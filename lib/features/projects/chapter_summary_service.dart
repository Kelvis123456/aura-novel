import '../../core/network/dynamic_openai_client.dart';
import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import 'models/project_model.dart';
import 'project_repository.dart';

/// Writes and reads the per-chapter recaps that stand in for earlier
/// chapters in the prompt, so a long novel doesn't need to fit in it.
class ChapterSummaryService {
  final DynamicOpenAIClient _client;
  final ProjectRepository _repository;
  final SecureConfigStorage _storage;

  static const maxInputChars = 16000;
  static const defaultMaxContextChars = 3000;

  ChapterSummaryService({
    required DynamicOpenAIClient client,
    required ProjectRepository repository,
    required SecureConfigStorage storage,
  })  : _client = client,
        _repository = repository,
        _storage = storage;

  /// Summarizes the chapter's latest saved version and stores the result.
  /// Returns null when the chapter has no text yet.
  Future<String?> summarize(ChapterModel chapter) async {
    final node = await _repository.getLatestNodeForChapter(chapter.id);
    final text = node?.content.trim() ?? '';
    if (text.isEmpty) return null;

    final config = await _storage.load();
    if (config == null || !config.isComplete) throw const MissingConfigException();

    final response = await _client.send(
      ChatCompletionRequest(
        model: config.modelId,
        temperature: 0.3,
        maxTokens: 300,
        messages: [
          ChatMessage.system(
            'Resumes capítulos de una novela para que otro escritor retome la historia. '
            'Resume en un solo párrafo de 4 a 6 frases: hechos clave, estado de los '
            'personajes y cabos sueltos. Sin comentarios ni metatexto.',
          ),
          ChatMessage.user('Capítulo "${chapter.title}":\n\n${clipMiddle(text, maxInputChars)}'),
        ],
      ),
    );

    final summary = response.content.trim();
    if (summary.isEmpty) throw const MalformedResponseException('The model returned an empty summary.');
    await _repository.updateChapterSummary(chapter.id, summary);
    return summary;
  }

  /// System message with the recaps of the chapters before [chapterId], or
  /// null if there are none. When they exceed [maxChars], the oldest drop
  /// first: the nearest chapters matter most for continuity.
  Future<ChatMessage?> buildPriorSummariesMessage(
    String projectId,
    String chapterId, {
    int maxChars = defaultMaxContextChars,
  }) async {
    final chapters = await _repository.getChaptersForProject(projectId);
    final currentIndex = chapters.indexWhere((c) => c.id == chapterId);
    if (currentIndex <= 0) return null;

    final lines = <String>[];
    var used = 0;
    for (final chapter in chapters.take(currentIndex).toList().reversed) {
      if (chapter.summary.trim().isEmpty) continue;
      final line = '- ${chapter.title}: ${chapter.summary.trim()}';
      if (used + line.length > maxChars) break;
      lines.insert(0, line);
      used += line.length;
    }
    if (lines.isEmpty) return null;

    return ChatMessage.system('[RESUMEN DE CAPÍTULOS ANTERIORES]\n${lines.join('\n')}');
  }

  /// Keeps the start and the end of [text] when it is longer than [max].
  static String clipMiddle(String text, int max) {
    if (text.length <= max) return text;
    final half = max ~/ 2;
    return '${text.substring(0, half)}\n[…]\n${text.substring(text.length - half)}';
  }
}
