/// A novel-length writing project — the top-level container for chapters.
class ProjectModel {
  final String id;
  final String title;
  final String synopsis;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectModel({
    required this.id,
    required this.title,
    this.synopsis = '',
    required this.createdAt,
    required this.updatedAt,
  });

  ProjectModel copyWith({String? title, String? synopsis, DateTime? updatedAt}) => ProjectModel(
        id: id,
        title: title ?? this.title,
        synopsis: synopsis ?? this.synopsis,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'synopsis': synopsis,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ProjectModel.fromMap(Map<String, dynamic> map) => ProjectModel(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        synopsis: map['synopsis'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

/// A chapter within a [ProjectModel]. Its actual text lives in one or more
/// [StoryNodeModel]s — the chapter itself only tracks identity and order.
class ChapterModel {
  final String id;
  final String projectId;
  final String title;
  final int order;

  /// Short AI-written recap, injected as context when writing later chapters
  /// so a long novel doesn't have to fit in the prompt. Empty until generated.
  final String summary;

  const ChapterModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.order,
    this.summary = '',
  });

  ChapterModel copyWith({String? title, int? order, String? summary}) => ChapterModel(
        id: id,
        projectId: projectId,
        title: title ?? this.title,
        order: order ?? this.order,
        summary: summary ?? this.summary,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_id': projectId,
        'title': title,
        'order_index': order,
        'summary': summary,
      };

  factory ChapterModel.fromMap(Map<String, dynamic> map) => ChapterModel(
        id: map['id'] as String,
        projectId: map['project_id'] as String,
        title: map['title'] as String? ?? '',
        order: map['order_index'] as int? ?? 0,
        summary: map['summary'] as String? ?? '',
      );
}
