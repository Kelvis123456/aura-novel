import 'package:flutter/material.dart';

import '../../core/theme/aura_theme.dart';
import 'writing_profile.dart';

/// Bottom sheet to edit how a project's prose reads. Pops with the new profile.
class WritingProfileSheet extends StatefulWidget {
  final WritingProfile profile;

  const WritingProfileSheet({super.key, required this.profile});

  static Future<WritingProfile?> show(BuildContext context, WritingProfile profile) {
    return showModalBottomSheet<WritingProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.aura.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => WritingProfileSheet(profile: profile),
    );
  }

  @override
  State<WritingProfileSheet> createState() => _WritingProfileSheetState();
}

class _WritingProfileSheetState extends State<WritingProfileSheet> {
  late WritingProfile _p = widget.profile;
  late final _genre = TextEditingController(text: _p.genre);
  late final _tone = TextEditingController(text: _p.tone);
  late final _references = TextEditingController(text: _p.references);
  late final _directions = TextEditingController(text: _p.directions);

  @override
  void dispose() {
    for (final c in [_genre, _tone, _references, _directions]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_p.copyWith(
      genre: _genre.text.trim(),
      tone: _tone.text.trim(),
      references: _references.text.trim(),
      directions: _directions.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text('Cómo escribe este proyecto', style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 24, color: c.text)),
            const SizedBox(height: 4),
            Text('Se aplica a todo lo que la IA escriba aquí. Puedes cambiarlo en cualquier momento.', style: TextStyle(color: c.textDim, fontSize: 13)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _p.language,
              dropdownColor: c.surface,
              decoration: const InputDecoration(labelText: 'Idioma del texto'),
              items: [for (final e in WritingProfile.languageLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _p = _p.copyWith(language: v)),
            ),
            const SizedBox(height: 12),
            Text('Registro', style: TextStyle(color: c.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            SegmentedButton<WritingRegister>(
              showSelectedIcon: false,
              segments: [for (final r in WritingRegister.values) ButtonSegment(value: r, label: Text(r.label))],
              selected: {_p.register},
              onSelectionChanged: (s) => setState(() => _p = _p.copyWith(register: s.first)),
            ),
            const SizedBox(height: 6),
            Text(_p.register.hint, style: TextStyle(color: c.textFaint, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(controller: _genre, decoration: const InputDecoration(labelText: 'Género', hintText: 'terror gótico, romance oscuro, ciencia ficción…')),
            TextField(controller: _tone, decoration: const InputDecoration(labelText: 'Tono', hintText: 'melancólico, irónico, opresivo…')),
            const SizedBox(height: 12),
            DropdownButtonFormField<Pov>(
              initialValue: _p.pov,
              dropdownColor: c.surface,
              decoration: const InputDecoration(labelText: 'Punto de vista'),
              items: [for (final v in Pov.values) DropdownMenuItem(value: v, child: Text(v.label))],
              onChanged: (v) => setState(() => _p = _p.copyWith(pov: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _p.presentTense,
              onChanged: (v) => setState(() => _p = _p.copyWith(presentTense: v)),
              title: Text('Narrar en presente', style: TextStyle(color: c.text)),
              activeThumbColor: c.accent,
            ),
            TextField(
              controller: _references,
              decoration: const InputDecoration(labelText: 'Referentes de estilo', hintText: 'autores o libros cuya técnica quieres'),
            ),
            TextField(
              controller: _directions,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Indicaciones fijas', hintText: 'lo que siempre debe hacer o evitar'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _p.craftLevel == CraftLevel.esencial,
              onChanged: (v) => setState(() => _p = _p.copyWith(craftLevel: v ? CraftLevel.esencial : CraftLevel.completo)),
              title: Text('Oficio esencial', style: TextStyle(color: c.text)),
              subtitle: Text(
                'Manda reglas de escritura mucho más cortas. Actívalo con modelos pequeños o locales; con modelos grandes deja el oficio completo.',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
              activeThumbColor: c.accent,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _p.polishAfter,
              onChanged: (v) => setState(() => _p = _p.copyWith(polishAfter: v)),
              title: Text('Pulir al terminar cada capítulo', style: TextStyle(color: c.text)),
              subtitle: Text(
                'Reescribe cada escena una vez para quitar tics de IA y frases planas. Tarda el doble.',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
              activeThumbColor: c.accent,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
