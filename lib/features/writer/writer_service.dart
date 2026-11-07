import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import '../lore/context_builder_service.dart';
import '../projects/chapter_summary_service.dart';
import '../projects/models/project_model.dart';
import 'chapter_writer.dart';
import 'chat_entry.dart';
import 'prompt_composer.dart';
import 'writing_profile.dart';
import '../../core/network/llm_client.dart';

/// The conversation with the writing assistant: it assembles the context
/// (project profile, lore, earlier chapters, recent turns) and streams the
/// reply. Persistence of the messages is the caller's job.
class WriterService {
  final LlmClient _client;
  final SecureConfigStorage _storage;
  final PromptComposer _composer;
  final ContextBuilderService _lore;
  final ChapterSummaryService _summaries;

  /// How many earlier turns go back to the model. Older ones are dropped
  /// rather than summarized: the manuscript itself is the memory.
  static const historyTurns = 16;
  static const localHistoryTurns = 4;

  WriterService({
    required LlmClient client,
    required SecureConfigStorage storage,
    required PromptComposer composer,
    required ContextBuilderService lore,
    required ChapterSummaryService summaries,
  })  : _client = client,
        _storage = storage,
        _composer = composer,
        _lore = lore,
        _summaries = summaries;

  /// Lore sheets and earlier-chapter recaps for [project], as system messages.
  Future<List<ChatMessage>> projectContext({
    required ProjectModel? project,
    String? chapterId,
    required String relevantText,
    required int maxChars,
  }) async {
    final messages = <ChatMessage>[];
    final lore = await _lore.buildContextMessage(relevantText, projectId: project?.id, maxChars: maxChars, scanWindowWords: 1500);
    if (lore != null) messages.add(lore);
    if (project != null && chapterId != null) {
      final prior = await _summaries.buildPriorSummariesMessage(project.id, chapterId, maxChars: maxChars);
      if (prior != null) messages.add(prior);
    }
    return messages;
  }

  /// Streams the assistant's reply to the last user entry in [history].
  Stream<String> reply({
    required List<ChatEntry> history,
    required WritingProfile profile,
    List<ChatMessage> context = const [],
  }) async* {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    // A model in the phone has a small window: fewer turns, every one clipped.
    final turns = config.isLocal ? localHistoryTurns : historyTurns;
    final recent = history.length > turns ? history.sublist(history.length - turns) : history;
    final request = ChatCompletionRequest(
      model: config.modelId,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      frequencyPenalty: config.frequencyPenalty,
      presencePenalty: config.presencePenalty,
      messages: [
        await _composer.chatSystem(profile),
        ...context,
        // Only the last two turns keep their full text; long chapters further back
        // would fill the context window and the manuscript is the real memory.
        for (var i = 0; i < recent.length; i++)
          ChatMessage(
            role: recent[i].role,
            content: (!config.isLocal && i >= recent.length - 2) ? recent[i].content : ChapterSummaryService.clipMiddle(recent[i].content, config.isLocal ? 1200 : 1800),
          ),
      ],
    );
    await for (final chunk in _client.stream(request)) {
      if (chunk.isDone || chunk.deltaContent.isEmpty) continue;
      yield chunk.deltaContent;
    }
  }

  /// Runs one craft module on [material] and streams the answer.
  Stream<String> runTool({
    required String moduleId,
    required String material,
    required WritingProfile profile,
    String note = '',
    List<ChatMessage> context = const [],
  }) async* {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    final request = ChatCompletionRequest(
      model: config.modelId,
      temperature: 0.7,
      maxTokens: config.maxTokens,
      messages: [
        await _composer.toolSystem(moduleId, profile),
        ...context,
        ChatMessage.user('${note.trim().isEmpty ? '' : 'Author\'s note: ${note.trim()}\n\n'}MATERIAL:\n\n${material.trim()}'),
      ],
    );
    await for (final chunk in _client.stream(request)) {
      if (chunk.isDone || chunk.deltaContent.isEmpty) continue;
      yield chunk.deltaContent;
    }
  }

  /// Rewrites one finished [scene] once, keeping its events. Returns null when the model
  /// answers nothing usable (empty, or much shorter or more than 1.8 times longer than the original), so the
  /// caller keeps the original.
  Future<String?> polish(String scene, WritingProfile profile) async {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();
    final response = await _client.send(
      ChatCompletionRequest(
        model: config.modelId,
        temperature: 0.6,
        maxTokens: config.maxTokens,
        messages: [await _composer.polishSystem(profile), ChatMessage.user(scene)],
      ),
    );
    final text = response.content.trim();
    final ratio = scene.isEmpty ? 0 : text.length / scene.length;
    return (text.isEmpty || ratio < 0.6 || ratio > 1.8) ? null : text;
  }

