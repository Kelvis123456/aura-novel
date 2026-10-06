/// Tells [EditorScreen] which project/chapter/node the canvas was opened
/// from, so its "Guardar versión" action knows where to write the new
/// [StoryNodeModel]. Absent when the editor is opened as a scratch buffer
/// with no project attached (in which case that action stays disabled).
class EditorDocumentBinding {
  final String projectId;
  final String chapterId;

  /// The story node currently loaded into the canvas — the parent of the
  /// next node "Guardar versión" will create.
  final String nodeId;

  const EditorDocumentBinding({
    required this.projectId,
    required this.chapterId,
    required this.nodeId,
  });

  EditorDocumentBinding withNode(String nodeId) => EditorDocumentBinding(
        projectId: projectId,
        chapterId: chapterId,
        nodeId: nodeId,
      );
}
