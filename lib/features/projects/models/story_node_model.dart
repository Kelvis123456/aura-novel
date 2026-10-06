/// A single point in a chapter's branching history: a full text snapshot
/// linked to its parent via [parentNodeId]. The tree formed by all nodes of
/// a chapter (grouped by shared [parentNodeId]) is what [BranchTreeViewer]
/// renders and lets the author navigate.
class StoryNodeModel {
  final String id;
  final String chapterId;

  /// Null for the trunk's root node.
  final String? parentNodeId;
  final String content;

  /// e.g. "Ruta A: Aceptar la propuesta". Empty for a plain saved version
  /// that isn't an explicit narrative fork.
  final String branchName;
  final DateTime timestamp;

  const StoryNodeModel({
    required this.id,
    required this.chapterId,
    this.parentNodeId,
    required this.content,
    this.branchName = '',
    required this.timestamp,
  });

  bool get isRoot => parentNodeId == null;
  bool get isBranch => branchName.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'chapter_id': chapterId,
        'parent_node_id': parentNodeId,
        'content': content,
        'branch_name': branchName,
        'timestamp': timestamp.toIso8601String(),
      };

  factory StoryNodeModel.fromMap(Map<String, dynamic> map) => StoryNodeModel(
        id: map['id'] as String,
        chapterId: map['chapter_id'] as String,
        parentNodeId: map['parent_node_id'] as String?,
        content: map['content'] as String? ?? '',
        branchName: map['branch_name'] as String? ?? '',
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}
