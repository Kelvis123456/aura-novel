import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import 'models/project_model.dart';
import 'project_repository.dart';
import '../../core/network/llm_client.dart';

/// Writes and reads the per-chapter recaps that stand in for earlier
/// chapters in the prompt, so a long novel doesn't need to fit in it.
class ChapterSummaryService {
  final LlmClient _client;
  final ProjectRepository _repository;
  final SecureConfigStorage _storage;

  /// Extra instructions for the recap (the summarization module). Null for a model with a small window.
  final Future<String?> Function()? _guidance;

  static const maxInputChars = 16000;
  static const defaultMaxContextChars = 3000;

  ChapterSummaryService({
    required LlmClient client,
    required ProjectRepository repository,
    required SecureConfigStorage storage,
    Future<String?> Function()? guidance,
  })  : _client = client,
        _repository = repository,
        _storage = storage,
        _guidance = guidance;

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
        maxTokens: 450,
        messages: [
          ChatMessage.system(
            'Resumes capítulos de una novela para que otro escritor retome la historia sin contradecirla. '
            'Escribe un solo párrafo de 5 a 8 frases con los hechos clave, el estado de cada personaje '
            '(heridas, objetos que lleva, lo que sabe y lo que ignora), las promesas y fechas mencionadas y los cabos sueltos. '
            'Sin comentarios ni metatexto.${await _guidance?.call() == null ? '' : '\n\nPrincipios de resumen:\n${await _guidance!.call()}'}',
          ),
          ChatMessage.user('Capítulo "${chapter.title}":\n\n${clipMiddle(text, maxInputChars)}'),
        ],
      ),
    );

    final summary = response.content.trim();
    if (summary.isEmpty) throw const MalformedResponseException('El modelo devolvió un resumen vacío.');
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
