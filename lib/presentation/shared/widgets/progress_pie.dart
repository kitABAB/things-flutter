import 'dart:math';
import 'package:flutter/material.dart';

class ProgressPie extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final Color color;

  const ProgressPie({
    super.key,
    required this.progress,
    this.size = 24.0,
    this.color = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      // 进度变化平滑过渡。
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _PiePainter(progress: value, color: color),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PiePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);

    // Draw background circle (outline)
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, bgPaint);

    if (progress > 0) {
      // Draw progress arc
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, // Start at top
        2 * pi * progress, // Sweep angle
        true, // Use center to make it a pie slice
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
