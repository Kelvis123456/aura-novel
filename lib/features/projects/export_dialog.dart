import 'package:flutter/material.dart';

import 'export_service.dart';
import 'models/project_model.dart';
import 'project_repository.dart';
import '../../core/theme/aura_theme.dart';

/// Bottom sheet to pick an export format and which chapters to include,
/// then compile + hand the file to the native share sheet. Each chapter's
/// content is resolved from its most recently saved [StoryNodeModel] —
/// picking a specific branch per chapter is left to the Branch Tree Viewer.
Future<void> showExportDialog(
  BuildContext context, {
  required ProjectModel project,
  required List<ChapterModel> chapters,
  required ProjectRepository repository,
  required Color accent,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: context.aura.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ExportSheet(project: project, chapters: chapters, repository: repository, accent: accent),
  );
}

class _ExportSheet extends StatefulWidget {
  final ProjectModel project;
  final List<ChapterModel> chapters;
  final ProjectRepository repository;
  final Color accent;

  const _ExportSheet({
    required this.project,
    required this.chapters,
    required this.repository,
    required this.accent,
  });

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  late Set<String> _includedChapterIds;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _includedChapterIds = widget.chapters.map((c) => c.id).toSet();
  }

  Future<void> _export() async {
    if (_includedChapterIds.isEmpty) return;
    setState(() => _isExporting = true);

    try {
      final selectedChapters = widget.chapters.where((c) => _includedChapterIds.contains(c.id)).toList();
      final contentByChapterId = <String, String>{};
      for (final chapter in selectedChapters) {
        final latest = await widget.repository.getLatestNodeForChapter(chapter.id);
        contentByChapterId[chapter.id] = latest?.content ?? '';
      }

      final service = ExportService();
      final file = await service.exportProject(
        project: widget.project,
        chapters: selectedChapters,
        contentByChapterId: contentByChapterId,
        format: _format,
      );
      await service.shareFile(file, subject: widget.project.title);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e'), backgroundColor: context.aura.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Exportar "${widget.project.title}"',
              style: TextStyle(color: context.aura.text, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text('FORMATO', style: TextStyle(color: context.aura.textDim, fontSize: 11, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final format in ExportFormat.values)
                  ChoiceChip(
                    label: Text(format.label),
                    selected: _format == format,
                    onSelected: (_) => setState(() => _format = format),
                    selectedColor: accent.withValues(alpha: 0.3),
                    backgroundColor: context.aura.surface,
                    labelStyle: TextStyle(color: _format == format ? context.aura.text : context.aura.textDim, fontSize: 12),
                    side: BorderSide(color: _format == format ? accent : context.aura.textFaint),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('CAPÍTULOS A INCLUIR', style: TextStyle(color: context.aura.textDim, fontSize: 11, letterSpacing: 1.1)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final chapter in widget.chapters)
                    CheckboxListTile(
                      value: _includedChapterIds.contains(chapter.id),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _includedChapterIds.add(chapter.id);
                        } else {
                          _includedChapterIds.remove(chapter.id);
                        }
                      }),
                      activeColor: accent,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(chapter.title, style: TextStyle(color: context.aura.text, fontSize: 13)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isExporting || _includedChapterIds.isEmpty ? null : _export,
              icon: _isExporting
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.aura.text))
                  : const Icon(Icons.ios_share),
              label: Text(_isExporting ? 'Exportando…' : 'Exportar y compartir'),
              style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
