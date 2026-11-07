import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/aura_theme.dart';
import 'writing_stats.dart';

/// Today's words against the daily goal, plus the streak. Tap to set the goal.
class DailyGoalCard extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const DailyGoalCard({super.key, required this.refresh});

  @override
  State<DailyGoalCard> createState() => _DailyGoalCardState();
}

class _DailyGoalCardState extends State<DailyGoalCard> {
  int _today = 0;
  int _goal = 0;
  int _streak = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).projectRepository;
    final log = await repo.getWritingLog();
    final goal = await repo.getDailyGoal();
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _goal = goal;
      _today = log[WritingStats.dayKey(now)] ?? 0;
      _streak = WritingStats.streak(log, now);
    });
  }

  Future<void> _editGoal() async {
    final repo = AppScope.of(context).projectRepository;
    final field = TextEditingController(text: _goal > 0 ? '$_goal' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Meta diaria'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Palabras por día', helperText: 'Cuenta lo que se añade al texto desde el editor.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(0), child: const Text('Quitar meta')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(field.text.trim()) ?? 0), child: const Text('Guardar')),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    await repo.setDailyGoal(value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final c = context.aura;
    final done = _goal > 0 && _today >= _goal;
    final streakText = _streak == 0 ? 'Sin racha' : (_streak == 1 ? '1 día seguido' : '$_streak días seguidos');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _editGoal,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('HOY', style: TextStyle(color: c.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
                    const Spacer(),
                    Text(streakText, style: TextStyle(color: _streak > 0 ? c.accentText : c.textFaint, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _goal > 0 ? '$_today de $_goal palabras${done ? ' · meta cumplida' : ''}' : '$_today palabras · toca para poner una meta',
                  style: TextStyle(color: c.text, fontSize: 16),
                ),
                if (_goal > 0) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (_today / _goal).clamp(0.0, 1.0),
                    minHeight: 3,
                    color: done ? c.success : c.accent,
                    backgroundColor: c.line,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
