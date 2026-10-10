import 'dart:async';

import '../projects/project_repository.dart';

/// Debounced autosave of the editor text into a [ChapterDraft]. The draft
/// only exists while the text differs from the last saved version: matching
/// text deletes it, so a clean chapter never offers a "recovered" draft.
class DraftAutosaver {
  final ProjectRepository _repository;
  final String chapterId;
  final Duration delay;

  String _nodeId;
  String _savedContent;
  String _latest;
  Timer? _timer;

  DraftAutosaver({
    required ProjectRepository repository,
    required this.chapterId,
    required String nodeId,
    required String savedContent,
    this.delay = const Duration(seconds: 2),
  })  : _repository = repository,
        _nodeId = nodeId,
        _savedContent = savedContent,
        _latest = savedContent;

  /// The draft for this chapter if it belongs to [nodeId] and differs from
  /// the saved text; anything else is stale and is dropped.
  Future<String?> recover() async {
    final draft = await _repository.getDraft(chapterId);
    if (draft == null) return null;
    if (draft.nodeId != _nodeId || draft.content == _savedContent) {
      await _repository.deleteDraft(chapterId);
      return null;
    }
    return draft.content;
  }

  void onTextChanged(String text) {
    _latest = text;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Writes (or clears) the draft now. Call on app pause and on dispose.
  Future<void> flush() async {
    _timer?.cancel();
    if (_latest == _savedContent) {
      await _repository.deleteDraft(chapterId);
    } else {
      await _repository.saveDraft(
        ChapterDraft(chapterId: chapterId, nodeId: _nodeId, content: _latest, updatedAt: DateTime.now()),
      );
    }
  }

  /// A new version was saved: [content] is the new baseline under [nodeId].
  Future<void> markSaved({required String nodeId, required String content}) async {
    _timer?.cancel();
    _nodeId = nodeId;
    _savedContent = content;
    _latest = content;
    await _repository.deleteDraft(chapterId);
  }

  void dispose() => _timer?.cancel();
}
