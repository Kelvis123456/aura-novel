import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import 'models/project_model.dart';
import 'models/timeline_event_model.dart';
import 'project_repository.dart';

/// Ordered list of the story world's events. Drag to reorder; each event can
/// point at the chapter that narrates it.
class TimelineScreen extends StatefulWidget {
  final ProjectModel project;
  final List<ChapterModel> chapters;
  final Color accent;

  const TimelineScreen({super.key, required this.project, required this.chapters, required this.accent});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<TimelineEvent> _events = [];
  bool _loading = true;

  ProjectRepository get _repo => AppScope.of(context).projectRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final events = await _repo.getTimelineEvents(widget.project.id);
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  String _chapterTitle(String? id) {
    for (final c in widget.chapters) {
      if (c.id == id) return c.title;
    }
    return '';
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final moved = List.of(_events);
    moved.insert(newIndex, moved.removeAt(oldIndex));
    setState(() => _events = moved);
    await _repo.reorderTimeline([for (final e in moved) e.id]);
  }

  Future<void> _edit([TimelineEvent? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final date = TextEditingController(text: existing?.worldDate ?? '');
    final description = TextEditingController(text: existing?.description ?? '');
    String? chapterId = existing?.chapterId;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A0B12),
          title: Text(existing == null ? 'Nuevo evento' : 'Editar evento', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Evento')),
                TextField(controller: date, decoration: const InputDecoration(labelText: 'Fecha del mundo (texto libre)')),
                TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: chapterId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A0B12),
                  decoration: const InputDecoration(labelText: 'Capítulo donde ocurre'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Ninguno')),
                    for (final c in widget.chapters) DropdownMenuItem<String?>(value: c.id, child: Text(c.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setDialogState(() => chapterId = value),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('delete'),
                child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete' && existing != null) {
      await _repo.deleteTimelineEvent(existing.id);
    } else if (action == 'save' && title.text.trim().isNotEmpty) {
      await _repo.saveTimelineEvent(TimelineEvent(
        id: existing?.id ?? ProjectRepository.generateId(),
        projectId: widget.project.id,
        chapterId: chapterId,
        title: title.text.trim(),
        worldDate: date.text.trim(),
        description: description.text.trim(),
        position: existing?.position ?? _events.length,
      ));
    } else {
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Línea de tiempo · ${widget.project.title}', overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aún no hay eventos. Añade los hechos del mundo y enlázalos al capítulo donde los cuentas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _events.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final e = _events[index];
                    final chapter = _chapterTitle(e.chapterId);
                    return Card(
                      key: ValueKey(e.id),
                      color: Colors.white.withValues(alpha: 0.05),
                      child: ListTile(
                        onTap: () => _edit(e),
                        title: Text(e.title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          [if (e.worldDate.isNotEmpty) e.worldDate, if (chapter.isNotEmpty) 'Cap.: $chapter'].join(' · '),
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle, color: Colors.white38),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.accent,
        onPressed: _edit,
        tooltip: 'Nuevo evento',
        child: const Icon(Icons.add),
      ),
    );
  }
}
