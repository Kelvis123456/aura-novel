import 'dart:convert';

/// How rough or restrained the prose should be. The author picks it, and the
/// author can still override it scene by scene with a plain instruction.
enum WritingRegister { suave, natural, crudo, sucio }

extension WritingRegisterInfo on WritingRegister {
  String get label => switch (this) {
        WritingRegister.suave => 'Suave',
        WritingRegister.natural => 'Natural',
        WritingRegister.crudo => 'Crudo',
        WritingRegister.sucio => 'Sucio',
      };

  String get hint => switch (this) {
        WritingRegister.suave => 'Sugiere más de lo que muestra. Violencia y sexo fuera de plano o contenidos.',
        WritingRegister.natural => 'Lo que la escena pida, sin recrearse ni esquivar.',
        WritingRegister.crudo => 'Explícito y directo. Cuerpo, violencia y lenguaje sin suavizar.',
        WritingRegister.sucio => 'Lo más crudo: vulgar, físico, incómodo, sin ninguna elegancia defensiva.',
      };

  String get instruction => switch (this) {
        WritingRegister.suave =>
          'Register: restrained. Imply rather than depict graphic violence and sex; use ellipsis, cut-aways and suggestion, but keep the emotional truth intact.',
        WritingRegister.natural =>
          'Register: natural. Show what the scene needs, at the level of detail a mainstream adult novel would use. Neither dwell nor dodge.',
        WritingRegister.crudo =>
          'Register: raw. Depict violence, bodies, sex and cruelty explicitly and directly, in concrete physical detail, with unsoftened language. No euphemism, no fade to black.',
        WritingRegister.sucio =>
          'Register: filthy. Go as raw as the story allows: vulgar, visceral, physical and uncomfortable, with coarse profanity and unglamorous detail. No defensive elegance, no cleaning up.',
      };
}

enum Pov { primera, terceraLimitada, terceraOmnisciente, segunda }

extension PovInfo on Pov {
  String get label => switch (this) {
        Pov.primera => 'Primera persona',
        Pov.terceraLimitada => 'Tercera limitada',
        Pov.terceraOmnisciente => 'Tercera omnisciente',
        Pov.segunda => 'Segunda persona',
      };

  String get instruction => switch (this) {
        Pov.primera => 'first person',
        Pov.terceraLimitada => 'close third person (limited to one character at a time)',
        Pov.terceraOmnisciente => 'omniscient third person',
        Pov.segunda => 'second person',
      };
}

enum CraftLevel { completo, esencial }

/// Per-project writing settings. Everything is optional: an empty profile
/// still produces a valid prompt.
class WritingProfile {
  /// BCP-47-ish code of the language the prose is written in.
  final String language;
  final String genre;
  final Pov pov;
  final bool presentTense;
  final String tone;
  final WritingRegister register;
  final String references;
  final String directions;

  /// `esencial` sends a much shorter craft prompt, for small or local models.
  final CraftLevel craftLevel;

  const WritingProfile({
    this.language = 'es',
    this.genre = '',
    this.pov = Pov.terceraLimitada,
    this.presentTense = false,
    this.tone = '',
    this.register = WritingRegister.natural,
    this.references = '',
    this.directions = '',
    this.craftLevel = CraftLevel.completo,
  });

  static const languages = {
    'es': 'Spanish',
    'en': 'English',
    'pt': 'Portuguese',
    'fr': 'French',
    'it': 'Italian',
    'de': 'German',
  };

  static const languageLabels = {
    'es': 'Español',
    'en': 'English',
    'pt': 'Português',
    'fr': 'Français',
    'it': 'Italiano',
    'de': 'Deutsch',
  };

  String get languageName => languages[language] ?? 'Spanish';

  WritingProfile copyWith({
    String? language,
    String? genre,
    Pov? pov,
    bool? presentTense,
    String? tone,
    WritingRegister? register,
    String? references,
    String? directions,
    CraftLevel? craftLevel,
  }) =>
      WritingProfile(
        language: language ?? this.language,
        genre: genre ?? this.genre,
        pov: pov ?? this.pov,
        presentTense: presentTense ?? this.presentTense,
        tone: tone ?? this.tone,
        register: register ?? this.register,
        references: references ?? this.references,
        directions: directions ?? this.directions,
        craftLevel: craftLevel ?? this.craftLevel,
      );

  /// The profile as prompt text. Empty fields are left out.
  String toPromptBlock() {
    final lines = <String>[
      'Write in $languageName.',
      'Point of view: ${pov.instruction}. Tense: ${presentTense ? 'present' : 'past'}.',
      register.instruction,
      if (genre.trim().isNotEmpty) 'Genre: ${genre.trim()}.',
      if (tone.trim().isNotEmpty) 'Tone: ${tone.trim()}.',
      if (references.trim().isNotEmpty) 'Stylistic references (absorb the technique, never copy phrasing): ${references.trim()}.',
      if (directions.trim().isNotEmpty) 'Author\'s standing directions: ${directions.trim()}',
    ];
    return lines.join('\n');
  }

  String toJsonString() => jsonEncode({
        'language': language,
        'genre': genre,
        'pov': pov.name,
        'presentTense': presentTense,
        'tone': tone,
        'register': register.name,
        'references': references,
        'directions': directions,
        'craftLevel': craftLevel.name,
      });

  /// Empty or unreadable input gives the default profile, so a corrupt value
  /// never stops a project from opening.
  static WritingProfile fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const WritingProfile();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.firstWhere((v) => v.name == name, orElse: () => fallback);
      return WritingProfile(
        language: languages.containsKey(m['language']) ? m['language'] as String : 'es',
        genre: m['genre'] as String? ?? '',
        pov: pick(Pov.values, m['pov'], Pov.terceraLimitada),
        presentTense: m['presentTense'] == true,
        tone: m['tone'] as String? ?? '',
        register: pick(WritingRegister.values, m['register'], WritingRegister.natural),
        references: m['references'] as String? ?? '',
        directions: m['directions'] as String? ?? '',
        craftLevel: pick(CraftLevel.values, m['craftLevel'], CraftLevel.completo),
      );
    } on Object {
      return const WritingProfile();
    }
  }
}
