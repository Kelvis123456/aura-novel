import 'package:flutter/material.dart';

import '../theme/aura_theme.dart';

/// The logo mark (pen nib over an open book, aura ring behind) drawn in the
/// theme's colors. Same geometry as design/logo/aura-icon.svg, in its
/// 512-unit space, so it matches the launcher icon.
class AuraMark extends StatelessWidget {
  final double size;

  const AuraMark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    return Semantics(
      label: 'Aura Novel',
      child: CustomPaint(
        size: Size.square(size),
        painter: _AuraMarkPainter(ring: c.accent, ink: c.text, gap: c.bg),
      ),
    );
  }
}

class _AuraMarkPainter extends CustomPainter {
  final Color ring;
  final Color ink;
  final Color gap;

  const _AuraMarkPainter({required this.ring, required this.ink, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 512, size.height / 512);

    canvas.drawCircle(
      const Offset(256, 244),
      178,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..color = ring,
    );

    final inkPaint = Paint()..color = ink;
    final gapPaint = Paint()..color = gap;

    canvas.drawPath(
      Path()
        ..moveTo(256, 104)
        ..lineTo(328, 300)
        ..quadraticBezierTo(256, 276, 184, 300)
        ..close(),
      inkPaint,
    );
    canvas.drawCircle(const Offset(256, 214), 18, gapPaint);
    canvas.drawPath(
      Path()
        ..moveTo(248, 214)
        ..lineTo(264, 214)
        ..lineTo(261, 280)
        ..lineTo(251, 280)
        ..close(),
      gapPaint,
    );

    // The margin under the book hides the lower arc of the ring.
    canvas.drawPath(
      Path()
        ..moveTo(64, 360)
        ..quadraticBezierTo(160, 330, 256, 372)
        ..quadraticBezierTo(352, 330, 448, 360)
        ..lineTo(448, 448)
        ..lineTo(64, 448)
        ..close(),
      gapPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(92, 372)
        ..quadraticBezierTo(168, 350, 256, 388)
        ..quadraticBezierTo(344, 350, 420, 372)
        ..lineTo(420, 424)
        ..quadraticBezierTo(344, 402, 256, 438)
        ..quadraticBezierTo(168, 402, 92, 424)
        ..close(),
      inkPaint,
    );
  }

  @override
  bool shouldRepaint(_AuraMarkPainter old) => old.ring != ring || old.ink != ink || old.gap != gap;
}