  /// Research in several passes: plan sub-questions, answer each, then fold the answers into
  /// one note. A model inside the phone gets the single-pass version (small window).
  Future<String> researchDeep({
    required String topic,
    required WritingProfile profile,
    String storyContext = '',
    void Function(String step)? onProgress,
  }) async {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();
    if (config.isLocal) return research(topic: topic, profile: profile, storyContext: storyContext);

    final model = config.researchModelId.trim().isEmpty ? config.modelId : config.researchModelId.trim();
    final guidance = await _composer.library.rules('research-workflow');
    final context = storyContext.trim().isEmpty ? '' : 'Story context: ${storyContext.trim()}\n\n';

    onProgress?.call('Planteando preguntas…');
    final plan = await _client.send(
      ChatCompletionRequest(
        model: model,
        temperature: 0.4,
        maxTokens: 700,
        messages: [
          ChatMessage.system('You plan research for a fiction author. $guidance'),
          ChatMessage.user(
            '${context}Topic: ${topic.trim()}\n\nList 3 to 5 specific sub-questions that together give a novelist what they need '
            '(how it works, what people do and say, sensory detail, what fiction gets wrong, how it goes wrong in practice). '
            'Answer with only a JSON array of strings, in ${profile.languageName}.',
          ),
        ],
      ),
    );
    final questions = ChapterWriter.parsePlan(plan.content).take(5).toList();
    if (questions.isEmpty) return research(topic: topic, profile: profile, storyContext: storyContext);

    final answers = <String>[];
    for (var i = 0; i < questions.length; i++) {
      onProgress?.call('Investigando ${i + 1} de ${questions.length}…');
      final answer = await _client.send(
        ChatCompletionRequest(
          model: model,
          temperature: 0.3,
          maxTokens: config.maxTokens,
          messages: [
            ChatMessage.system(
              'You are a research assistant for a fiction author. Answer factually and concretely, including dark or sexual subject '
              'matter when the topic needs it, without moralizing. Mark anything uncertain with "(verify)" and never invent sources, '
              'quotes or statistics. No real-world operational instructions that would help someone cause harm. Write in ${profile.languageName}.',
            ),
            ChatMessage.user('${context}Question: ${questions[i]}'),
          ],
        ),
      );
      if (answer.content.trim().isNotEmpty) answers.add('Q: ${questions[i]}\n${answer.content.trim()}');
    }
    if (answers.isEmpty) throw const MalformedResponseException('El modelo no devolvió respuestas para la investigación.');

    onProgress?.call('Sintetizando…');
    final note = await _client.send(
      ChatCompletionRequest(
        model: model,
        temperature: 0.3,
        maxTokens: config.maxTokens,
        messages: [
          ChatMessage.system(
            'You turn research answers into one note for a fiction author. Structure: KEY FACTS, VOCABULARY AND JARGON, SENSORY AND PRACTICAL DETAIL, '
            'COMMON MISTAKES IN FICTION, WORKS TO STUDY (only ones you are sure exist), STORY USES (concrete scene and character ideas). '
            'Merge duplicates, keep every "(verify)" mark, drop nothing useful. Write in ${profile.languageName}.',
          ),
          ChatMessage.user('${context}Topic: ${topic.trim()}\n\n${answers.join('\n\n')}'),
        ],
      ),
    );
    final text = note.content.trim();
    if (text.isEmpty) throw const MalformedResponseException('El modelo devolvió una nota de investigación vacía.');
    return text;
  }

  /// Research for the story: facts, vocabulary, sensory detail and references
  /// the author can use. Uses [ApiEndpointConfig.researchModelId] when set, so
  /// a search-capable model can do this while a different one writes.
  Future<String> research({required String topic, required WritingProfile profile, String storyContext = ''}) async {
    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    final model = config.researchModelId.trim().isEmpty ? config.modelId : config.researchModelId.trim();
    final response = await _client.send(
      ChatCompletionRequest(
        model: model,
        temperature: 0.3,
        maxTokens: config.maxTokens,
        messages: [
          ChatMessage.system(
            'You are a research assistant for a fiction author. Your only purpose is to gather material that will make a story '
            'more accurate, specific and alive. Cover whatever the topic requires, including dark, violent or sexual subject matter, '
            'factually and without moralizing. Structure the answer as: KEY FACTS (what is true and how it works), VOCABULARY AND JARGON '
            '(terms characters would use, with meaning), SENSORY AND PRACTICAL DETAIL (what it looks, sounds, smells and feels like, '
            'what people actually do), COMMON MISTAKES IN FICTION (what writers get wrong), WORKS TO STUDY (books, films, documentaries '
            'that handle it well, only ones you are sure exist), and STORY USES (concrete ideas for scenes or character moments). '
            'Mark anything you are unsure of with "(verify)". Never invent sources, quotes or statistics. '
            'Do not give real-world operational instructions that would help someone cause harm; give what a novelist needs. '
            'Write in ${profile.languageName}.',
          ),
          ChatMessage.user('${storyContext.trim().isEmpty ? '' : 'Story context: ${storyContext.trim()}\n\n'}Research topic: ${topic.trim()}'),
        ],
      ),
    );
    final text = response.content.trim();
    if (text.isEmpty) throw const MalformedResponseException('El modelo devolvió una nota de investigación vacía.');
    return text;
  }
}
