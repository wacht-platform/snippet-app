import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';

const _mochiColor = Color(0xFFB9C6FF);
const _mochiSize = 105.0;
const _feetFromTop = 0.881;

/// Scene units are 400x300, fitted and centred in the available box.
class _Fit {
  _Fit(Size s) {
    u = math.min(s.width / 400, s.height / 300);
    ox = (s.width - 400 * u) / 2;
    oy = (s.height - 300 * u) / 2;
  }
  late final double u, ox, oy;

  Widget mochi(double feetX, double feetY,
      {required bool happy, double scale = 1}) {
    final size = _mochiSize * scale * u;
    return Positioned(
      left: ox + feetX * u - size / 2,
      top: oy + feetY * u - _feetFromTop * size,
      child: MochiIcon(
          color: _mochiColor,
          size: size,
          eyes: happy ? MochiEyes.happy : MochiEyes.dot),
    );
  }
}

Paint _fill(Color c) => Paint()..color = c;
Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

void _shadow(Canvas c, double rx) => c.drawOval(
    Rect.fromCenter(center: const Offset(200, 262), width: rx * 2, height: 18),
    _fill(Colors.black.withValues(alpha: 0.35)));

/// Left: the delivery box. Mochi peeks out and pops up when hovered.
class UnboxArt extends StatelessWidget {
  const UnboxArt({super.key, required this.time, required this.hover});
  final Animation<double> time;
  final double hover;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final f = _Fit(box.biggest);
        final pop = Curves.easeOutBack.transform(hover.clamp(0.0, 1.0));
        final feet = 236 - 22 - 32 * pop;
        return AnimatedBuilder(
          animation: time,
          builder: (_, __) => Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _BoxBack(f))),
            f.mochi(200, feet, happy: hover > 0.35),
            Positioned.fill(
                child: CustomPaint(painter: _BoxFront(f, hover, time.value))),
          ]),
        );
      });
}

class _BoxBack extends CustomPainter {
  _BoxBack(this.f);
  final _Fit f;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(f.ox, f.oy);
    canvas.scale(f.u);
    _shadow(canvas, 125);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoxBack old) => false;
}

class _BoxFront extends CustomPainter {
  _BoxFront(this.f, this.h, this.t);
  final _Fit f;
  final double h, t;

  void _flap(Canvas c, List<Offset> pts, Offset pivot, double deg) {
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(deg * math.pi / 180);
    c.translate(-pivot.dx, -pivot.dy);
    final p = Path()..addPolygon(pts, true);
    c.drawPath(p, _fill(const Color(0xFF2A2A2F)));
    c.drawPath(p, _stroke(const Color(0xFF3B3B42), 2));
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(f.ox, f.oy);
    canvas.scale(f.u);
    final open = Curves.easeOutBack.transform(h.clamp(0.0, 1.0));
    _flap(
        canvas,
        const [
          Offset(108, 190),
          Offset(156, 190),
          Offset(148, 164),
          Offset(98, 172)
        ],
        const Offset(156, 190),
        -8 - 54 * open);
    _flap(
        canvas,
        const [
          Offset(244, 190),
          Offset(292, 190),
          Offset(302, 172),
          Offset(252, 164)
        ],
        const Offset(244, 190),
        8 + 54 * open);
    final front = Path()
      ..moveTo(108, 190)
      ..lineTo(292, 190)
      ..lineTo(284, 262)
      ..lineTo(116, 262)
      ..close();
    canvas.drawPath(front, _fill(const Color(0xFF232327)));
    canvas.drawPath(front, _stroke(const Color(0xFF3B3B42), 2));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(168, 208, 64, 9), const Radius.circular(4.5)),
        _fill(AppColors.accent.withValues(alpha: 0.85)));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(178, 226, 44, 5), const Radius.circular(2.5)),
        _fill(const Color(0xFF3B3B42)));

    if (h > 0.05) {
      final pieces = [
        (150.0, -40.0, 0.0, const Color(0xFF7FD1A6), true),
        (240.0, 30.0, 0.3, const Color(0xFFF2A7A0), true),
        (210.0, 55.0, 0.7, AppColors.accent, false),
        (190.0, -60.0, 1.0, const Color(0xFFF7E3A1), false),
      ];
      for (final (x0, dx, delay, color, square) in pieces) {
        final p = (t * 4 + delay) % 1.0;
        final a = h * (p < 0.15 ? p / 0.15 : (1 - p) / 0.85);
        final at = Offset(x0 + dx * p, 170 - 80 * p);
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(p * 3.5);
        final paint = _fill(color.withValues(alpha: a.clamp(0.0, 1.0)));
        if (square) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(const Rect.fromLTWH(-3.5, -3.5, 7, 7),
                  const Radius.circular(1.5)),
              paint);
        } else {
          canvas.drawCircle(Offset.zero, 3.6, paint);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoxFront old) => old.h != h || old.t != t;
}

