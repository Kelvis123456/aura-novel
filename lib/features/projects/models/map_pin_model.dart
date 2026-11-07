/// A marker on a project's map. [x] and [y] are fractions (0 to 1) of the
/// image size, so a pin stays put whatever the screen or image resolution.
class MapPin {
  final String id;
  final String projectId;
  final double x;
  final double y;
  final String label;

  /// Lore entry this pin opens in the studio, if any.
  final String? loreItemId;

  const MapPin({
    required this.id,
    required this.projectId,
    required this.x,
    required this.y,
    required this.label,
    this.loreItemId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_id': projectId,
        'x': x,
        'y': y,
        'label': label,
        'lore_item_id': loreItemId,
      };

  factory MapPin.fromMap(Map<String, dynamic> map) => MapPin(
        id: map['id'] as String,
        projectId: map['project_id'] as String,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        label: map['label'] as String? ?? '',
        loreItemId: map['lore_item_id'] as String?,
      );
}
