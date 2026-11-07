import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../../features/local_model/local_model_catalog.dart';
import '../../features/local_model/local_model_manager.dart';
import '../storage/secure_config_storage.dart';
import 'exceptions/api_exceptions.dart';
import 'llm_client.dart';
import 'models/chat_completion_request.dart';
import 'models/chat_completion_response.dart';
import 'models/chat_message.dart';

/// Runs the downloaded model inside the phone with llama.cpp and speaks the
/// same interface as the remote client. One request at a time: the model has
/// a single context, so a second request waits for the first.
class LocalLlmClient implements LlmClient {
  final SecureConfigStorage _storage;
  final LocalModelManager _manager;

  /// Tokens of context the model is loaded with. Bigger needs more RAM.
  static const contextSize = 6144;

  LlamaEngine? _engine;
  String? _loadedId;
  Future<void> _queue = Future<void>.value();

  LocalLlmClient({required SecureConfigStorage storage, required LocalModelManager manager})
      : _storage = storage,
        _manager = manager;

  /// Role mapping, kept apart so it can be tested without the native runtime.
  static String roleName(String role) => switch (role) {
        ChatRole.system => 'system',
        ChatRole.assistant => 'assistant',
        _ => 'user',
      };

  Future<LlamaEngine> _engineFor(String modelId) async {
    if (_engine != null && _loadedId == modelId) return _engine!;
    final info = LocalModelCatalog.byId(modelId);
    if (info == null) throw const MissingConfigException('El modelo local elegido ya no existe. Elige otro en Ajustes de API.');
    final file = await _manager.fileFor(info);
    if (!file.existsSync()) {
      throw const MissingConfigException('El modelo local no está descargado. Descárgalo en Ajustes de API.');
    }
    await _release();
    try {
      _engine = await LlamaEngine.load(
        LlamaModel(ModelSource.parse(file.path)),
        params: const ModelParams(contextSize: contextSize),
      );
    } on Object catch (e) {
      throw MalformedResponseException('No se pudo cargar el modelo local: $e');
    }
    _loadedId = modelId;
    return _engine!;
  }

  Future<void> _release() async {
    final engine = _engine;
    _engine = null;
    _loadedId = null;
    if (engine != null) await engine.dispose();
  }

  List<LlamaChatMessage> _toLlama(List<ChatMessage> messages) {
    // Several leading system messages (persona, lore, recaps) become one: small
    // chat templates accept a single system turn.
    final system = messages.where((m) => m.role == ChatRole.system).map((m) => m.content).join('\n\n');
    return [
      if (system.isNotEmpty) LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
      for (final m in messages.where((m) => m.role != ChatRole.system))
        LlamaChatMessage.fromText(role: roleName(m.role) == 'assistant' ? LlamaChatRole.assistant : LlamaChatRole.user, text: m.content),
    ];
  }

  @override
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) async* {
    final config = await _storage.load();
    if (config == null || !config.isLocal || config.localModelId.isEmpty) throw const MissingConfigException();

    // Wait for the previous request, then hold the queue until this one ends.
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      final engine = await _engineFor(config.localModelId);
      final params = GenerationParams(
        maxTokens: request.maxTokens ?? 1024,
        temp: request.temperature ?? 0.8,
        topP: request.topP ?? 0.95,
        penalty: 1.1 + (request.frequencyPenalty ?? 0).clamp(0.0, 1.0) * 0.1,
        presencePenalty: (request.presencePenalty ?? 0).clamp(0.0, 1.0),
      );
      try {
        await for (final text in engine.create(_toLlama(request.messages), params: params).textDeltas()) {
          yield ChatCompletionChunk(deltaContent: text);
        }
      } on ApiClientException {
        rethrow;
      } on Object catch (e) {
        throw MalformedResponseException('El modelo local falló al escribir: $e');
      }
      yield ChatCompletionChunk.done();
    } finally {
      done.complete();
    }
  }

  @override
  Future<ChatCompletionResponse> send(ChatCompletionRequest request) async {
    final buffer = StringBuffer();
    await for (final chunk in stream(request)) {
      buffer.write(chunk.deltaContent);
    }
    return ChatCompletionResponse(id: 'local', model: request.model, content: buffer.toString());
  }

  /// Loads the model and writes a few tokens, for the settings screen to check it works.
  Future<void> selfTest(String modelId) async {
    final engine = await _engineFor(modelId);
    await engine.create([const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Di hola.')], params: const GenerationParams(maxTokens: 8)).text();
  }

  /// Frees the model's memory (before deleting its file, or on a provider switch).
  Future<void> unload() => _release();

  @override
  void dispose() {
    unawaited(_release());
  }
}
