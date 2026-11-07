import 'package:flutter/material.dart';

import '../../projects/models/project_model.dart';

/// "Pertenece a": one project or the shared universe (null).
class ProjectOwnerField extends StatelessWidget {
  final List<ProjectModel> projects;
  final String? value;
  final ValueChanged<String?> onChanged;

  const ProjectOwnerField({super.key, required this.projects, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // A deleted project would leave the stored id without an item to show.
    final known = value == null || projects.any((p) => p.id == value);
    return DropdownButtonFormField<String?>(
      initialValue: known ? value : null,
      isExpanded: true,
      dropdownColor: const Color(0xFF1A0B12),
      decoration: const InputDecoration(
        labelText: 'Pertenece a',
        helperText: 'Universo compartido = aparece en todos tus proyectos.',
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Universo compartido')),
        for (final p in projects) DropdownMenuItem<String?>(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}
