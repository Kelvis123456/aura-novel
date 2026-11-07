import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import '../lore/context_builder_service.dart';
import '../projects/chapter_summary_service.dart';
import '../projects/models/project_model.dart';
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