/// Right: Mochi holds a cable that straightens and plugs into the other machine.
class PlugArt extends StatelessWidget {
  const PlugArt({super.key, required this.time, required this.hover});
  final Animation<double> time;
  final double hover;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final f = _Fit(box.biggest);
        return AnimatedBuilder(
          animation: time,
          builder: (_, __) {
            final hop =
                -12 * hover * math.sin(time.value * math.pi * 2 * 4).abs();
            return Stack(children: [
              Positioned.fill(
                  child:
                      CustomPaint(painter: _PlugScene(f, hover, time.value))),
              f.mochi(96, 248 + hop, happy: hover > 0.35, scale: 0.96),
            ]);
          },
        );
      });
}

class _PlugScene extends CustomPainter {
  _PlugScene(this.f, this.h, this.t);
  final _Fit f;
  final double h, t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(f.ox, f.oy);
    canvas.scale(f.u);
    _shadow(canvas, 150);

    final socket = RRect.fromRectAndRadius(
        const Rect.fromLTWH(312, 178, 46, 78), const Radius.circular(9));
    canvas.drawRRect(socket, _fill(const Color(0xFF1D1D20)));
    canvas.drawRRect(socket, _stroke(const Color(0xFF34343A), 2));
    for (final x in [324.0, 340.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 198, 6, 18), const Radius.circular(3)),
          _fill(AppColors.bg));
    }
    canvas.drawCircle(
        const Offset(335, 236), 3, _fill(const Color(0xFF2B2B31)));

    if (h > 0) {
      final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 9);
      canvas.drawCircle(
          const Offset(335, 207),
          30,
          _fill(AppColors.accent
              .withValues(alpha: 0.14 * h * (0.55 + 0.45 * pulse))));
      if (h > 0.7 && math.sin(t * math.pi * 2 * 6) > 0.4) {
        canvas.drawPath(
            Path()
              ..moveTo(296, 196)
              ..lineTo(288, 208)
              ..lineTo(298, 208)
              ..lineTo(290, 222),
            _stroke(const Color(0xFFF7E3A1), 2.5));
      }
    }

    final cable = _stroke(const Color(0xFF4A4A52), 5);
    final slack = Path()
      ..moveTo(140, 232)
      ..cubicTo(150, 262, 190, 268, 205, 248)
      ..cubicTo(220, 228, 246, 226, 252, 236);
    final taut = Path()
      ..moveTo(140, 232)
      ..cubicTo(190, 240, 250, 224, 296, 233);
    if (h < 1) {
      canvas.saveLayer(
          null, Paint()..color = Colors.white.withValues(alpha: 1 - h));
      canvas.drawPath(slack, cable);
      canvas.restore();
    }
    if (h > 0) {
      canvas.saveLayer(
          null, Paint()..color = Colors.white.withValues(alpha: h));
      canvas.drawPath(taut, cable);
      canvas.restore();
    }

    final dx = 52 * Curves.easeOutBack.transform(h.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(dx, 0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(244, 224, 26, 18), const Radius.circular(5)),
        _fill(AppColors.accent));
    for (final y in [228.0, 236.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(268, y, 9, 4), const Radius.circular(2)),
          _fill(const Color(0xFFC9BAFC)));
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlugScene old) => old.h != h || old.t != t;
}
