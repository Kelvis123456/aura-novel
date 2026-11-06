import 'dart:convert';

enum LoreCategory { location, faction, object, worldRule, event }

extension LoreCategoryLabel on LoreCategory {
  String get label => switch (this) {
        LoreCategory.location => 'Lugar',
        LoreCategory.faction => 'Facción',
        LoreCategory.object => 'Objeto',
        LoreCategory.worldRule => 'Regla del mundo',
        LoreCategory.event => 'Evento',
      };

  static LoreCategory fromName(String name) =>
      LoreCategory.values.firstWhere((c) => c.name == name, orElse: () => LoreCategory.location);
}

/// A single lore entry (place, faction, object, world rule or past event)
/// consulted by [ContextBuilderService] for world coherence.
class LoreItemModel {
  final String id;
  final String name;
  final LoreCategory category;
  final String shortDescription;
  final String longDetails;

  /// Keywords that trigger this entry's inclusion when mentioned in text.
  final List<String> tags;

  /// When true, always injected regardless of whether a tag is mentioned.
  final bool forceInclude;

  /// Chapter number (1-based) from which the public wiki shows this entry; 0 = always.
  final int visibleFromChapter;

  const LoreItemModel({
    required this.id,
    required this.name,
    required this.category,
    this.shortDescription = '',
    this.longDetails = '',
    this.tags = const [],
    this.forceInclude = false,
    this.visibleFromChapter = 0,
  });

  LoreItemModel copyWith({
    String? name,
    LoreCategory? category,
    String? shortDescription,
    String? longDetails,
    List<String>? tags,
    bool? forceInclude,
    int? visibleFromChapter,
  }) {
    return LoreItemModel(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      shortDescription: shortDescription ?? this.shortDescription,
      longDetails: longDetails ?? this.longDetails,
      tags: tags ?? this.tags,
      forceInclude: forceInclude ?? this.forceInclude,
      visibleFromChapter: visibleFromChapter ?? this.visibleFromChapter,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category.name,
        'short_description': shortDescription,
        'long_details': longDetails,
        'tags': jsonEncode(tags),
        'force_include': forceInclude ? 1 : 0,
        'visible_from_chapter': visibleFromChapter,
      };

  factory LoreItemModel.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'];
    final tags = (rawTags is String && rawTags.isNotEmpty)
        ? (jsonDecode(rawTags) as List<dynamic>).cast<String>()
        : <String>[];

    return LoreItemModel(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      category: LoreCategoryLabel.fromName(map['category'] as String? ?? ''),
      shortDescription: map['short_description'] as String? ?? '',
      longDetails: map['long_details'] as String? ?? '',
      tags: tags,
      forceInclude: (map['force_include'] as int? ?? 0) == 1,
      visibleFromChapter: map['visible_from_chapter'] as int? ?? 0,
    );
  }
}
