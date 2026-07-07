import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/note_node.dart';
import '../models/note_group.dart';

class GroupColors {
  static const List<Color> colors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFFF43F5E), // Rose
    Color(0xFF06B6D4), // Cyan
    Color(0xFFD946EF), // Fuchsia
    Color(0xFF8B5CF6), // Violet
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
    Color(0xFF0EA5E9), // Sky
    Color(0xFF84CC16), // Lime
    Color(0xFFEC4899), // Pink
  ];
}

class SingleGroupPainter extends CustomPainter {
  final NoteGroup group;
  final List<Offset> hull;
  final Map<String, NoteNode> noteMap;

  SingleGroupPainter({
    required this.group,
    required this.hull,
    required this.noteMap,
  });

  Path _computeBlobPath(List<Offset> vertices) {
    final path = Path();
    if (vertices.isEmpty) return path;

    if (vertices.length < 3) {
      if (vertices.length == 1) {
        path.addOval(Rect.fromCircle(center: vertices.first, radius: 80.0));
      } else {
        final p1 = vertices[0];
        final p2 = vertices[1];
        final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final dist = math.sqrt((p2.dx - p1.dx) * (p2.dx - p1.dx) + (p2.dy - p1.dy) * (p2.dy - p1.dy));
        path.addOval(Rect.fromCircle(center: center, radius: dist / 2 + 80.0));
      }
      return path;
    }

    final firstMid = Offset(
      (vertices.last.dx + vertices.first.dx) / 2,
      (vertices.last.dy + vertices.first.dy) / 2,
    );
    path.moveTo(firstMid.dx, firstMid.dy);

    for (int i = 0; i < vertices.length; i++) {
      final current = vertices[i];
      final next = vertices[(i + 1) % vertices.length];
      final mid = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  bool _isPointInPolygon(Offset p, List<Offset> poly) {
    if (poly.isEmpty) return false;
    if (poly.length < 3) {
      if (poly.length == 1) {
        final dist = (p - poly.first).distance;
        return dist <= 80.0;
      } else {
        final p1 = poly[0];
        final p2 = poly[1];
        final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final dist = math.sqrt((p2.dx - p1.dx) * (p2.dx - p1.dx) + (p2.dy - p1.dy) * (p2.dy - p1.dy));
        final radius = dist / 2 + 80.0;
        return (p - center).distance <= radius;
      }
    }

    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      if ((poly[i].dy > p.dy) != (poly[j].dy > p.dy) &&
          p.dx < (poly[j].dx - poly[i].dx) * (p.dy - poly[i].dy) / (poly[j].dy - poly[i].dy) + poly[i].dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  bool hitTest(Offset position) {
    return _isPointInPolygon(position, hull);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (hull.isEmpty) return;

    final path = _computeBlobPath(hull);
    final color = GroupColors.colors[group.colorIndex % GroupColors.colors.length];

    // Draw outer soft glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(path, glowPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, borderPaint);

    // Draw semi-transparent fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant SingleGroupPainter oldDelegate) =>
      oldDelegate.group != group || oldDelegate.hull != hull || oldDelegate.noteMap != noteMap;
}
