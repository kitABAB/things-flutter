import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_view.dart';
import '../theme/app_theme.dart';

/// 各系统视图的「空状态」手绘风格插画（矢量绘制，无需图片资源，自动适配深浅色）。
/// 线条采用圆头描边 + 贝塞尔曲线，营造轻松的手绘感，配合视图强调色。
class EmptyIllustration extends StatelessWidget {
  final AppView view;
  final double size;

  const EmptyIllustration({super.key, required this.view, this.size = 150});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: CustomPaint(
        painter: _EmptyPainter(
          view: view,
          accent: view.color,
          ink: AppTheme.textSecondary,
          cardColor: Theme.of(context).cardColor,
        ),
      ),
    );
  }
}

class _EmptyPainter extends CustomPainter {
  final AppView view;
  final Color accent;
  final Color ink;
  final Color cardColor;

  _EmptyPainter({
    required this.view,
    required this.accent,
    required this.ink,
    required this.cardColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = ink.withValues(alpha: 0.55);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = accent.withValues(alpha: 0.12);
    final dot = Paint()
      ..style = PaintingStyle.fill
      ..color = accent.withValues(alpha: 0.6);

    switch (view) {
      case AppView.inbox:
        _inbox(canvas, size, stroke, fill, thin);
        break;
      case AppView.today:
        _today(canvas, size, stroke, fill, dot);
        break;
      case AppView.upcoming:
        _upcoming(canvas, size, stroke, fill, dot);
        break;
      case AppView.anytime:
        _anytime(canvas, size, stroke, fill);
        break;
      case AppView.someday:
        _someday(canvas, size, stroke, fill, dot);
        break;
      case AppView.logbook:
        _logbook(canvas, size, stroke, fill, dot);
        break;
    }
  }

  // 收件箱：一个敞口托盘，里面一张便签微微露出。
  void _inbox(Canvas c, Size s, Paint stroke, Paint fill, Paint thin) {
    final cx = s.width / 2;
    final base = s.height * 0.72;
    final tray = Path()
      ..moveTo(cx - 50, base - 26)
      ..lineTo(cx - 38, base)
      ..lineTo(cx + 38, base)
      ..lineTo(cx + 50, base - 26);
    final note = Path()
      ..moveTo(cx - 26, base - 30)
      ..lineTo(cx - 26, base - 64)
      ..lineTo(cx + 26, base - 64)
      ..lineTo(cx + 26, base - 30);
    c.drawPath(note, fill);
    c.drawLine(Offset(cx - 14, base - 52), Offset(cx + 14, base - 52), thin);
    c.drawLine(Offset(cx - 14, base - 44), Offset(cx + 8, base - 44), thin);
    c.drawPath(note, stroke);
    c.drawPath(tray, stroke);
    c.drawLine(Offset(cx - 50, base - 26), Offset(cx + 50, base - 26), stroke);
  }

  // 今天：一颗带光芒的星 + 地平线，悠闲的一天。
  void _today(Canvas c, Size s, Paint stroke, Paint fill, Paint dot) {
    final cx = s.width / 2;
    final cy = s.height * 0.42;
    final star = _starPath(Offset(cx, cy), 26, 12);
    c.drawPath(star, fill);
    c.drawPath(star, stroke);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      const r1 = 34.0, r2 = 44.0;
      c.drawLine(
        Offset(cx + r1 * math.cos(a), cy + r1 * math.sin(a)),
        Offset(cx + r2 * math.cos(a), cy + r2 * math.sin(a)),
        stroke,
      );
    }
    final y = s.height * 0.84;
    c.drawLine(Offset(cx - 56, y), Offset(cx + 56, y), stroke);
    c.drawCircle(Offset(cx - 40, y - 6), 2.4, dot);
    c.drawCircle(Offset(cx + 44, y - 6), 2.4, dot);
  }

  // 计划：一页日历，顶上两个环，下方日期点阵。
  void _upcoming(Canvas c, Size s, Paint stroke, Paint fill, Paint dot) {
    final cx = s.width / 2;
    final top = s.height * 0.30;
    final r = RRect.fromLTRBR(
        cx - 42, top, cx + 42, top + 74, const Radius.circular(10));
    c.drawRRect(r, fill);
    c.drawRRect(r, stroke);
    c.drawLine(Offset(cx - 42, top + 20), Offset(cx + 42, top + 20), stroke);
    c.drawLine(Offset(cx - 22, top - 8), Offset(cx - 22, top + 8), stroke);
    c.drawLine(Offset(cx + 22, top - 8), Offset(cx + 22, top + 8), stroke);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        c.drawCircle(
            Offset(cx - 22 + col * 22, top + 38 + row * 18), 2.6, dot);
      }
    }
  }

  // 随时：三张错落堆叠的卡片。
  void _anytime(Canvas c, Size s, Paint stroke, Paint fill) {
    final cx = s.width / 2;
    final cy = s.height * 0.5;
    final back = Paint()
      ..style = PaintingStyle.fill
      ..color = cardColor;
    for (var i = 2; i >= 0; i--) {
      final dx = (i - 1) * 10.0;
      final dy = i * 9.0 - 9;
      final r = RRect.fromLTRBR(
          cx - 46 + dx, cy - 22 + dy, cx + 46 + dx, cy + 18 + dy,
          const Radius.circular(9));
      c.drawRRect(r, i == 0 ? fill : back);
      c.drawRRect(r, stroke);
    }
  }

  // 将来：一只盖着的箱子 + 上方月亮与星点（冷冻 / 梦想）。
  void _someday(Canvas c, Size s, Paint stroke, Paint fill, Paint dot) {
    final cx = s.width / 2;
    final top = s.height * 0.46;
    final box = RRect.fromLTRBR(
        cx - 44, top, cx + 44, top + 46, const Radius.circular(8));
    c.drawRRect(box, fill);
    c.drawRRect(box, stroke);
    c.drawLine(Offset(cx - 44, top + 14), Offset(cx + 44, top + 14), stroke);
    c.drawLine(Offset(cx, top + 14), Offset(cx, top + 46), stroke);
    final moon = Path()
      ..addArc(
          Rect.fromCircle(center: Offset(cx, s.height * 0.22), radius: 16),
          -1.2, 4.2);
    c.drawPath(moon, stroke);
    c.drawCircle(Offset(cx - 34, s.height * 0.18), 2.2, dot);
    c.drawCircle(Offset(cx + 30, s.height * 0.26), 2.6, dot);
    c.drawCircle(Offset(cx + 38, s.height * 0.12), 1.8, dot);
  }

  // 日志：一个圆里的对勾 + 小亮点，已完成的成就感。
  void _logbook(Canvas c, Size s, Paint stroke, Paint fill, Paint dot) {
    final cx = s.width / 2;
    final cy = s.height * 0.5;
    c.drawCircle(Offset(cx, cy), 34, fill);
    c.drawCircle(Offset(cx, cy), 34, stroke);
    final check = Path()
      ..moveTo(cx - 16, cy + 2)
      ..lineTo(cx - 4, cy + 14)
      ..lineTo(cx + 18, cy - 14);
    c.drawPath(check, stroke);
    c.drawCircle(Offset(cx + 34, cy - 30), 2.6, dot);
    c.drawCircle(Offset(cx - 36, cy + 26), 2.2, dot);
  }

  Path _starPath(Offset center, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _EmptyPainter old) =>
      old.view != view ||
      old.accent != accent ||
      old.ink != ink ||
      old.cardColor != cardColor;
}
