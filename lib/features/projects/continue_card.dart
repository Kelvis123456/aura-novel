import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/aura_theme.dart';
import '../editor/editor_screen.dart';
import 'editor_document_binding.dart';
import 'project_repository.dart';

/// "Continuar donde lo dejaste": the chapter whose latest saved version is
/// the most recent one, one tap from the editor. Hidden until something is
/// saved. [refresh] ticks when the tab becomes visible again.
class ContinueCard extends StatefulWidget {
  final ValueNotifier<int> refresh;

  const ContinueCard({super.key, required this.refresh});

  @override
  State<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<ContinueCard> {
  LastEdited? _last;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_last == null) _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).projectRepository;
    final last = await repo.getLastEdited();
    if (mounted) setState(() => _last = last);
  }

  void _open(LastEdited last) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => EditorScreen(
              initialContent: last.node.content,
              documentBinding: EditorDocumentBinding(
                projectId: last.project.id,
                chapterId: last.chapter.id,
                nodeId: last.node.id,
              ),
            ),
          ),
        )
        .then((_) => _load());
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    if (last == null) return const SizedBox.shrink();
    final c = context.aura;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(last),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUAR',
                        style: TextStyle(color: c.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        last.chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 22, color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${last.project.title} · ${_ago(last.node.timestamp)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textDim, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward, color: c.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
