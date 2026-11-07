import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Visible desde el capítulo N" for the public wiki. Empty or 0 = always.
class VisibleFromField extends StatelessWidget {
  final TextEditingController controller;

  const VisibleFromField({super.key, required this.controller});

  static int parse(String text) => int.tryParse(text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        labelText: 'Visible en la wiki desde el capítulo',
        helperText: 'Vacío = siempre. Evita spoilers a quien lea hasta cierto punto.',
      ),
    );
  }
}
