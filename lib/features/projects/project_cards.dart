import 'package:flutter/material.dart';

import 'models/project_model.dart';
import '../../core/theme/aura_theme.dart';

class ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ProjectCard(
      {super.key, required this.project, required this.accent, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.aura.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.aura.line),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.aura.text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      if (project.synopsis.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            project.synopsis,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.aura.textDim, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: context.aura.textFaint),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChapterCard extends StatelessWidget {
  final ChapterModel chapter;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSummarize;
  final VoidCallback onCheckConsistency;

  const ChapterCard({
    super.key,
    required this.chapter,
    required this.accent,
    required this.onTap,
    required this.onDelete,
    required this.onSummarize,
    required this.onCheckConsistency,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.aura.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.aura.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent.withValues(alpha: 0.2),
                  child: Text('${chapter.order + 1}',
                      style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.aura.text, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (chapter.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            chapter.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.aura.textFaint, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.notes, size: 18, color: chapter.summary.isEmpty ? context.aura.textFaint : accent),
                  tooltip: chapter.summary.isEmpty ? 'Resumir con IA' : 'Actualizar resumen',
                  onPressed: onSummarize,
                ),
                IconButton(
                  icon: Icon(Icons.fact_check_outlined, size: 18, color: context.aura.textFaint),
                  tooltip: 'Revisar coherencia',
                  onPressed: onCheckConsistency,
                ),
                Icon(Icons.chevron_right, color: context.aura.textFaint, size: 20),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: context.aura.textFaint),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
