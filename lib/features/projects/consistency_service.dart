import '../../core/network/dynamic_openai_client.dart';
import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import '../lore/context_builder_service.dart';
import 'chapter_summary_service.dart';
import 'models/project_model.dart';
import 'project_repository.dart';

/// Asks the model to compare a chapter against the lore sheets and the
/// recaps of earlier chapters, and lists what contradicts them.
class ConsistencyService {
  final DynamicOpenAIClient _client;
  final ProjectRepository _repository;
  final ContextBuilderService _contextBuilder;
  final ChapterSummaryService _summaries;
  final SecureConfigStorage _storage;

  /// Marker the model must answer with when it finds nothing. Parsed, so
  /// it lives here and not only in the prompt.
  static const noIssuesMarker = 'SIN_CONTRADICCIONES';

  ConsistencyService({
    required DynamicOpenAIClient client,
    required ProjectRepository repository,
    required ContextBuilderService contextBuilder,
    required ChapterSummaryService summaries,
    required SecureConfigStorage storage,
  })  : _client = client,
        _repository = repository,
        _contextBuilder = contextBuilder,
        _summaries = summaries,
        _storage = storage;

  /// Returns the contradictions found (empty list = none), or null when the
  /// chapter has no text yet.
  Future<List<String>?> check(ChapterModel chapter) async {
    final node = await _repository.getLatestNodeForChapter(chapter.id);
    final text = node?.content.trim() ?? '';
    if (text.isEmpty) return null;

    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    final clipped = ChapterSummaryService.clipMiddle(text, ChapterSummaryService.maxInputChars);
    // Scan the whole chapter for names, not just the last 400 words the editor uses.
    final lore = await _contextBuilder.buildContextMessage(clipped, scanWindowWords: 100000, maxChars: config.contextChars, projectId: chapter.projectId);
    final prior = await _summaries.buildPriorSummariesMessage(chapter.projectId, chapter.id, maxChars: config.contextChars);

    final response = await _client.send(
      ChatCompletionRequest(
        model: config.modelId,
        temperature: 0.2,
        maxTokens: 600,
        messages: [
          ChatMessage.system(
            'Revisas la coherencia de un capítulo de novela contra las fichas del mundo y '
            'los resúmenes de capítulos anteriores. Lista solo contradicciones claras '
            '(edad, apariencia, relaciones, lugares, hechos ya ocurridos, secretos revelados '
            'antes de tiempo), una por línea y empezando con "- ". Cita el dato del capítulo '
            'y el dato con el que choca. No corrijas el estilo ni inventes problemas. '
            'Si no hay ninguna, responde solo $noIssuesMarker.',
          ),
          if (lore != null) lore,
          if (prior != null) prior,
          ChatMessage.user('Capítulo "${chapter.title}":\n\n$clipped'),
        ],
      ),
    );
    return parseIssues(response.content);
  }

  static List<String> parseIssues(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    final bullets = trimmed
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('- ') || l.startsWith('* '))
        .map((l) => l.substring(2).trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (bullets.isNotEmpty) return bullets;
    // The marker only means "nothing found" when no contradiction was listed.
    if (trimmed.contains(noIssuesMarker)) return const [];
    // A model that ignored the bullet format still said something: keep it whole.
    return [trimmed];
  }
}
