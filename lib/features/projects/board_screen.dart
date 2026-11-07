import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/aura_theme.dart';
import 'models/project_model.dart';

const _statusLabels = {
  'idea': 'Idea',
  'borrador': 'Borrador',
  'revision': 'Revisión',
  'listo': 'Listo',
};

/// Groups chapters into the four board columns, keeping story order inside each one. When
/// [thread] is set only the chapters that carry it appear.
Map<String, List<ChapterModel>> groupByStatus(List<ChapterModel> chapters, {String? thread}) {
  final columns = {for (final s in ChapterModel.statuses) s: <ChapterModel>[]};
  final sorted = [...chapters]..sort((a, b) => a.order.compareTo(b.order));
  for (final c in sorted) {
    if (thread != null && !c.threads.contains(thread)) continue;
    columns[c.status]!.add(c);
  }
  return columns;
}

/// Every thread used in the project, most-used first.
List<String> threadsOf(List<ChapterModel> chapters) {
  final counts = <String, int>{};
  for (final c in chapters) {
    for (final t in c.threads) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!) != 0 ? counts[b]!.compareTo(counts[a]!) : a.compareTo(b));
  return names;
}

/// A board of the project's chapters by stage (idea, draft, revision, done) with plot threads
/// to filter by. Tap a card to change its stage or threads.
class BoardScreen extends StatefulWidget {
  final ProjectModel project;
  final Color accent;
  const BoardScreen({super.key, required this.project, required this.accent});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<ChapterModel> _chapters = [];
  String? _thread;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final chapters = await AppScope.of(context).projectRepository.getChaptersForProject(widget.project.id);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _loading = false;
      if (_thread != null && !threadsOf(chapters).contains(_thread)) _thread = null;
    });
  }

  Future<void> _edit(ChapterModel chapter) async {
    var status = chapter.status;
    final field = TextEditingController(text: chapter.threads.join(', '));
    final known = threadsOf(_chapters);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.aura.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapter.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ChapterModel.statuses)
                    ChoiceChip(label: Text(_statusLabels[s]!), selected: status == s, onSelected: (_) => setSheet(() => status = s)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: field,
                decoration: const InputDecoration(labelText: 'Hilos de la trama', hintText: 'separados por comas: el faro, la herencia'),
              ),
              if (known.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in known)
                      ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          final current = ChapterModel.splitThreads(field.text.replaceAll(',', '|'));
                          if (!current.contains(t)) field.text = [...current, t].join(', ');
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(sheetContext).pop(true), child: const Text('Guardar'))),
            ],
          ),
        ),
      ),
    );
    final threads = ChapterModel.splitThreads(field.text.replaceAll(',', '|'));
    field.dispose();
    if (saved != true || !mounted) return;
    await AppScope.of(context).projectRepository.updateChapterBoard(chapter.id, status: status, threads: threads);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final columns = groupByStatus(_chapters, thread: _thread);
    final threads = threadsOf(_chapters);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Tablero')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Este proyecto aún no tiene capítulos. Créalos y aparecerán aquí por etapa.', textAlign: TextAlign.center, style: TextStyle(color: c.textDim, height: 1.5)),
                  ),
                )
              : Column(
                  children: [
                    if (threads.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final t in threads)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(t),
                                  selected: _thread == t,
                                  showCheckmark: false,
                                  selectedColor: widget.accent.withValues(alpha: 0.2),
                                  onSelected: (v) => setState(() => _thread = v ? t : null),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          for (final s in ChapterModel.statuses) _column(c, s, columns[s]!),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _column(AuraColors c, String status, List<ChapterModel> items) {
    return Container(
      width: 250,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Text(
              '${_statusLabels[status]!.toUpperCase()}  ${items.length}',
              style: TextStyle(color: c.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(4), child: Text('Nada aquí', style: TextStyle(color: c.textFaint, fontSize: 12))))
                : ListView(
                    children: [
                      for (final ch in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: c.bg,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _edit(ch),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ch.title, style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                                    if (ch.summary.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(ch.summary.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textDim, fontSize: 12, height: 1.35)),
                                    ],
                                    if (ch.threads.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final t in ch.threads)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(20)),
                                              child: Text(t, style: TextStyle(color: c.accentText, fontSize: 11)),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
