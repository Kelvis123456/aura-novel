import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import 'calendar_editor_screen.dart';
import 'models/fantasy_calendar_model.dart';
import 'models/project_model.dart';
import 'models/timeline_event_model.dart';
import 'project_repository.dart';
import '../../core/theme/aura_theme.dart';

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
  late ProjectModel _project = widget.project;

  ProjectRepository get _repo => AppScope.of(context).projectRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final repo = _repo;
    final events = await repo.getTimelineEvents(widget.project.id);
    // The chapter list holds an older copy of the project than the DB.
    final fresh = await repo.getProject(widget.project.id);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _project = fresh;
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

  Future<void> _editCalendar() async {
    final calendar = await Navigator.of(context).push<FantasyCalendar>(
      MaterialPageRoute(builder: (_) => CalendarEditorScreen(initial: _project.calendar, accent: widget.accent)),
    );
    if (calendar == null) return;
    final repo = _repo;
    await repo.setProjectCalendar(_project.id, calendar);
    final fresh = await repo.getProject(_project.id);
    if (mounted && fresh != null) setState(() => _project = fresh);
  }

  int _nextPosition() => _events.isEmpty ? 0 : _events.map((e) => e.position).reduce((a, b) => a > b ? a : b) + 1;

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final moved = List.of(_events);
    moved.insert(newIndex, moved.removeAt(oldIndex));
    // Keep the in-memory positions in step with the DB, or editing an event
    // afterwards would write its old position back.
    final renumbered = [for (var i = 0; i < moved.length; i++) moved[i].copyWith(position: i)];
    setState(() => _events = renumbered);
    await _repo.reorderTimeline([for (final e in moved) e.id]);
  }

  Future<void> _edit([TimelineEvent? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final date = TextEditingController(text: existing?.worldDate ?? '');
    final description = TextEditingController(text: existing?.description ?? '');
    String? chapterId = existing?.chapterId;
    final calendar = _project.calendar;
    final year = TextEditingController();
    final day = TextEditingController();
    int monthIndex = 0;
    String? dateError;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.aura.surface,
          title: Text(existing == null ? 'Nuevo evento' : 'Editar evento', style: TextStyle(color: context.aura.text, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Evento')),
                TextField(controller: date, decoration: const InputDecoration(labelText: 'Fecha del mundo (texto libre)')),
                if (calendar != null) ...[
                  const SizedBox(height: 8),
                  Text('O elige con tu calendario (${calendar.eraName})', style: TextStyle(color: context.aura.textDim, fontSize: 12)),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: year,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: calendar.eraName),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: monthIndex,
                          isExpanded: true,
                          dropdownColor: context.aura.surface,
                          decoration: const InputDecoration(labelText: 'Mes'),
                          items: [
                            for (var i = 0; i < calendar.months.length; i++)
                              DropdownMenuItem(value: i, child: Text(calendar.months[i].name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setDialogState(() => monthIndex = v ?? 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: day,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Día'),
                        ),
                      ),
                    ],
                  ),
                  if (dateError != null) Text(dateError!, style: TextStyle(color: context.aura.danger, fontSize: 12)),
                ],
                TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: chapterId,
                  isExpanded: true,
                  dropdownColor: context.aura.surface,
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
                child: Text('Eliminar', style: TextStyle(color: context.aura.danger)),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
            ),
            FilledButton(
              onPressed: () {
                if (calendar != null && year.text.trim().isNotEmpty) {
                  final yearValue = int.tryParse(year.text.trim());
                  if (yearValue == null) {
                    setDialogState(() => dateError = 'El año no es un número válido.');
                    return;
                  }
                  try {
                    date.text = calendar.format(
                      year: yearValue,
                      monthIndex: monthIndex,
                      day: int.tryParse(day.text.trim()) ?? 0,
                    );
                  } on RangeError {
                    setDialogState(() => dateError = '${calendar.months[monthIndex].name} tiene ${calendar.months[monthIndex].days} días.');
                    return;
                  }
                }
                Navigator.of(dialogContext).pop('save');
              },
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final values = (title: title.text.trim(), date: date.text.trim(), description: description.text.trim());
    for (final c in [title, date, description, year, day]) {
      c.dispose();
    }

    if (action == 'delete' && existing != null) {
      await _repo.deleteTimelineEvent(existing.id);
    } else if (action == 'save' && values.title.isNotEmpty) {
      await _repo.saveTimelineEvent(TimelineEvent(
        id: existing?.id ?? ProjectRepository.generateId(),
        projectId: widget.project.id,
        chapterId: chapterId,
        title: values.title,
        worldDate: values.date,
        description: values.description,
        position: existing?.position ?? _nextPosition(),
      ));
    } else {
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.aura.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Línea de tiempo · ${widget.project.title}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month), tooltip: 'Calendario del mundo', onPressed: _editCalendar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Aún no hay eventos. Añade los hechos del mundo y enlázalos al capítulo donde los cuentas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.aura.textDim),
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
                      color: context.aura.surface,
                      child: ListTile(
                        onTap: () => _edit(e),
                        title: Text(e.title, style: TextStyle(color: context.aura.text)),
                        subtitle: Text(
                          [if (e.worldDate.isNotEmpty) e.worldDate, if (chapter.isNotEmpty) 'Cap.: $chapter'].join(' · '),
                          style: TextStyle(color: context.aura.textDim),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle, color: context.aura.textFaint),
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
