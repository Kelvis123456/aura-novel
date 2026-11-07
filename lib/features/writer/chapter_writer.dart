import 'dart:convert';

import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import 'prompt_composer.dart';
import 'writing_profile.dart';
import '../../core/network/llm_client.dart';

sealed class WriterEvent {
  const WriterEvent();
}

/// The scene plan, before any prose.
class PlanReady extends WriterEvent {
  final List<String> beats;
  const PlanReady(this.beats);
}

class SegmentStarted extends WriterEvent {
  final int index;
  final int total;
  const SegmentStarted(this.index, this.total);
}

/// A piece of prose, in order. Append it to what you already have.
class ProseDelta extends WriterEvent {
  final String text;
  const ProseDelta(this.text);
}

class WriterFinished extends WriterEvent {
  final int words;
  const WriterFinished(this.words);
}

/// Writes a long piece of prose in several model calls, because no single call
/// returns thousands of words. It plans the scenes, then writes them one at a
/// time, each call seeing the plan and the end of what is already written.
class ChapterWriter {
  final LlmClient _client;
  final SecureConfigStorage _storage;
  final PromptComposer _composer;

  /// Words aimed at per call. Below this a model tends to summarize; above it
  /// many providers cut the answer off.
  static const wordsPerScene = 900;
  static const maxScenes = 14;

  /// How much of the written text each call gets back as context.
  static const tailChars = 6000;

  /// The same, for a model inside the phone (6k tokens of context in all).
  static const localTailChars = 2400;

  ChapterWriter({
    required LlmClient client,
    required SecureConfigStorage storage,
    required PromptComposer composer,
  })  : _client = client,
        _storage = storage,
        _composer = composer;

  static int sceneCount(int targetWords) => (targetWords / wordsPerScene).ceil().clamp(1, maxScenes);

