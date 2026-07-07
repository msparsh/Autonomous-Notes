import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/note_node.dart';
import '../models/note_group.dart';

class ConnectionEdge {
  final String sourceId;
  final String targetId;
  final double similarity;

  ConnectionEdge({
    required this.sourceId,
    required this.targetId,
    required this.similarity,
  });
}

class ConnectionsPainter extends CustomPainter {
  final List<NoteNode> notes;
  final List<ConnectionEdge> edges;
  final double animationValue; // 0.0 to 1.0, driven by an animation controller
  final Map<String, NoteNode> noteMap;
  final String searchQuery;
  final List<NoteGroup> groups;

  ConnectionsPainter({
    required this.notes,
    required this.edges,
    required this.animationValue,
    required this.noteMap,
    required this.searchQuery,
    required this.groups,
  });

  Offset _getIntersectionPoint(Rect rect, Offset target) {
    final center = rect.center;
    if (center == target) return center;

    final dx = target.dx - center.dx;
    final dy = target.dy - center.dy;

    double tMin = double.infinity;

    // Check vertical boundaries (left and right)
    if (dx != 0) {
      final targetX = dx > 0 ? rect.right : rect.left;
      final t = (targetX - center.dx) / dx;
      if (t >= 0) {
        tMin = math.min(tMin, t);
      }
    }

    // Check horizontal boundaries (top and bottom)
    if (dy != 0) {
      final targetY = dy > 0 ? rect.bottom : rect.top;
      final t = (targetY - center.dy) / dy;
      if (t >= 0) {
        tMin = math.min(tMin, t);
      }
    }

    if (tMin != double.infinity && !tMin.isNaN) {
      return Offset(center.dx + dx * tMin, center.dy + dy * tMin);
    }

    return center;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || edges.isEmpty) return;

    final String query = searchQuery.trim().toLowerCase();

    // Map each note to the set of group IDs it belongs to
    final Map<String, Set<String>> noteGroups = {};
    for (final g in groups) {
      for (final noteId in g.noteIds) {
        noteGroups.putIfAbsent(noteId, () => {}).add(g.id);
      }
    }

    for (final edge in edges) {
      final source = noteMap[edge.sourceId];
      final target = noteMap[edge.targetId];

      if (source == null || target == null) continue;

      // Group isolation: only connect if they belong to the exact same set of groups
      final sourceGroupIds = noteGroups[edge.sourceId] ?? {};
      final targetGroupIds = noteGroups[edge.targetId] ?? {};
      final bool setsEqual = sourceGroupIds.length == targetGroupIds.length &&
          sourceGroupIds.containsAll(targetGroupIds);
      if (!setsEqual) continue;

      if (query.isNotEmpty) {
        final sourceMatches = source.content.toLowerCase().contains(query);
        final targetMatches = target.content.toLowerCase().contains(query);
        if (!sourceMatches || !targetMatches) continue;
      }

      // Calculate centers of notes
      final sourceCenter = Offset(
        source.position.dx + source.width / 2,
        source.position.dy + source.height / 2,
      );
      final targetCenter = Offset(
        target.position.dx + target.width / 2,
        target.position.dy + target.height / 2,
      );

      final sourceRect = Rect.fromLTWH(
        source.position.dx,
        source.position.dy,
        source.width,
        source.height,
      );
      final targetRect = Rect.fromLTWH(
        target.position.dx,
        target.position.dy,
        target.width,
        target.height,
      );

      // Draw curved bezier line (quadratic curve with a control point)
      // The control point is displaced slightly from the midpoint to create an elegant curve
      final midPoint = Offset(
        (sourceCenter.dx + targetCenter.dx) / 2,
        (sourceCenter.dy + targetCenter.dy) / 2,
      );

      // Add a slight orthogonal displacement for the bezier control point
      final dx = targetCenter.dx - sourceCenter.dx;
      final dy = targetCenter.dy - sourceCenter.dy;
      final normal = Offset(-dy, dx);
      final normalLength = math.sqrt(normal.dx * normal.dx + normal.dy * normal.dy);
      
      Offset controlPoint = midPoint;
      if (normalLength > 0.0) {
        // Displace control point based on distance (longer lines curve more)
        final displacement = (normalLength * 0.12).clamp(10.0, 100.0);
        controlPoint = Offset(
          midPoint.dx + (normal.dx / normalLength) * displacement,
          midPoint.dy + (normal.dy / normalLength) * displacement,
        );
      }

      // Calculate intersections at boundaries
      final sourceEdge = _getIntersectionPoint(sourceRect, controlPoint);
      final targetEdge = _getIntersectionPoint(targetRect, controlPoint);

      final Path path = Path()
        ..moveTo(sourceEdge.dx, sourceEdge.dy)
        ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, targetEdge.dx, targetEdge.dy);

      // Paint setup
      final opacity = (edge.similarity * 0.65).clamp(0.15, 0.75);
      final strokeWidth = (edge.similarity * 5.0).clamp(1.5, 4.5);

      // Under-glow path (blurry look)
      final glowPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF6366F1).withValues(alpha: opacity * 0.4),
            const Color(0xFF818CF8).withValues(alpha: opacity * 0.4),
          ],
        ).createShader(Rect.fromPoints(sourceEdge, targetEdge))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, glowPaint);

      // Core connection path
      final corePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF4F46E5).withValues(alpha: opacity),
            const Color(0xFF6366F1).withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromPoints(sourceEdge, targetEdge))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, corePaint);

      // Animated glowing pulse dot moving along the path
      // Calculate quadratic bezier point at animationValue
      final t = animationValue;
      final mt = 1.0 - t;
      // Formula: B(t) = (1-t)^2 * P0 + 2*(1-t)*t * P1 + t^2 * P2
      final pulseX = mt * mt * sourceEdge.dx + 2 * mt * t * controlPoint.dx + t * t * targetEdge.dx;
      final pulseY = mt * mt * sourceEdge.dy + 2 * mt * t * controlPoint.dy + t * t * targetEdge.dy;
      final pulseOffset = Offset(pulseX, pulseY);

      // Fade dot in/out smoothly as it moves along the line
      final double fadeFactor = math.sin(t * math.pi);

      // Pulse outer halo
      final pulseHaloPaint = Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: 0.7 * fadeFactor)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pulseOffset, 8.0, pulseHaloPaint);

      // Pulse core dot
      final pulseDotPaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: fadeFactor)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pulseOffset, 4.0, pulseDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionsPainter oldDelegate) =>
      oldDelegate.notes != notes ||
      oldDelegate.edges != edges ||
      oldDelegate.animationValue != animationValue ||
      oldDelegate.groups != groups;
}
