import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/fantasy_calendar_model.dart';

/// Edits the era name and the months of a project's made-up calendar.
/// Pops with the new [FantasyCalendar], or null when nothing was saved.
class CalendarEditorScreen extends StatefulWidget {
  final FantasyCalendar? initial;
  final Color accent;

  const CalendarEditorScreen({super.key, this.initial, required this.accent});

  @override
  State<CalendarEditorScreen> createState() => _CalendarEditorScreenState();
}

class _MonthRow {
  final TextEditingController name;
  final TextEditingController days;

  _MonthRow(String name, int days)
      : name = TextEditingController(text: name),
        days = TextEditingController(text: '$days');
}

class _CalendarEditorScreenState extends State<CalendarEditorScreen> {
  late final TextEditingController _era;
  late final List<_MonthRow> _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _era = TextEditingController(text: initial?.eraName ?? 'Año');
    _rows = [for (final m in initial?.months ?? const <CalendarMonth>[]) _MonthRow(m.name, m.days)];
    if (_rows.isEmpty) _rows.add(_MonthRow('', 30));
  }

  @override
  void dispose() {
    _era.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.days.dispose();
    }
    super.dispose();
  }

  void _save() {
    final months = <CalendarMonth>[];
    for (final r in _rows) {
      final name = r.name.text.trim();
      final days = int.tryParse(r.days.text.trim()) ?? 0;
      if (name.isEmpty && r.days.text.trim() == '30') continue; // untouched blank row
      if (name.isEmpty || days < 1) {
        setState(() => _error = 'Cada mes necesita un nombre y al menos 1 día.');
        return;
      }
      months.add(CalendarMonth(name: name, days: days));
    }
    if (months.isEmpty) {
      setState(() => _error = 'Añade al menos un mes.');
      return;
    }
    final era = _era.text.trim();
    Navigator.of(context).pop(FantasyCalendar(eraName: era.isEmpty ? 'Año' : era, months: months));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Calendario del mundo'),
        actions: [TextButton(onPressed: _save, child: Text('Guardar', style: TextStyle(color: widget.accent)))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          TextField(controller: _era, decoration: const InputDecoration(labelText: 'Nombre de la era (ej. Año, Era del Sol)')),
          const SizedBox(height: 16),
          const Text('Meses, en orden', style: TextStyle(color: Colors.white70)),
          for (var i = 0; i < _rows.length; i++)
            Row(
              key: ObjectKey(_rows[i]),
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(controller: _rows[i].name, decoration: InputDecoration(labelText: 'Mes ${i + 1}')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rows[i].days,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Días'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white38),
                  tooltip: 'Quitar mes',
                  onPressed: _rows.length == 1
                      ? null
                      : () => setState(() {
                            final removed = _rows.removeAt(i);
                            removed.name.dispose();
                            removed.days.dispose();
                          }),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_MonthRow('', 30))),
            icon: Icon(Icons.add, color: widget.accent),
            label: Text('Añadir mes', style: TextStyle(color: widget.accent)),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }
}
