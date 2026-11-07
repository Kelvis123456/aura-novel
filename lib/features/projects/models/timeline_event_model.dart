/// A dated event of the story world, optionally tied to the chapter where it
/// is narrated. [worldDate] is free text ("Año 312, invierno") because the
/// world may not use the real calendar; [position] is what orders the list.
class TimelineEvent {
  final String id;
  final String projectId;
  final String? chapterId;
  final String title;
  final String worldDate;
  final String description;
  final int position;

  const TimelineEvent({
    required this.id,
    required this.projectId,
    this.chapterId,
    required this.title,
    this.worldDate = '',
    this.description = '',
    this.position = 0,
  });

  TimelineEvent copyWith({
    String? chapterId,
    bool clearChapter = false,
    String? title,
    String? worldDate,
    String? description,
    int? position,
  }) =>
      TimelineEvent(
        id: id,
        projectId: projectId,
        chapterId: clearChapter ? null : (chapterId ?? this.chapterId),
        title: title ?? this.title,
        worldDate: worldDate ?? this.worldDate,
        description: description ?? this.description,
        position: position ?? this.position,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_id': projectId,
        'chapter_id': chapterId,
        'title': title,
        'world_date': worldDate,
        'description': description,
        'position': position,
      };

  factory TimelineEvent.fromMap(Map<String, dynamic> map) => TimelineEvent(
        id: map['id'] as String,
        projectId: map['project_id'] as String,
        chapterId: map['chapter_id'] as String?,
        title: map['title'] as String,
        worldDate: map['world_date'] as String? ?? '',
        description: map['description'] as String? ?? '',
        position: map['position'] as int? ?? 0,
      );
}
