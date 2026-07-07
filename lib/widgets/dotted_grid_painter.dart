import 'dart:ui';
import 'package:flutter/material.dart';

class DottedGridPainter extends CustomPainter {
  final double spacing;
  final Color color;
  final Matrix4 transform;
  final Size viewportSize;

  DottedGridPainter({
    required this.transform,
    required this.viewportSize,
    this.spacing = 30.0,
    this.color = const Color(0xFFF1F5F9),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Extract translation and scale from the transform matrix
    final translation = transform.getTranslation();
    final scale = transform.getMaxScaleOnAxis().clamp(0.1, 10.0);

    // Calculate visible bounds in local coordinates
    final double left = (-translation.x / scale).clamp(0.0, size.width);
    final double top = (-translation.y / scale).clamp(0.0, size.height);
    final double right = ((viewportSize.width - translation.x) / scale).clamp(0.0, size.width);
    final double bottom = ((viewportSize.height - translation.y) / scale).clamp(0.0, size.height);

    // Align start coordinates to the spacing grid
    final double startX = (left / spacing).floor() * spacing;
    final double startY = (top / spacing).floor() * spacing;
    final double endX = (right / spacing).ceil() * spacing;
    final double endY = (bottom / spacing).ceil() * spacing;

    final List<Offset> points = [];
    for (double x = startX; x <= endX; x += spacing) {
      for (double y = startY; y <= endY; y += spacing) {
        points.add(Offset(x, y));
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    if (points.isNotEmpty) {
      canvas.drawPoints(PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DottedGridPainter oldDelegate) =>
      oldDelegate.spacing != spacing ||
      oldDelegate.color != color ||
      oldDelegate.transform != transform ||
      oldDelegate.viewportSize != viewportSize;
}
