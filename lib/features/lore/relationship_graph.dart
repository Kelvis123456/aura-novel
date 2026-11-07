import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/aura_theme.dart';
import 'models/character_model.dart';

/// Places characters on a plane so related ones sit close and unrelated ones drift apart
/// (Fruchterman-Reingold). Deterministic: the same sheets always give the same picture.
class GraphLayout {
  /// Position of each character id in a [size] x [size] square.
  static Map<String, Offset> compute(List<CharacterModel> characters, {double size = 1000, int iterations = 250}) {
    final ids = [for (final c in characters) c.id];
    final n = ids.length;
    if (n == 0) return {};
    if (n == 1) return {ids.first: Offset(size / 2, size / 2)};

    final index = {for (var i = 0; i < n; i++) ids[i]: i};
    final edges = <(int, int)>{};
    for (final c in characters) {
      for (final r in c.relationships) {
        final from = index[c.id], to = index[r.characterId];
        if (from != null && to != null && from != to) edges.add(from < to ? (from, to) : (to, from));
      }
    }

    final pos = [
      for (var i = 0; i < n; i++)
        Offset(size / 2 + size * 0.35 * math.cos(2 * math.pi * i / n), size / 2 + size * 0.35 * math.sin(2 * math.pi * i / n)),
    ];
    final k = math.sqrt(size * size / n) * 0.8;
    var temperature = size / 8;

    for (var step = 0; step < iterations; step++) {
      final force = List.filled(n, Offset.zero);
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          var d = pos[i] - pos[j];
          var dist = d.distance;
          if (dist < 0.01) {
            d = Offset(0.01 * (i + 1), 0.01 * (j + 1));
            dist = d.distance;
          }
          final push = d / dist * (k * k / dist);
          force[i] += push;
          force[j] -= push;
        }
      }
      for (final (a, b) in edges) {
        final d = pos[a] - pos[b];
        final dist = math.max(d.distance, 0.01);
        final pull = d / dist * (dist * dist / k);
        force[a] -= pull;
        force[b] += pull;
      }
      for (var i = 0; i < n; i++) {
        // gentle pull to the centre keeps disconnected groups on screen
        force[i] += (Offset(size / 2, size / 2) - pos[i]) * 0.02;
        final len = force[i].distance;
        if (len > 0) pos[i] += force[i] / len * math.min(len, temperature);
        pos[i] = Offset(pos[i].dx.clamp(60, size - 60), pos[i].dy.clamp(60, size - 60));
      }
      temperature *= 0.985;
    }
    return {for (var i = 0; i < n; i++) ids[i]: pos[i]};
  }
}

class RelationshipGraphScreen extends StatelessWidget {
  final List<CharacterModel> characters;
  const RelationshipGraphScreen({super.key, required this.characters});

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final withLinks = characters.where((ch) => ch.relationships.isNotEmpty || characters.any((o) => o.relationships.any((r) => r.characterId == ch.id))).toList();
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Relaciones')),
      body: withLinks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aún no hay relaciones. Añádelas en la ficha de cada personaje y aquí verás el mapa de quién se vincula con quién.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textDim, height: 1.5),
                ),
              ),
            )
          : InteractiveViewer(
              constrained: false,
              minScale: 0.3,
              maxScale: 2.5,
              boundaryMargin: const EdgeInsets.all(300),
              child: SizedBox(
                width: 1000,
                height: 1000,
                child: CustomPaint(painter: _GraphPainter(withLinks, GraphLayout.compute(withLinks), c)),
              ),
            ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<CharacterModel> characters;
  final Map<String, Offset> positions;
  final AuraColors colors;
  _GraphPainter(this.characters, this.positions, this.colors);

  void _text(Canvas canvas, String text, Offset center, TextStyle style, {double maxWidth = 150}) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 2, ellipsis: '…', textAlign: TextAlign.center)
      ..layout(maxWidth: maxWidth);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = colors.textFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const radius = 30.0;

    for (final ch in characters) {
      final a = positions[ch.id];
      if (a == null) continue;
      for (final r in ch.relationships) {
        final b = positions[r.characterId];
        if (b == null) continue;
        final dir = b - a;
        final dist = dir.distance;
        if (dist < 1) continue;
        final unit = dir / dist;
        final normal = Offset(-unit.dy, unit.dx);
        // each direction bows to its own side so a mutual pair shows two separate arrows
        final control = (a + b) / 2 + normal * 26;
        final start = a + unit * radius;
        final end = b - unit * radius;
        canvas.drawPath(Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy), line);

        final tangent = end - control;
        final tUnit = tangent / tangent.distance;
        final left = Offset(-tUnit.dy, tUnit.dx);
        canvas.drawPath(
          Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - tUnit.dx * 11 + left.dx * 5, end.dy - tUnit.dy * 11 + left.dy * 5)
            ..lineTo(end.dx - tUnit.dx * 11 - left.dx * 5, end.dy - tUnit.dy * 11 - left.dy * 5)
            ..close(),
          Paint()..color = colors.textFaint,
        );
        if (r.description.trim().isNotEmpty) {
          final mid = (start + control * 2 + end) / 4;
          _text(canvas, r.description, mid, TextStyle(fontSize: 11, color: colors.textDim, backgroundColor: colors.bg.withValues(alpha: 0.85)), maxWidth: 110);
        }
      }
    }

    for (final ch in characters) {
      final p = positions[ch.id];
      if (p == null) continue;
      canvas.drawCircle(p, radius, Paint()..color = colors.surfaceHigh);
      canvas.drawCircle(p, radius, Paint()..color = colors.accent..style = PaintingStyle.stroke..strokeWidth = 2);
      final initial = ch.name.trim().isEmpty ? '?' : ch.name.trim().substring(0, 1).toUpperCase();
      _text(canvas, initial, p, TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: colors.accentText));
      _text(canvas, ch.name, p + const Offset(0, radius + 14), TextStyle(fontSize: 13, color: colors.text), maxWidth: 120);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => old.characters != characters || old.positions != positions || old.colors != colors;
}
