import 'package:flutter/services.dart';

enum CraftGroup { prosa, estructura, personajes, mundo, publicar }

extension CraftGroupLabel on CraftGroup {
  String get label => switch (this) {
        CraftGroup.prosa => 'Prosa',
        CraftGroup.estructura => 'Estructura',
        CraftGroup.personajes => 'Personajes',
        CraftGroup.mundo => 'Mundo',
        CraftGroup.publicar => 'Publicar',
      };
}

/// One writing-craft module: a skill distilled into prompt text and bundled
/// in `assets/craft/<id>.md`. Modules the author can run on a passage appear as
/// tools in the assistant; [core] ones also shape every piece of prose.
class CraftModule {
  final String id;
  final String label;
  final String blurb;
  final CraftGroup group;
  final bool core;

  const CraftModule(this.id, this.label, this.blurb, this.group, {this.core = false});
}

class CraftLibrary {
  static const modules = [
    CraftModule('prose-style', 'Pulir prosa', 'Frases planas, ritmo y verbos débiles.', CraftGroup.prosa, core: true),
    CraftModule('dialogue', 'Diálogo', 'Voces distintas, subtexto, conversaciones vivas.', CraftGroup.prosa, core: true),
    CraftModule('cliche-transcendence', 'Romper clichés', 'Cambia lo predecible por algo propio.', CraftGroup.prosa, core: true),
    CraftModule('humanizer', 'Quitar tics de IA', 'Limpia el texto que suena a máquina.', CraftGroup.prosa, core: true),
    CraftModule('long-form-style', 'Estilo y manías a evitar', 'Listas de palabras y tics, escenas de acción, diálogo en serie.', CraftGroup.prosa, core: true),
    CraftModule('voice-builder', 'Voz de autor', 'Fija y mantiene tu voz a partir de tus textos.', CraftGroup.prosa),
    CraftModule('scene-sequencing', 'Ritmo de escenas', 'Escena y secuela, tensión y respiro.', CraftGroup.estructura, core: true),
    CraftModule('key-moments', 'Momentos clave', 'Construye la historia desde sus momentos emocionales.', CraftGroup.estructura),
    CraftModule('drafting', 'Primer borrador', 'Desbloquea y avanza sin pulir.', CraftGroup.estructura),
    CraftModule('revision', 'Revisión', 'Pasada de edición ordenada.', CraftGroup.estructura),
    CraftModule('endings', 'Finales', 'Cierres que se ganan lo que prometen.', CraftGroup.estructura),
    CraftModule('story-analysis', 'Analizar texto', 'Fortalezas y debilidades de un capítulo.', CraftGroup.estructura),
    CraftModule('story-sense', 'Qué necesita la historia', 'Diagnóstico general de la historia.', CraftGroup.estructura),
    CraftModule('long-form-hooks', 'Ganchos y finales de capítulo', 'Aperturas, cliffhangers y suspense.', CraftGroup.estructura),
    CraftModule('long-form-plot', 'Trama y giros', 'Escaleta, conflicto, ritmo y giros.', CraftGroup.estructura),
    CraftModule('long-form-continuity', 'Continuidad de novela larga', 'Seguimiento de estado, reparto y revisión de un manuscrito largo.', CraftGroup.estructura),
    CraftModule('summarization', 'Resumir', 'Resúmenes de capítulo, sinopsis y escaleta.', CraftGroup.estructura),
    CraftModule('story-long-write', 'Novela larga', 'Ritmo, ganchos y continuidad en serie.', CraftGroup.estructura),
    CraftModule('story-short-write', 'Relato corto', 'Compresión, giro y emoción.', CraftGroup.estructura),
    CraftModule('character-arc', 'Arco de personaje', 'Transformación creíble.', CraftGroup.personajes),
    CraftModule('character-naming', 'Nombres de personajes', 'Nombres que no son los de siempre.', CraftGroup.personajes),
    CraftModule('naming', 'Nombres', 'Marcas, lugares y cosas con nombre.', CraftGroup.personajes),
    CraftModule('long-form-genres', 'Géneros y lo que espera el lector', 'Mecánicas y fórmulas por género.', CraftGroup.personajes),
    CraftModule('genre-conventions', 'Género', 'Promesa y convenciones del género.', CraftGroup.personajes),
    CraftModule('sensitivity-check', 'Autenticidad', 'Opcional: representación con oficio, sin límites.', CraftGroup.personajes),
    CraftModule('worldbuilding', 'Mundo', 'Diagnóstico de mundos finos o vacíos.', CraftGroup.mundo),
    CraftModule('systemic-worldbuilding', 'Mundo sistémico', 'Consecuencias en cascada de un cambio.', CraftGroup.mundo),
    CraftModule('belief-systems', 'Religiones y creencias', 'Panteones, ritos y herejías.', CraftGroup.mundo),
    CraftModule('economic-systems', 'Economía', 'Monedas, comercio y escasez.', CraftGroup.mundo),
    CraftModule('governance-systems', 'Gobiernos', 'Reinos, poder e instituciones.', CraftGroup.mundo),
    CraftModule('settlement-design', 'Ciudades y pueblos', 'Asentamientos con lógica.', CraftGroup.mundo),
    CraftModule('conlang', 'Idiomas inventados', 'Lenguas y nombres coherentes.', CraftGroup.mundo),
    CraftModule('research-workflow', 'Investigación guiada', 'Plan de preguntas, fuentes y síntesis para tu historia.', CraftGroup.mundo),
    CraftModule('book-marketing', 'Sinopsis y pitch', 'Contraportada, descripción de tienda y carta a editoriales.', CraftGroup.publicar),
  ];

  static CraftModule? byId(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Modules whose rules go into every prose prompt.
  static final coreIds = [for (final m in modules) if (m.core) m.id];

  final AssetBundle _bundle;
  final Map<String, String> _cache = {};

  CraftLibrary({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  Future<String> _read(String path) async => _cache[path] ??= await _bundle.loadString(path);

  Future<String> persona() => _read('assets/prompts/writer_core.md');
  Future<String> chatMode() => _read('assets/prompts/chat_mode.md');
  Future<String> essentials() => _read('assets/prompts/craft_essentials.md');

  /// The whole module: when to use it, rules, diagnosis, how to answer and the
  /// deep notes. [deep] false drops the deep notes, for models with a small window.
  Future<String> full(String id, {bool deep = true}) async {
    final text = await _read('assets/craft/$id.md');
    return deep ? text : removeSection(text, 'Deep notes');
  }

  /// Only the "Core rules" section, to keep always-on prompts short.
  Future<String> rules(String id) async => extractSection(await full(id), 'Core rules');

  /// [markdown] without the section called [heading] (up to the next heading).
  static String removeSection(String markdown, String heading) {
    final out = <String>[];
    var skipping = false;
    for (final line in markdown.split('\n')) {
      if (line.startsWith('## ')) skipping = line.substring(3).trim().toLowerCase() == heading.toLowerCase();
      if (!skipping) out.add(line);
    }
    return out.join('\n').trimRight();
  }

  static String extractSection(String markdown, String heading) {
    final lines = markdown.split('\n');
    final out = <String>[];
    var inside = false;
    for (final line in lines) {
      if (line.startsWith('## ')) {
        if (inside) break;
        inside = line.substring(3).trim().toLowerCase() == heading.toLowerCase();
        continue;
      }
      if (inside) out.add(line);
    }
    return out.join('\n').trim();
  }
}
