import 'package:flutter/material.dart';

/// Chip-based multi-value input used for aliases, personality traits and
/// lore tags. Commit a value with Enter/submit; tap the chip's `x` to remove.
class TagInputField extends StatefulWidget {
  final String label;
  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;
  final Color accent;
  final String hint;

  const TagInputField({
    super.key,
    required this.label,
    required this.initialTags,
    required this.onChanged,
    required this.accent,
    this.hint = 'Añadir…',
  });

  @override
  State<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends State<TagInputField> {
  late List<String> _tags;
  final _fieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.initialTags);
  }

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final value = raw.trim();
    _fieldController.clear();
    if (value.isEmpty || _tags.contains(value)) return;
    setState(() => _tags.add(value));
    widget.onChanged(List.of(_tags));
  }

  void _remove(String tag) {
    setState(() => _tags.remove(tag));
    widget.onChanged(List.of(_tags));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.1),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in _tags)
              Chip(
                label: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: widget.accent.withValues(alpha: 0.18),
                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white70),
                onDeleted: () => _remove(tag),
                side: BorderSide(color: widget.accent.withValues(alpha: 0.4)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _fieldController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hint,
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  border: InputBorder.none,
                ),
                onSubmitted: _commit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