  static int countWords(String text) {
    final t = text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  /// Extracts the list of scene beats from the planner's answer. Accepts a
  /// JSON array (possibly inside a code fence) or a numbered/bulleted list.
  static List<String> parsePlan(String raw) {
    final text = raw.trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is List) {
          final beats = decoded.map((e) => e is String ? e : (e is Map ? (e['beat'] ?? e['scene'] ?? e['summary'] ?? '').toString() : e.toString())).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (beats.isNotEmpty) return beats;
        }
      } on FormatException {
        // fall through to the line-based reading
      }
    }
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('```') && l != '[' && l != ']').toList();
    final marker = RegExp(r'^(?:[-*•]|\d+[.)])\s+');
    // With a list in the answer, only the list items are scenes: an intro line is not one.
    final items = lines.where(marker.hasMatch).toList();
    return (items.isNotEmpty ? items : lines)
        .map((l) => l.replaceFirst(marker, '').replaceAll(RegExp(r'^["\x27]+|["\x27,]+$'), '').trim())
        .where((l) => l.length > 3)
        .toList();
  }

  /// Streams the plan and then the prose. [context] are extra system messages
  /// (lore, recaps, research); [existingText] is what the chapter already has.
  Stream<WriterEvent> write({
    required String instruction,
    required int targetWords,
    required WritingProfile profile,
    List<ChatMessage> context = const [],
    String existingText = '',
  }) async* {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    final system = await _composer.proseSystem(profile, longForm: true);
    final tailLimit = config.isLocal ? localTailChars : tailChars;
    final scenes = sceneCount(targetWords);

    final beats = scenes == 1 ? [instruction.trim()] : await _plan(config, system, context, instruction, scenes, existingText);
    yield PlanReady(beats);

    // A plan with fewer scenes than asked must not stretch one call past what it can return.
    final perScene = (targetWords / beats.length).round().clamp(100, (wordsPerScene * 1.4).round());
    var written = existingText;
    var newWords = 0;

    for (var i = 0; i < beats.length; i++) {
      yield SegmentStarted(i, beats.length);
      final isLast = i == beats.length - 1;
      final tail = written.length > tailLimit ? written.substring(written.length - tailLimit) : written;

      final prompt = StringBuffer()
        ..writeln('CHAPTER BRIEF: ${instruction.trim()}')
        ..writeln();
      if (beats.length > 1) {
        prompt.writeln('SCENE PLAN:');
        for (var b = 0; b < beats.length; b++) {
          prompt.writeln('${b + 1}. ${beats[b]}${b == i ? '   <- write this one now' : ''}');
        }
        prompt.writeln();
      }
      if (tail.trim().isNotEmpty) {
        prompt
          ..writeln('TEXT SO FAR (do not repeat it; continue seamlessly after its last line):')
          ..writeln(tail)
          ..writeln();
      }
      prompt
        ..writeln('NOW WRITE ${beats.length > 1 ? 'scene ${i + 1} of ${beats.length}' : 'the piece'}: ${beats[i]}')
        ..writeln('Length: about $perScene words of finished prose, fully dramatized.')
        ..writeln(isLast
            ? 'This is the final part: bring it to a satisfying close that fits the chapter.'
            : 'More follows after this part: do not conclude, summarize or wrap up. End mid-motion.')
        ..writeln(written.trim().isEmpty
            ? 'Start directly with the prose, with no scene-break marker. Output only the prose.'
            : 'If this part starts a new scene, begin with a line containing * * * . Output only the prose.');

      final request = ChatCompletionRequest(
        model: config.modelId,
        temperature: config.temperature,
        maxTokens: _maxTokensFor(perScene, config.maxTokens),
        frequencyPenalty: config.frequencyPenalty,
        presencePenalty: config.presencePenalty,
        messages: [system, ...context, ChatMessage.user(prompt.toString())],
      );

      final separator = written.trim().isEmpty ? '' : '\n\n';
      var segment = StringBuffer();
      var first = true;
      await for (final chunk in _client.stream(request)) {
        if (chunk.isDone || chunk.deltaContent.isEmpty) continue;
        var text = chunk.deltaContent;
        if (first) {
          text = separator + text.trimLeft();
          first = false;
        }
        segment.write(text);
        yield ProseDelta(text);
      }
      if (segment.isEmpty) throw const MalformedResponseException('El modelo no devolvió texto para una escena.');
      written += segment.toString();
      newWords += countWords(segment.toString());
    }
    yield WriterFinished(newWords);
  }

  Future<List<String>> _plan(
    ApiEndpointConfig config,
    ChatMessage system,
    List<ChatMessage> context,
    String instruction,
    int scenes,
    String existingText,
  ) async {
    final tail = existingText.length > tailChars ? existingText.substring(existingText.length - tailChars) : existingText;
    final response = await _client.send(
      ChatCompletionRequest(
        model: config.modelId,
        temperature: 0.7,
        maxTokens: 900,
        messages: [
          system,
          ...context,
          ChatMessage.user(
            'Plan a chapter as exactly $scenes consecutive scenes that together cover this brief:\n\n'
            '${instruction.trim()}\n\n'
            '${tail.trim().isEmpty ? '' : 'The chapter already has this text; plan what comes next:\n$tail\n\n'}'
            'Each scene is one or two sentences: who wants what, what stands in the way, how it turns. '
            'Escalate across scenes and avoid repeating the same beat. '
            'Answer with only a JSON array of $scenes strings, in the language of the brief.',
          ),
        ],
      ),
    );
    final beats = parsePlan(response.content);
    if (beats.isEmpty) throw const MalformedResponseException('El modelo devolvió un plan de escenas ilegible.');
    // A model that returns too many or too few still gives a usable plan.
    return beats.length > scenes ? beats.sublist(0, scenes) : beats;
  }

  /// Roughly 1.8 tokens per word covers Spanish; the user's own cap wins.
  static int _maxTokensFor(int words, int configured) {
    final needed = (words * 2.2).ceil() + 200;
    return needed < configured ? needed : configured;
  }
}
