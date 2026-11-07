import '../../writer/writing_profile.dart';
import 'fantasy_calendar_model.dart';

/// A novel-length writing project — the top-level container for chapters.
class ProjectModel {
  final String id;
  final String title;
  final String synopsis;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The world's own calendar, if the author defined one.
  final FantasyCalendar? calendar;

  /// Local path of the map image, empty when none. The path travels in the JSON backup but the image file does not.
  final String mapPath;

  /// How this project's prose should read; see the writer feature.
  final WritingProfile writingProfile;

  const ProjectModel({
    required this.id,
    required this.title,
    this.synopsis = '',
    required this.createdAt,
    required this.updatedAt,
    this.calendar,
    this.mapPath = '',
    this.writingProfile = const WritingProfile(),
  });

  ProjectModel copyWith({String? title, String? synopsis, DateTime? updatedAt, FantasyCalendar? calendar, bool clearCalendar = false, String? mapPath, WritingProfile? writingProfile}) => ProjectModel(
        id: id,
        title: title ?? this.title,
        synopsis: synopsis ?? this.synopsis,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        calendar: clearCalendar ? null : (calendar ?? this.calendar),
        mapPath: mapPath ?? this.mapPath,
        writingProfile: writingProfile ?? this.writingProfile,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'synopsis': synopsis,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'calendar': calendar?.toJsonString() ?? '',
        'map_path': mapPath,
        'writing_profile': writingProfile.toJsonString(),
      };

  factory ProjectModel.fromMap(Map<String, dynamic> map) => ProjectModel(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        synopsis: map['synopsis'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        calendar: FantasyCalendar.fromJsonString(map['calendar'] as String?),
        mapPath: map['map_path'] as String? ?? '',
        writingProfile: WritingProfile.fromJsonString(map['writing_profile'] as String?),
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
