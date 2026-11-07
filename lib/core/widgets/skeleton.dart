import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';

/// Placeholder rows shaped like the cards they stand in for, with a slow
/// pulse. Replaces the centered spinner while a list loads. With "reduce
/// motion" on, the rows stay still.
class SkeletonList extends StatefulWidget {
  final int count;
  final double itemHeight;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.count = 4,
    this.itemHeight = 78,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    return Padding(
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final fill = Color.lerp(c.surface, c.surfaceHigh, Curves.easeInOut.transform(_pulse.value))!;
          return Column(
            children: [
              for (var i = 0; i < widget.count; i++)
                Container(
                  height: widget.itemHeight,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.55 : 0.4,
                        child: Container(height: 12, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(6))),
                      ),
                      const SizedBox(height: 10),
                      FractionallySizedBox(
                        widthFactor: 0.3,
                        child: Container(height: 9, decoration: BoxDecoration(color: c.line.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(5))),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
