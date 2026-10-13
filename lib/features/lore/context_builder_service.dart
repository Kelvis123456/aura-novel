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

  /// Cap for the rendered block (~750 tokens). Without it a big lore base
  /// would eat the whole prompt budget on every generation.
  static const defaultMaxContextChars = 3000;

  ContextBuilderService({required LoreRepository repository}) : _repository = repository;

  /// Returns null when nothing relevant was detected and no entry is pinned
  /// — callers should skip adding a context message in that case.
  Future<ChatMessage?> buildContextMessage(
    String fullText, {
    int scanWindowWords = _defaultScanWindowWords,
    int maxChars = defaultMaxContextChars,
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

    // Pinned entries first so they survive the cap; among the rest, the
    // mentioned characters go before lore (they carry the coherence rules).
    final entries = [
      for (final c in activeCharacters.where((c) => c.forceInclude)) _renderCharacter(c, nameById),
      for (final l in activeLore.where((l) => l.forceInclude)) _renderLore(l),
      for (final c in activeCharacters.where((c) => !c.forceInclude)) _renderCharacter(c, nameById),
      for (final l in activeLore.where((l) => !l.forceInclude)) _renderLore(l),
    ];

    const header = '[INFORMACIÓN DE CONTEXTO DEL MUNDO - REGLAS DE COHERENCIA]';
    final buffer = StringBuffer(header);
    for (final entry in entries) {
      if (buffer.length + entry.length + 1 > maxChars) continue;
      buffer
        ..writeln()
        ..write(entry);
    }

    // Everything was too big for the cap: nothing useful to send.
    if (buffer.length == header.length) return null;
    return ChatMessage.system(buffer.toString().trim());
  }

  String _renderCharacter(CharacterModel c, Map<String, String> nameById) {
    final buffer = StringBuffer();
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
    return buffer.toString().trimRight();
  }

  String _renderLore(LoreItemModel l) {
    final description = l.shortDescription.trim().isEmpty ? l.longDetails.trim() : l.shortDescription.trim();
    return '- ${l.category.label} relevante: ${l.name} ($description)';
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
