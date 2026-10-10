import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/dynamic_openai_client.dart';
import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_completion_response.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import '../lore/context_builder_service.dart';

enum GenerationStatus { idle, generating, paused, error }

/// Quick tone-shift presets offered by the "Cambiar Tono" contextual action.
enum ToneShift { tense, lighter, darker, sensory, faster }

extension ToneShiftPreset on ToneShift {
  String get label => switch (this) {
        ToneShift.tense => 'Más tenso',
        ToneShift.lighter => 'Más ligero',
        ToneShift.darker => 'Más oscuro',
        ToneShift.sensory => 'Más sensorial',
        ToneShift.faster => 'Más rápido',
      };

  String get instruction => switch (this) {
        ToneShift.tense => 'Aumenta la tensión y el conflicto de la escena.',
        ToneShift.lighter => 'Aligera el tono, hazlo más ameno y distendido.',
        ToneShift.darker => 'Oscurece la atmósfera de la escena.',
        ToneShift.sensory => 'Añade más detalle sensorial y descriptivo.',
        ToneShift.faster => 'Acelera el ritmo narrativo, frases más cortas.',
      };
}

const _contextWindowChars = 4000;
const _wordsPerMinute = 200;
const _charsPerToken = 4;

/// Drives the immersive editor: owns the document buffer, streams AI
/// generations from [DynamicOpenAIClient] straight into it token-by-token,
/// and exposes the live word/char/reading-time stats the top bar shows.
class EditorController extends ChangeNotifier {
  final DynamicOpenAIClient _client;
  final bool _ownsClient;
  final SecureConfigStorage _storage;
  final ContextBuilderService? _contextBuilder;
  final Future<ChatMessage?> Function()? _storyContext;

  /// [client]/[storage]/[contextBuilder] are normally the shared instances
  /// from [AppScope] — pass none to let this controller create (and own)
  /// its own client, e.g. in isolated tests.
  EditorController({
    DynamicOpenAIClient? client,
    SecureConfigStorage? storage,
    ContextBuilderService? contextBuilder,
    Future<ChatMessage?> Function()? storyContext,
  })  : _client = client ?? DynamicOpenAIClient(),
        _ownsClient = client == null,
        _storage = storage ?? SecureConfigStorage(),
        _contextBuilder = contextBuilder,
        _storyContext = storyContext {
    textController.addListener(notifyListeners);
  }

  /// Owns both the document text and the current selection/cursor, so
  /// contextual actions (rewrite/expand/tone) and streaming insertion share
  /// a single source of truth.
  final TextEditingController textController = TextEditingController();

  GenerationStatus status = GenerationStatus.idle;
  String? errorMessage;

  /// Rough token spend of this editing session (about 4 characters per token),
  /// shown so the author notices cost on their own API key. Providers report
  /// exact usage differently in streams, so this stays an estimate.
  int estimatedSessionTokens = 0;
  int _generatedChars = 0;
  bool distractionFreeMode = false;

  StreamSubscription<ChatCompletionChunk>? _subscription;
  int _cursor = 0;

  bool get isGenerating => status == GenerationStatus.generating;

