import '../../core/network/models/chat_message.dart';
import 'lore_repository.dart';
import 'models/character_model.dart';
import 'models/lore_item_model.dart';

/// Scans the most recent text in the editor for character names/aliases and
/// lore tags, then compiles whatever is detected (plus anything pinned via
/// "Forzar inclusión") into a single `system` [ChatMessage] the caller
/// prepends to its generation request.
class ContextBuilderService {
  final LoreRepository _repository;
  static const _defaultScanWindowWords = 400;

  ContextBuilderService({required LoreRepository repository}) : _repository = repository;

  /// Returns null when nothing relevant was detected and no entry is pinned
  /// — callers should skip adding a context message in that case.
  Future<ChatMessage?> buildContextMessage(
    String fullText, {
    int scanWindowWords = _defaultScanWindowWords,
  }) async {
    final window = _lastWords(fullText, scanWindowWords);

    final characters = await _repository.getAllCharacters();
    final loreItems = await _repository.getAllLoreItems();

    final activeCharacters = characters
        .where((c) => c.forceInclude || _mentionsAny(window, [c.name, ...c.aliases]))
        .toList();
    final activeLore = loreItems
        .where((l) => l.forceInclude || _mentionsAny(window, [l.name, ...l.tags]))
        .toList();

    if (activeCharacters.isEmpty && activeLore.isEmpty) return null;

    final nameById = {for (final c in characters) c.id: c.name};
    final block = _renderBlock(activeCharacters, activeLore, nameById);
    return ChatMessage.system(block);
  }

  String _renderBlock(
    List<CharacterModel> characters,
    List<LoreItemModel> loreItems,
    Map<String, String> nameById,
  ) {
    final buffer = StringBuffer()
      ..writeln('[INFORMACIÓN DE CONTEXTO DEL MUNDO - REGLAS DE COHERENCIA]');

    for (final c in characters) {
      final traits = c.personalityTraits.isEmpty ? 'sin rasgos definidos' : c.personalityTraits.join(', ');
      final motivation = c.motivation.trim().isEmpty ? 'sin motivación definida' : c.motivation.trim();
      final appearance = c.appearance.trim().isEmpty ? 'sin descripción física' : c.appearance.trim();
      buffer.writeln('- Personaje activo: ${c.name} ($appearance, $traits, $motivation)');

      if (c.secretsLimits.trim().isNotEmpty) {
        buffer.writeln('  Límites/secretos a respetar: ${c.secretsLimits.trim()}');
      }
      if (c.relationships.isNotEmpty) {
        final rel = c.relationships
            .map((r) => '${nameById[r.characterId] ?? r.characterId}: ${r.description}')
            .join('; ');
        buffer.writeln('  Relaciones: $rel');
      }
    }

    for (final l in loreItems) {
      final description = l.shortDescription.trim().isEmpty ? l.longDetails.trim() : l.shortDescription.trim();
      buffer.writeln('- ${l.category.label} relevante: ${l.name} ($description)');
    }

    return buffer.toString().trim();
  }

  String _lastWords(String text, int n) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length <= n) return trimmed;
    return words.sublist(words.length - n).join(' ');
  }

  bool _mentionsAny(String haystack, List<String> needles) {
    if (haystack.isEmpty) return false;
    for (final needle in needles) {
      final trimmed = needle.trim();
      if (trimmed.isEmpty) continue;
      final pattern = RegExp(r'\b' + RegExp.escape(trimmed) + r'\b', caseSensitive: false);
      if (pattern.hasMatch(haystack)) return true;
    }
    return false;
  }
}
