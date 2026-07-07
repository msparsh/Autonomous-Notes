import 'dart:ui';
import 'package:flutter/material.dart';

class CardPaperPainter extends CustomPainter {
  final String paperType;
  final Color lineColor;

  CardPaperPainter({
    required this.paperType,
    this.lineColor = const Color(0xFFE2E8F0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (paperType == 'blank') return;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    if (paperType == 'dot') {
      final double spacing = 24.0;
      final dotPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.8)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      List<Offset> points = [];
      for (double x = spacing; x < size.width; x += spacing) {
        for (double y = spacing; y < size.height; y += spacing) {
          points.add(Offset(x, y));
        }
      }
      if (points.isNotEmpty) {
        canvas.drawPoints(PointMode.points, points, dotPaint);
      }
    } else if (paperType == 'ruled') {
      final double spacing = 28.0;
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else if (paperType == 'graph') {
      final double spacing = 24.0;
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double x = spacing; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CardPaperPainter oldDelegate) =>
      oldDelegate.paperType != paperType || oldDelegate.lineColor != lineColor;
}
