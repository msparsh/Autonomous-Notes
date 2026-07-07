import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/note_node.dart';
import '../models/note_group.dart';

class GroupColors {
  static const List<Color> colors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFFEF4444), // Rose
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEC4899), // Pink
  ];
}

class GroupsPainter extends CustomPainter {
  final List<NoteGroup> groups;
  final Map<String, NoteNode> noteMap;

  GroupsPainter({
    required this.groups,
    required this.noteMap,
  });

  // Andrew's Monotone Chain Convex Hull algorithm
  List<Offset> _convexHull(List<Offset> points) {
    if (points.length <= 1) return points;

    final sorted = List<Offset>.from(points)
      ..sort((a, b) {
        if (a.dx != b.dx) {
          return a.dx.compareTo(b.dx);
        }
        return a.dy.compareTo(b.dy);
      });

    double cross(Offset o, Offset a, Offset b) {
      return (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    }

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();

    return [...lower, ...upper];
  }

  Path _computeBlobPath(List<Offset> vertices) {
    final path = Path();
    if (vertices.isEmpty) return path;

    if (vertices.length < 3) {
      // If we only have 1 or 2 points, draw a circle/pill around them.
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

    // Midpoint of last edge to first edge
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

  @override
  void paint(Canvas canvas, Size size) {
    for (final group in groups) {
      final List<Offset> pointsToHull = [];

      for (final noteId in group.noteIds) {
        final note = noteMap[noteId];
        if (note == null) continue;

        // Inflate the note rect slightly to leave breathing room
        final rect = Rect.fromLTWH(
          note.position.dx,
          note.position.dy,
          note.width,
          note.height,
        ).inflate(50.0); // 50px of padding around note cards

        // Add the 4 corners of the inflated rect to the points list
        pointsToHull.add(rect.topLeft);
        pointsToHull.add(rect.topRight);
        pointsToHull.add(rect.bottomLeft);
        pointsToHull.add(rect.bottomRight);
      }

      if (pointsToHull.isEmpty) continue;

      final hull = _convexHull(pointsToHull);
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
  }

  @override
  bool shouldRepaint(covariant GroupsPainter oldDelegate) =>
      oldDelegate.groups != groups || oldDelegate.noteMap != noteMap;
}
