import 'dart:convert';

/// A directed relationship from one character to another
/// (e.g. "hermano mayor, protector").
class CharacterRelationship {
  final String characterId;
  final String description;

  const CharacterRelationship({required this.characterId, required this.description});

  factory CharacterRelationship.fromJson(Map<String, dynamic> json) => CharacterRelationship(
        characterId: json['characterId'] as String,
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'characterId': characterId, 'description': description};
}

/// A character sheet stored locally and consulted by [ContextBuilderService]
/// to keep generations coherent with established appearance, personality,
/// motivation and boundaries.
class CharacterModel {
  final String id;
  final String name;
  final List<String> aliases;
  final String appearance;
  final List<String> personalityTraits;
  final String motivation;

  /// Secrets and hard limits the AI must respect/not reveal prematurely.
  final String secretsLimits;
  final List<CharacterRelationship> relationships;

  /// When true, this sheet is always injected into the prompt regardless of
  /// whether the character is mentioned in the recent text.
  final bool forceInclude;

  const CharacterModel({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.appearance = '',
    this.personalityTraits = const [],
    this.motivation = '',
    this.secretsLimits = '',
    this.relationships = const [],
    this.forceInclude = false,
  });

  CharacterModel copyWith({
    String? name,
    List<String>? aliases,
    String? appearance,
    List<String>? personalityTraits,
    String? motivation,
    String? secretsLimits,
    List<CharacterRelationship>? relationships,
    bool? forceInclude,
  }) {
    return CharacterModel(
      id: id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      appearance: appearance ?? this.appearance,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      motivation: motivation ?? this.motivation,
      secretsLimits: secretsLimits ?? this.secretsLimits,
      relationships: relationships ?? this.relationships,
      forceInclude: forceInclude ?? this.forceInclude,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'aliases': jsonEncode(aliases),
        'appearance': appearance,
        'personality_traits': jsonEncode(personalityTraits),
        'motivation': motivation,
        'secrets_limits': secretsLimits,
        'relationships': jsonEncode(relationships.map((r) => r.toJson()).toList()),
        'force_include': forceInclude ? 1 : 0,
      };

  factory CharacterModel.fromMap(Map<String, dynamic> map) {
    List<String> decodeStringList(Object? raw) {
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<String>();
    }

    List<CharacterRelationship> decodeRelationships(Object? raw) {
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => CharacterRelationship.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return CharacterModel(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      aliases: decodeStringList(map['aliases']),
      appearance: map['appearance'] as String? ?? '',
      personalityTraits: decodeStringList(map['personality_traits']),
      motivation: map['motivation'] as String? ?? '',
      secretsLimits: map['secrets_limits'] as String? ?? '',
      relationships: decodeRelationships(map['relationships']),
      forceInclude: (map['force_include'] as int? ?? 0) == 1,
    );
  }
}
