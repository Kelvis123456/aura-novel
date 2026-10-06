import 'package:flutter/material.dart';

import 'lore_repository.dart';
import 'models/character_model.dart';
import 'widgets/tag_input_field.dart';

/// Full-height create/edit form for a [CharacterModel]. Pops with the
/// resulting model on save, or `null` if dismissed without saving.
class CharacterFormSheet extends StatefulWidget {
  final CharacterModel? existing;
  final List<CharacterModel> otherCharacters;
  final Color accent;

  const CharacterFormSheet({
    super.key,
    required this.otherCharacters,
    required this.accent,
    this.existing,
  });

  static Future<CharacterModel?> show(
    BuildContext context, {
    CharacterModel? existing,
    required List<CharacterModel> otherCharacters,
    required Color accent,
  }) {
    return showModalBottomSheet<CharacterModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0508),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CharacterFormSheet(existing: existing, otherCharacters: otherCharacters, accent: accent),
    );
  }

  @override
  State<CharacterFormSheet> createState() => _CharacterFormSheetState();
}

class _CharacterFormSheetState extends State<CharacterFormSheet> {
  late final TextEditingController _nameField;
  late final TextEditingController _appearanceField;
  late final TextEditingController _motivationField;
  late final TextEditingController _secretsField;

  late List<String> _aliases;
  late List<String> _personalityTraits;
  late List<CharacterRelationship> _relationships;
  late bool _forceInclude;

  String? _nameError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameField = TextEditingController(text: existing?.name ?? '');
    _appearanceField = TextEditingController(text: existing?.appearance ?? '');
    _motivationField = TextEditingController(text: existing?.motivation ?? '');
    _secretsField = TextEditingController(text: existing?.secretsLimits ?? '');
    _aliases = List.of(existing?.aliases ?? const []);
    _personalityTraits = List.of(existing?.personalityTraits ?? const []);
    _relationships = List.of(existing?.relationships ?? const []);
    _forceInclude = existing?.forceInclude ?? false;
  }

  @override
  void dispose() {
    _nameField.dispose();
    _appearanceField.dispose();
    _motivationField.dispose();
    _secretsField.dispose();
    super.dispose();
  }

  void _addRelationship() {
    if (widget.otherCharacters.isEmpty) return;
    setState(() {
      _relationships.add(CharacterRelationship(characterId: widget.otherCharacters.first.id, description: ''));
    });
  }

  void _removeRelationship(int index) => setState(() => _relationships.removeAt(index));

  void _save() {
    final name = _nameField.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'El nombre es obligatorio.');
      return;
    }

    final model = CharacterModel(
      id: widget.existing?.id ?? LoreRepository.generateId(),
      name: name,
      aliases: _aliases,
      appearance: _appearanceField.text.trim(),
      personalityTraits: _personalityTraits,
      motivation: _motivationField.text.trim(),
      secretsLimits: _secretsField.text.trim(),
      relationships: _relationships.where((r) => r.description.trim().isNotEmpty).toList(),
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
        initialChildSize: 0.9,
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
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  _isEditing ? 'Editar personaje' : 'Nuevo personaje',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                _field('Nombre', _nameField, errorText: _nameError, accent: accent),
                const SizedBox(height: 16),
                TagInputField(
                  label: 'Alias',
                  initialTags: _aliases,
                  onChanged: (v) => _aliases = v,
                  accent: accent,
                ),
                const SizedBox(height: 16),
                _field('Apariencia física', _appearanceField, maxLines: 3, accent: accent),
                const SizedBox(height: 16),
                TagInputField(
                  label: 'Rasgos de personalidad',
                  initialTags: _personalityTraits,
                  onChanged: (v) => _personalityTraits = v,
                  accent: accent,
                ),
                const SizedBox(height: 16),
                _field('Motivación principal', _motivationField, maxLines: 2, accent: accent),
                const SizedBox(height: 16),
                _field('Secretos / límites', _secretsField, maxLines: 3, accent: accent),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('RELACIONES', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.1)),
                    TextButton.icon(
                      onPressed: widget.otherCharacters.isEmpty ? null : _addRelationship,
                      icon: Icon(Icons.add, size: 16, color: accent),
                      label: Text('Añadir', style: TextStyle(color: accent, fontSize: 12)),
                    ),
                  ],
                ),
                for (var i = 0; i < _relationships.length; i++) _relationshipRow(i, accent),
                const SizedBox(height: 12),
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
                  child: Text(_isEditing ? 'Guardar cambios' : 'Crear personaje'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _relationshipRow(int index, Color accent) {
    final relationship = _relationships[index];
    final options = widget.otherCharacters;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: options.any((c) => c.id == relationship.characterId) ? relationship.characterId : null,
              dropdownColor: const Color(0xFF1A0B12),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              items: options
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _relationships[index] = CharacterRelationship(
                      characterId: value,
                      description: relationship.description,
                    ));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: relationship.description,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'ej. hermano mayor, protector',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                border: InputBorder.none,
              ),
              onChanged: (value) => _relationships[index] = CharacterRelationship(
                characterId: relationship.characterId,
                description: value,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => _removeRelationship(index),
          ),
        ],
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