  int get wordCount {
    final trimmed = textController.text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  int get charCount => textController.text.length;

  int get estimatedReadingMinutes {
    if (wordCount == 0) return 0;
    final minutes = wordCount / _wordsPerMinute;
    return minutes < 1 ? 1 : minutes.round();
  }

  void toggleDistractionFree() {
    distractionFreeMode = !distractionFreeMode;
    notifyListeners();
  }

  String _recentContext() {
    final text = textController.text;
    if (text.length <= _contextWindowChars) return text;
    return text.substring(text.length - _contextWindowChars);
  }

  Future<ChatCompletionRequest> _buildRequest(List<ChatMessage> messages) async {
    final config = await _storage.load();
    if (config == null || !config.isComplete) {
      throw const MissingConfigException();
    }

    final resolvedMessages = await _withWorldContext(messages);

    return ChatCompletionRequest(
      model: config.modelId,
      messages: resolvedMessages,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      frequencyPenalty: config.frequencyPenalty,
      presencePenalty: config.presencePenalty,
    );
  }

  /// Inserts the earlier-chapter recaps and the Lore Studio's world-context
  /// system messages (the latter only if any character/lore entry is detected or pinned) right after the leading
  /// persona system message(s) and before the user's own instruction.
  Future<List<ChatMessage>> _withWorldContext(List<ChatMessage> messages) async {
    final contextMessages = [
      await _storyContext?.call(),
      await _contextBuilder?.buildContextMessage(textController.text),
    ].whereType<ChatMessage>().toList();
    if (contextMessages.isEmpty) return messages;

    final resolved = List<ChatMessage>.from(messages);
    final insertIndex = resolved.indexWhere((m) => m.role != ChatRole.system);
    resolved.insertAll(insertIndex < 0 ? resolved.length : insertIndex, contextMessages);
    return resolved;
  }

  /// Sends the current chapter context as a `user` prompt and appends the
  /// model's continuation at the end of the document.
  Future<void> continueStory() async {
    final context = _recentContext();
    final messages = [
      ChatMessage.system(
        'Eres un asistente de escritura creativa. Continúa la historia manteniendo '
        'la voz, el tono y la coherencia de personajes ya establecidos. Responde '
        'únicamente con la continuación narrativa, sin comentarios ni metatexto.',
      ),
      ChatMessage.user(
        context.trim().isEmpty
            ? 'Empieza la historia con una escena de apertura.'
            : 'Continúa la historia a partir de este fragmento:\n\n$context',
      ),
    ];
    await _runAppendGeneration(messages);
  }

  /// Sends a free-form hot instruction from the floating prompt bar
  /// (e.g. "Aumenta la tensión") and appends the result.
  Future<void> generateCustomPrompt(String userInstruction) async {
    final instruction = userInstruction.trim();
    if (instruction.isEmpty) return;

    final context = _recentContext();
    final messages = [
      ChatMessage.system(
        'Eres un asistente de escritura creativa. Sigue la instrucción del autor '
        'y continúa el texto de forma coherente con el fragmento dado. Responde '
        'únicamente con la continuación narrativa.',
      ),
      ChatMessage.user('Fragmento actual:\n\n$context\n\nInstrucción: $instruction'),
    ];
    await _runAppendGeneration(messages);
  }

  /// Replaces the selected block with a rewritten variant.
  Future<void> rewriteSelection() => _runSelectionGeneration(
        (selected) => 'Reescribe el siguiente fragmento manteniendo su significado '
            'pero con nuevas palabras y ritmo:\n\n"$selected"',
      );

  /// Expands the selected block with more sensory/narrative detail.
  Future<void> expandSelection() => _runSelectionGeneration(
        (selected) => 'Expande el siguiente fragmento añadiendo más detalle, '
            'sensación y matiz, sin cambiar los hechos narrados:\n\n"$selected"',
      );

  /// Rewrites the selected block shifted toward one of the [ToneShift] presets.
  Future<void> changeSelectionTone(ToneShift tone) => _runSelectionGeneration(
        (selected) => '${tone.instruction} Reescribe este fragmento con ese '
            'ajuste de tono:\n\n"$selected"',
      );

  Future<void> _runSelectionGeneration(String Function(String selected) buildInstruction) async {
    final selection = textController.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selected = selection.textInside(textController.text);
    if (selected.trim().isEmpty) return;

    final messages = [
      ChatMessage.system(
        'Eres un asistente de escritura creativa. Responde únicamente con el '
        'texto de reemplazo, sin comillas ni comentarios adicionales.',
      ),
      ChatMessage.user(buildInstruction(selected)),
    ];

    await _runReplaceGeneration(start: selection.start, end: selection.end, messages: messages);
  }

  Future<void> _runAppendGeneration(List<ChatMessage> messages) async {
    final end = textController.text.length;
    await _runReplaceGeneration(start: end, end: end, messages: messages);
  }

  /// Core streaming loop: deletes `[start, end)`, then inserts each SSE
  /// delta at that same position as it arrives.
  Future<void> _runReplaceGeneration({
    required int start,
    required int end,
    required List<ChatMessage> messages,
  }) async {
    if (status == GenerationStatus.generating) return;

    ChatCompletionRequest request;
    try {
      request = await _buildRequest(messages);
    } on ApiClientException catch (e) {
      status = GenerationStatus.error;
      errorMessage = e.message;
      notifyListeners();
      return;
    }

    estimatedSessionTokens +=
        request.messages.fold<int>(0, (sum, m) => sum + m.content.length) ~/ _charsPerToken;
    _generatedChars = 0;
    _deleteRange(start, end);
    _cursor = start;
    status = GenerationStatus.generating;
    errorMessage = null;
    notifyListeners();

    _subscription = _client.stream(request).listen(
      (chunk) {
        if (chunk.isDone || chunk.deltaContent.isEmpty) return;
        _insertAtCursor(chunk.deltaContent);
        _generatedChars += chunk.deltaContent.length;
      },
      onError: (error) {
        status = GenerationStatus.error;
        final reason =
            error is ApiClientException ? error.message : 'Error inesperado durante la generación.';
        errorMessage = _generatedChars > 0 ? '$reason Se conservó el texto que ya había llegado.' : reason;
        estimatedSessionTokens += _generatedChars ~/ _charsPerToken;
        notifyListeners();
      },
      onDone: () {
        if (status == GenerationStatus.generating) {
          status = GenerationStatus.idle;
          estimatedSessionTokens += _generatedChars ~/ _charsPerToken;
          notifyListeners();
        }
      },
      cancelOnError: true,
    );
  }

  /// Stops the in-flight HTTP stream. The text generated so far is kept.
  void cancelGeneration() {
    _subscription?.cancel();
    _subscription = null;
    if (status == GenerationStatus.generating) {
      status = GenerationStatus.paused;
      estimatedSessionTokens += _generatedChars ~/ _charsPerToken;
      notifyListeners();
    }
  }

  void _deleteRange(int start, int end) {
    if (start == end) return;
    final text = textController.text;
    final newText = text.replaceRange(start, end, '');
    textController.value = textController.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );
  }

  void _insertAtCursor(String delta) {
    final text = textController.text;
    final safeCursor = _cursor.clamp(0, text.length);
    final newText = text.replaceRange(safeCursor, safeCursor, delta);
    final newCursor = safeCursor + delta.length;

    textController.value = textController.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
    _cursor = newCursor;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    textController.removeListener(notifyListeners);
    textController.dispose();
    if (_ownsClient) _client.dispose();
    super.dispose();
  }
}
