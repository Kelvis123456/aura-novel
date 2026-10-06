import 'package:flutter/material.dart';

import 'lore_repository.dart';
import 'models/lore_item_model.dart';
import 'widgets/tag_input_field.dart';

/// Full-height create/edit form for a [LoreItemModel]. Pops with the
/// resulting model on save, or `null` if dismissed without saving.
class LoreItemFormSheet extends StatefulWidget {
  final LoreItemModel? existing;
  final Color accent;

  const LoreItemFormSheet({super.key, this.existing, required this.accent});

  static Future<LoreItemModel?> show(
    BuildContext context, {
    LoreItemModel? existing,
    required Color accent,
  }) {
    return showModalBottomSheet<LoreItemModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0508),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LoreItemFormSheet(existing: existing, accent: accent),
    );
  }

  @override
  State<LoreItemFormSheet> createState() => _LoreItemFormSheetState();
}

class _LoreItemFormSheetState extends State<LoreItemFormSheet> {
  late final TextEditingController _nameField;
  late final TextEditingController _shortDescField;
  late final TextEditingController _longDetailsField;
  late LoreCategory _category;
  late List<String> _tags;
  late bool _forceInclude;

  String? _nameError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameField = TextEditingController(text: existing?.name ?? '');
    _shortDescField = TextEditingController(text: existing?.shortDescription ?? '');
    _longDetailsField = TextEditingController(text: existing?.longDetails ?? '');
    _category = existing?.category ?? LoreCategory.location;
    _tags = List.of(existing?.tags ?? const []);
    _forceInclude = existing?.forceInclude ?? false;
  }

  @override
  void dispose() {
    _nameField.dispose();
    _shortDescField.dispose();
    _longDetailsField.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameField.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'El nombre es obligatorio.');
      return;
    }

    final model = LoreItemModel(
      id: widget.existing?.id ?? LoreRepository.generateId(),
      name: name,
      category: _category,
      shortDescription: _shortDescField.text.trim(),
      longDetails: _longDetailsField.text.trim(),
      tags: _tags,
      forceInclude: _forceInclude,
    );

    Navigator.of(context).pop(model);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SafeArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Text(
                  _isEditing ? 'Editar elemento de lore' : 'Nuevo elemento de lore',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                const Text('CATEGORÍA', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in LoreCategory.values)
                      ChoiceChip(
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                        selectedColor: accent.withValues(alpha: 0.3),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        labelStyle: TextStyle(color: _category == category ? Colors.white : Colors.white60, fontSize: 12),
                        side: BorderSide(color: _category == category ? accent : Colors.white24),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _field('Nombre', _nameField, errorText: _nameError, accent: accent),
                const SizedBox(height: 16),
                _field('Descripción corta', _shortDescField, maxLines: 2, accent: accent),
                const SizedBox(height: 16),
                _field('Detalles extensos', _longDetailsField, maxLines: 5, accent: accent),
                const SizedBox(height: 16),
                TagInputField(
                  label: 'Palabras clave (tags de activación)',
                  initialTags: _tags,
                  onChanged: (v) => _tags = v,
                  accent: accent,
                  hint: 'ej. taberna, capital',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _forceInclude,
                  onChanged: (v) => setState(() => _forceInclude = v),
                  activeThumbColor: accent,
                  title: const Text('Forzar inclusión en la IA', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Se incluirá en el contexto aunque no se mencione en el texto actual.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(_isEditing ? 'Guardar cambios' : 'Crear elemento'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required Color accent,
    int maxLines = 1,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
    );
  }
}
