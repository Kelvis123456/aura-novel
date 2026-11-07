import 'package:flutter/material.dart';

import '../../core/theme/aura_theme.dart';
import 'craft_library.dart';

/// What the author chose in the tools sheet.
class ToolRequest {
  final String moduleId;
  final String material;
  final String note;

  const ToolRequest(this.moduleId, this.material, this.note);
}

/// Lists the craft modules by group and, once one is picked, asks for the
/// passage to run it on ([defaultMaterial] is prefilled).
Future<ToolRequest?> showCraftTools(BuildContext context, {required String defaultMaterial}) {
  return showModalBottomSheet<ToolRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.aura.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ToolsSheet(defaultMaterial: defaultMaterial),
  );
}

class _ToolsSheet extends StatefulWidget {
  final String defaultMaterial;

  const _ToolsSheet({required this.defaultMaterial});

  @override
  State<_ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<_ToolsSheet> {
  CraftModule? _picked;
  late final _material = TextEditingController(text: widget.defaultMaterial);
  final _note = TextEditingController();

  @override
  void dispose() {
    _material.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final picked = _picked;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => picked == null ? _list(c, scroll) : _form(c, scroll, picked),
      ),
    );
  }

  Widget _list(AuraColors c, ScrollController scroll) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text('Herramientas de oficio', style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 24, color: c.text)),
        const SizedBox(height: 4),
        Text('Cada una aplica una técnica de escritura a un texto tuyo.', style: TextStyle(color: c.textDim, fontSize: 13)),
        for (final group in CraftGroup.values) ...[
          const SizedBox(height: 20),
          Text(group.label.toUpperCase(), style: TextStyle(color: c.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          for (final m in CraftLibrary.modules.where((m) => m.group == group))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.label, style: TextStyle(color: c.text)),
              subtitle: Text(m.blurb, style: TextStyle(color: c.textDim, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: c.textFaint),
              onTap: () => setState(() => _picked = m),
            ),
        ],
      ],
    );
  }

  Widget _form(AuraColors c, ScrollController scroll, CraftModule m) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _picked = null)),
            Expanded(child: Text(m.label, style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 24, color: c.text))),
          ],
        ),
        Text(m.blurb, style: TextStyle(color: c.textDim, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(
          controller: _material,
          maxLines: 10,
          minLines: 5,
          decoration: const InputDecoration(labelText: 'Texto o pregunta', alignLabelWithHint: true),
        ),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota para la IA (opcional)')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_material.text.trim().isEmpty) return;
            Navigator.of(context).pop(ToolRequest(m.id, _material.text, _note.text));
          },
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
