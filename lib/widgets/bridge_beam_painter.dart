import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paints the live "thought bridge beam" between two selected note nodes.
///
/// Layers:
///   1. Animated dashed amber line connecting the two nodes.
///   2. Midpoint glow orb that pulses with the animation.
///   3. When [collapseProgress] > 0, the two node positions converge toward
///      the midpoint, simulating the "collapse into synthesis" animation.
class BridgeBeamPainter extends CustomPainter {
  final Offset? nodeA;
  final Offset? nodeB;

  /// 0.0 → 1.0 animation tick (continuous loop for dashes + pulse)
  final double animationValue;

  /// 0.0 = normal beam, 1.0 = fully collapsed (nodes merged at midpoint)
  final double collapseProgress;

  const BridgeBeamPainter({
    required this.nodeA,
    required this.nodeB,
    required this.animationValue,
    this.collapseProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodeA == null) return;

    // ── When only node A is selected: draw a soft "seeking" halo ────────────
    if (nodeB == null) {
      _drawSeekingHalo(canvas, nodeA!);
      return;
    }

    // ── Apply collapse transform: lerp positions toward midpoint ─────────────
    final rawMid = Offset(
      (nodeA!.dx + nodeB!.dx) / 2,
      (nodeA!.dy + nodeB!.dy) / 2,
    );
    final effectiveA = Offset.lerp(nodeA!, rawMid, collapseProgress)!;
    final effectiveB = Offset.lerp(nodeB!, rawMid, collapseProgress)!;
    final mid = Offset(
      (effectiveA.dx + effectiveB.dx) / 2,
      (effectiveA.dy + effectiveB.dy) / 2,
    );

    // ── Draw glow underlay ────────────────────────────────────────────────────
    _drawGlowLine(canvas, effectiveA, effectiveB);

    // ── Draw animated dashed line ─────────────────────────────────────────────
    _drawDashedLine(canvas, effectiveA, effectiveB);

    // ── Draw midpoint pulse orb ───────────────────────────────────────────────
    _drawMidpointOrb(canvas, mid);

    // ── Draw node halos ───────────────────────────────────────────────────────
    if (collapseProgress < 0.95) {
      _drawNodeHalo(canvas, effectiveA, isPrimary: true);
      _drawNodeHalo(canvas, effectiveB, isPrimary: false);
    }

    // ── Collapse burst effect ─────────────────────────────────────────────────
    if (collapseProgress > 0.5) {
      _drawCollapseBurst(canvas, mid, collapseProgress);
    }
  }

  void _drawSeekingHalo(Canvas canvas, Offset center) {
    final double pulse = (math.sin(animationValue * math.pi * 2) + 1) / 2;
    final paint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 32 + 10 * pulse, paint);

    final innerPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.15 * pulse)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 28 + 8 * pulse, innerPaint);
  }

  void _drawGlowLine(Canvas canvas, Offset a, Offset b) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: 0.18),
          const Color(0xFF6366F1).withValues(alpha: 0.18),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromPoints(a, b))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawLine(a, b, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b) {
    final totalDx = b.dx - a.dx;
    final totalDy = b.dy - a.dy;
    final totalLen = math.sqrt(totalDx * totalDx + totalDy * totalDy);
    if (totalLen < 1.0) return;

    final unitX = totalDx / totalLen;
    final unitY = totalDy / totalLen;

    const double dashLen = 12.0;
    const double gapLen = 8.0;
    const double period = dashLen + gapLen;

    // Animate the dash offset so dashes "flow" from A to B
    final double offset = (animationValue * period) % period;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFF59E0B),
          const Color(0xFFE0781A),
          const Color(0xFF818CF8),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromPoints(a, b))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    double drawn = -offset;
    while (drawn < totalLen) {
      final dashStart = drawn.clamp(0.0, totalLen);
      final dashEnd = (drawn + dashLen).clamp(0.0, totalLen);
      if (dashEnd > dashStart) {
        canvas.drawLine(
          Offset(a.dx + unitX * dashStart, a.dy + unitY * dashStart),
          Offset(a.dx + unitX * dashEnd, a.dy + unitY * dashEnd),
          paint,
        );
      }
      drawn += period;
    }
  }

  void _drawMidpointOrb(Canvas canvas, Offset mid) {
    final double pulse = (math.sin(animationValue * math.pi * 4) + 1) / 2;
    final double radius = 10.0 + 4.0 * pulse;

    // Outer halo
    final haloPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.20 + 0.15 * pulse)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(mid, radius + 8, haloPaint);

    // Core gradient orb
    final orbPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95),
          const Color(0xFFF59E0B).withValues(alpha: 0.9),
          const Color(0xFF6366F1).withValues(alpha: 0.6),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: mid, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(mid, radius, orbPaint);

    // Orbiting ring
    final ringPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(mid, radius + 5 + 3 * pulse, ringPaint);
  }

  void _drawNodeHalo(Canvas canvas, Offset center, {required bool isPrimary}) {
    final double pulse = (math.sin(animationValue * math.pi * 2 + (isPrimary ? 0 : math.pi)) + 1) / 2;
    final color = isPrimary ? const Color(0xFFF59E0B) : const Color(0xFF818CF8);

    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.25 + 0.20 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, 40 + 6 * pulse, outerPaint);

    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.45 + 0.25 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 34 + 4 * pulse, innerPaint);
  }

  void _drawCollapseBurst(Canvas canvas, Offset mid, double progress) {
    // Radial burst lines emanating from the midpoint
    const int rayCount = 12;
    final double burstRadius = 60.0 * (progress - 0.5) * 2.0;
    final double alpha = ((1.0 - progress) * 2.0).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: alpha * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * math.pi * 2 + animationValue * math.pi;
      final innerR = burstRadius * 0.3;
      final outerR = burstRadius;
      final start = Offset(
        mid.dx + math.cos(angle) * innerR,
        mid.dy + math.sin(angle) * innerR,
      );
      final end = Offset(
        mid.dx + math.cos(angle) * outerR,
        mid.dy + math.sin(angle) * outerR,
      );
      canvas.drawLine(start, end, paint);
    }

    // Central flash circle
    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * 0.5)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(mid, burstRadius * 0.4, flashPaint);
  }

  @override
  bool shouldRepaint(covariant BridgeBeamPainter old) =>
      old.nodeA != nodeA ||
      old.nodeB != nodeB ||
      old.animationValue != animationValue ||
      old.collapseProgress != collapseProgress;
}
