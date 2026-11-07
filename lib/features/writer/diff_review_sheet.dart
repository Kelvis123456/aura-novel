import 'package:flutter/material.dart';

import '../../core/theme/aura_theme.dart';
import 'word_diff.dart';

/// Shows what a rewrite changed and lets the author keep or undo each change. Returns the text
/// with the chosen changes, or null if they close it without applying.
Future<String?> showDiffReview(BuildContext context, {required String original, required String updated}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.aura.bg,
    builder: (_) => _DiffReviewSheet(original: original, updated: updated),
  );
}

class _DiffReviewSheet extends StatefulWidget {
  final String original;
  final String updated;
  const _DiffReviewSheet({required this.original, required this.updated});

  @override
  State<_DiffReviewSheet> createState() => _DiffReviewSheetState();
}

class _DiffReviewSheetState extends State<_DiffReviewSheet> {
  late final List<DiffHunk> _hunks = WordDiff.compute(widget.original, widget.updated);
  late final List<bool> _accepted = List.filled(_hunks.where((h) => h.changed).length, true);

  void _setAll(bool value) => setState(() => _accepted.fillRange(0, _accepted.length, value));

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final base = TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 17, height: 1.6, color: c.text);
    var change = 0;
    final spans = <InlineSpan>[];
    for (final h in _hunks) {
      if (!h.changed) {
        spans.add(TextSpan(text: h.after));
        continue;
      }
      final index = change++;
      final accepted = _accepted[index];
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => setState(() => _accepted[index] = !accepted),
          child: Text.rich(
            TextSpan(children: [
              if (h.before.trim().isNotEmpty)
                TextSpan(
                  text: h.before,
                  style: TextStyle(
                    color: accepted ? c.danger : c.text,
                    decoration: accepted ? TextDecoration.lineThrough : null,
                    backgroundColor: accepted ? c.danger.withValues(alpha: 0.12) : null,
                  ),
                ),
              if (h.after.trim().isNotEmpty)
                TextSpan(
                  text: h.after,
                  style: TextStyle(
                    color: accepted ? c.success : c.textFaint,
                    decoration: accepted ? null : TextDecoration.lineThrough,
                    backgroundColor: accepted ? c.success.withValues(alpha: 0.12) : null,
                  ),
                ),
            ]),
            style: base,
          ),
        ),
      ));
    }

    final accepted = _accepted.where((a) => a).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revisar cambios', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _accepted.isEmpty ? 'El texto no cambió.' : 'Toca un cambio para quedarte con el original. Verde es lo nuevo, rojo lo que sale.',
            style: TextStyle(color: c.textDim, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: Text.rich(TextSpan(children: spans), style: base))),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$accepted de ${_accepted.length} cambios', style: TextStyle(color: c.textFaint, fontSize: 12)),
              const Spacer(),
              TextButton(onPressed: _accepted.isEmpty ? null : () => _setAll(false), child: const Text('Ninguno')),
              TextButton(onPressed: _accepted.isEmpty ? null : () => _setAll(true), child: const Text('Todos')),
            ],
          ),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(WordDiff.merge(_hunks, _accepted)),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
