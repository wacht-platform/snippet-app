import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

const mochiPalette = <(String, Color)>[
  ('Periwinkle', Color(0xFFB9C6FF)),
  ('Sakura', Color(0xFFF6C6D2)),
  ('Matcha', Color(0xFFC4E3B5)),
  ('Taro', Color(0xFFD5C3F5)),
  ('Peach', Color(0xFFF9C9A6)),
  ('Butter', Color(0xFFF7E3A1)),
  ('Sky', Color(0xFFBDE3F5)),
  ('Hojicha', Color(0xFFD8B48C)),
];

enum MascotShape { mochi, bunny, cat, bear, ghost, cloud, onigiri }

MascotShape mascotShapeNamed(String? name) => MascotShape.values
    .firstWhere((m) => m.name == name, orElse: () => MascotShape.mochi);

final agentColors = ValueNotifier<Map<String, String>>(const {});
final agentShapes = ValueNotifier<Map<String, String>>(const {});

MascotShape mascotShapeFor(String agentId) =>
    mascotShapeNamed(agentShapes.value[agentId]);

void rememberAgentShapes(Iterable<(String, String?)> agents) {
  final next = <String, String>{};
  for (final (id, shape) in agents) {
    if (shape != null && shape.isNotEmpty) next[id] = shape;
  }
  if (!mapEquals(next, agentShapes.value)) agentShapes.value = next;
}

void setRememberedAgentShape(String id, String? shape) {
  final next = Map<String, String>.of(agentShapes.value);
  if (shape == null) {
    next.remove(id);
  } else {
    next[id] = shape;
  }
  agentShapes.value = next;
}

Color? parseHexColor(String? hex) {
  final h = hex?.trim().replaceFirst('#', '') ?? '';
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color defaultMochiColor(String agentId) => const Color(0xFFEDEDED);

Color mochiColorFor(String agentId) =>
    parseHexColor(agentColors.value[agentId]) ?? defaultMochiColor(agentId);

void rememberAgentColors(Iterable<(String, String?)> agents) {
  final next = <String, String>{};
  for (final (id, color) in agents) {
    if (color != null && color.isNotEmpty) next[id] = color;
  }
  if (!mapEquals(next, agentColors.value)) agentColors.value = next;
}

void setRememberedAgentColor(String id, String? color) {
  final next = Map<String, String>.of(agentColors.value);
  if (color == null) {
    next.remove(id);
  } else {
    next[id] = color;
  }
  agentColors.value = next;
}

class MochiIcon extends StatelessWidget {
  const MochiIcon(
      {super.key,
      required this.color,
      this.size = 18,
      this.shape = MascotShape.mochi});

  final Color color;
  final double size;
  final MascotShape shape;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MochiPainter(color, size, shape: shape)),
      );
}

class AgentMochi extends StatelessWidget {
  const AgentMochi(this.agentId, {super.key, this.size = 18});

  final String agentId;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([agentColors, agentShapes]),
        builder: (_, __) => MochiIcon(
            color: mochiColorFor(agentId),
            size: size,
            shape: mascotShapeFor(agentId)),
      );
}

enum MochiEyes { dot, flat, happy }

class WorkingMochi extends StatefulWidget {
  const WorkingMochi(
      {super.key,
      this.size = 20,
      this.squeeze = false,
      this.color,
      this.shape = MascotShape.mochi});

  final MascotShape shape;
  final double size;
  final bool squeeze;
  final Color? color;

  @override
  State<WorkingMochi> createState() => _WorkingMochiState();
}

class _WorkingMochiState extends State<WorkingMochi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.squeeze ? 1800 : 1400),
  );
  final _rng = math.Random();
  Timer? _mood;
  MochiEyes _eyes = MochiEyes.dot;

  @override
  void initState() {
    super.initState();
    _c.repeat();
    _nextMood();
  }

  void _nextMood() {
    _mood = Timer(Duration(milliseconds: 2200 + _rng.nextInt(2600)), () {
      if (!mounted) return;
      final pool = widget.squeeze
          ? const [MochiEyes.flat, MochiEyes.dot]
          : const [MochiEyes.dot, MochiEyes.dot, MochiEyes.flat, MochiEyes.happy];
      MochiEyes next;
      do {
        next = pool[_rng.nextInt(pool.length)];
      } while (next == _eyes);
      setState(() => _eyes = next);
      _nextMood();
    });
  }

  @override
  void dispose() {
    _mood?.cancel();
    _c.dispose();
    super.dispose();
  }

  static double _out(double t) => 1 - math.pow(1 - t, 3).toDouble();
  static double _in(double t) => t * t * t;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final size = widget.size;
    final color = widget.color ?? mochiPalette.first.$2;
    if (still) {
      return MochiIcon(color: color, size: size, shape: widget.shape);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        var dy = 0.0, sx = 1.0, sy = 1.0;
        if (widget.squeeze) {
          final k = math.pow(math.sin(t * math.pi), 2).toDouble();
          sy = 1 - .2 * k;
          sx = 1 + .14 * k;
        } else {
          final h = size * .3;
          if (t < .18) {
            final e = _out(t / .18);
            sy = 1 - .16 * e;
            sx = 1 + .12 * e;
          } else if (t < .5) {
            final p = (t - .18) / .32;
            dy = -h * _out(p);
            sy = 1 + .1 * (1 - p);
            sx = 1 - .06 * (1 - p);
          } else if (t < .72) {
            final p = (t - .5) / .22;
            dy = -h * (1 - _in(p));
            sy = 1 + .06 * p;
            sx = 1 - .04 * p;
          } else if (t < .86) {
            final k = math.sin((t - .72) / .14 * math.pi);
            sy = 1 - .18 * k;
            sx = 1 + .14 * k;
          }
        }
        final blink = _eyes == MochiEyes.dot && t > .9 && t < .96 ? 1.0 : 0.0;
        final look = math.sin(_c.lastElapsedDuration == null
                ? 0
                : _c.lastElapsedDuration!.inMilliseconds / 900) *
            3;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(sx, sy, 1),
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _MochiPainter(color, size,
                    eyes: _eyes,
                    blink: blink,
                    look: widget.squeeze ? 0 : look,
                    shape: widget.shape),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MochiPainter extends CustomPainter {
  _MochiPainter(this.color, this.size,
      {this.eyes = MochiEyes.dot,
      this.blink = 0,
      this.look = 0,
      this.shape = MascotShape.mochi});

  final MascotShape shape;
  final Color color;
  final double size;
  final MochiEyes eyes;
  final double blink;
  final double look;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 84;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-18, -26);
    final small = size < 22;
    _drawBody(canvas, shape, color);
    final ink = Paint()..color = const Color(0xFF15161C);
    if (!small) {
      final blush = Paint()..color = const Color(0xE6F2A7A0);
      canvas.drawOval(Rect.fromCenter(center: const Offset(39, 81), width: 15, height: 8), blush);
      canvas.drawOval(Rect.fromCenter(center: const Offset(81, 81), width: 15, height: 8), blush);
    }
    final r = small ? 6.0 : 4.6;
    final lx = (small ? 47.0 : 48.0) + look, rx = (small ? 73.0 : 72.0) + look;
    final line = Paint()
      ..color = const Color(0xFF15161C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 4.6 : 3
      ..strokeCap = StrokeCap.round;
    for (final ex in [lx, rx]) {
      switch (eyes) {
        case MochiEyes.dot:
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(ex, 72),
                  width: r * 2,
                  height: r * 2 * (1 - blink * .85)),
              ink);
        case MochiEyes.flat:
          canvas.drawLine(Offset(ex - r, 72), Offset(ex + r, 72), line);
        case MochiEyes.happy:
          canvas.drawPath(
              Path()
                ..moveTo(ex - r, 74)
                ..quadraticBezierTo(ex, 64, ex + r, 74),
              line);
      }
    }
    if (!small) {
      final mouth = Path()
        ..moveTo(54, 80)
        ..quadraticBezierTo(57, 84, 60, 80)
        ..quadraticBezierTo(63, 84, 66, 80);
      canvas.drawPath(
          mouth,
          Paint()
            ..color = const Color(0xFF15161C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MochiPainter old) =>
      old.color != color ||
      old.size != size ||
      old.eyes != eyes ||
      old.blink != blink ||
      old.look != look ||
      old.shape != shape;
}

Path _blob() => Path()
  ..moveTo(20, 84)
  ..cubicTo(20, 60, 36, 48, 60, 48)
  ..cubicTo(84, 48, 100, 60, 100, 84)
  ..cubicTo(100, 98, 84, 100, 60, 100)
  ..cubicTo(36, 100, 20, 98, 20, 84)
  ..close();

void _drawBody(Canvas canvas, MascotShape shape, Color color) {
  final fill = Paint()..color = color;
  final inner = Paint()..color = const Color(0x66F2A7A0);
  final round = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeJoin = StrokeJoin.round;
  switch (shape) {
    case MascotShape.mochi:
      canvas.drawPath(
          Path()
            ..moveTo(20, 84)
            ..cubicTo(20, 54, 38, 38, 60, 38)
            ..cubicTo(82, 38, 100, 54, 100, 84)
            ..cubicTo(100, 98, 84, 100, 60, 100)
            ..cubicTo(36, 100, 20, 98, 20, 84)
            ..close(),
          fill);
      canvas.drawPath(
          Path()
            ..moveTo(60, 39)
            ..quadraticBezierTo(66, 25, 80, 28)
            ..quadraticBezierTo(74, 41, 60, 39)
            ..close(),
          Paint()..color = const Color(0xFF7FD1A6));
    case MascotShape.bunny:
      for (final (cx, tilt) in [(44.0, -0.14), (76.0, 0.14)]) {
        canvas.save();
        canvas.translate(cx, 42);
        canvas.rotate(tilt);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 17, height: 40), fill);
        canvas.drawOval(
            Rect.fromCenter(center: const Offset(0, 2), width: 8, height: 26),
            inner);
        canvas.restore();
      }
      canvas.drawPath(_blob(), fill);
    case MascotShape.cat:
      for (final sign in [-1.0, 1.0]) {
        double x(double dx) => 60 + sign * dx;
        final ear = Path()
          ..moveTo(x(34), 62)
          ..lineTo(x(30), 33)
          ..lineTo(x(12), 52)
          ..close();
        canvas.drawPath(ear, fill);
        canvas.drawPath(ear, round);
        canvas.drawPath(
            Path()
              ..moveTo(x(28), 54)
              ..lineTo(x(26), 41)
              ..lineTo(x(18), 52)
              ..close(),
            inner);
      }
      canvas.drawPath(_blob(), fill);
      final whisker = Paint()
        ..color = const Color(0x8015161C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (final sign in [-1.0, 1.0]) {
        canvas.drawLine(Offset(60 + sign * 46, 78), Offset(60 + sign * 34, 80), whisker);
        canvas.drawLine(Offset(60 + sign * 46, 85), Offset(60 + sign * 34, 84), whisker);
      }
    case MascotShape.bear:
      for (final sign in [-1.0, 1.0]) {
        canvas.drawCircle(Offset(60 + sign * 28, 52), 11, fill);
        canvas.drawCircle(Offset(60 + sign * 28, 52), 5.5, inner);
      }
      canvas.drawPath(_blob(), fill);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(60, 85), width: 30, height: 20),
          Paint()..color = const Color(0x55FFFFFF));
    case MascotShape.ghost:
      canvas.drawPath(
          Path()
            ..moveTo(20, 102)
            ..lineTo(20, 70)
            ..cubicTo(20, 50, 38, 40, 60, 40)
            ..cubicTo(82, 40, 100, 50, 100, 70)
            ..lineTo(100, 102)
            ..quadraticBezierTo(92, 94, 84, 102)
            ..quadraticBezierTo(76, 110, 68, 102)
            ..quadraticBezierTo(60, 94, 52, 102)
            ..quadraticBezierTo(44, 110, 36, 102)
            ..quadraticBezierTo(28, 94, 20, 102)
            ..close(),
          fill);
    case MascotShape.cloud:
      canvas.drawCircle(const Offset(38, 80), 19, fill);
      canvas.drawCircle(const Offset(60, 64), 24, fill);
      canvas.drawCircle(const Offset(83, 80), 19, fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(26, 72, 68, 28), const Radius.circular(14)),
          fill);
    case MascotShape.onigiri:
      final body = Path()
        ..moveTo(60, 40)
        ..cubicTo(68, 40, 74, 46, 80, 56)
        ..lineTo(98, 88)
        ..cubicTo(103, 97, 98, 100, 90, 100)
        ..lineTo(30, 100)
        ..cubicTo(22, 100, 17, 97, 22, 88)
        ..lineTo(40, 56)
        ..cubicTo(46, 46, 52, 40, 60, 40)
        ..close();
      canvas.drawPath(body, fill);
      canvas.save();
      canvas.clipPath(body);
      canvas.drawRect(const Rect.fromLTWH(10, 91, 100, 12),
          Paint()..color = const Color(0xFF2B2E36));
      canvas.restore();
  }
}

class DottedMochi extends StatelessWidget {
  const DottedMochi({super.key, this.width = 300, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * 0.7,
        child: CustomPaint(
            painter: _DottedMochiPainter(color ?? AppColors.accent)),
      );
}

class _DottedMochiPainter extends CustomPainter {
  _DottedMochiPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 360;
    canvas.scale(k);
    const step = 9.0, cx = 180.0, cy = 150.0, rx = 132.0;
    const ryTop = 128.0, ryBot = 70.0;
    const eyes = [Offset(132, 150), Offset(228, 150)];
    final fill = Paint()..color = color;
    final faint = Paint()..color = color.withValues(alpha: 0.28);
    var seed = 7;
    double rnd() {
      seed = (seed * 9301 + 49297) % 233280;
      return seed / 233280;
    }

    for (var y = 6.0; y < 248; y += step) {
      final ox = ((y / step).floor() % 2) * step / 2;
      for (var x = 6.0; x < 356; x += step) {
        final px = x + ox;
        final dx = (px - cx) / rx;
        final dy = (y - cy) / (y < cy ? ryTop : ryBot);
        final r = math.pow(dx.abs(), 2.4) + math.pow(dy.abs(), 2.4);
        final eye = eyes.any((e) =>
            math.sqrt(math.pow(px - e.dx, 2) + math.pow((y - e.dy) * 0.8, 2)) <
            15);
        if (r <= 1 && !eye) {
          final lx = (px - 120) / 220, ly = (y - 70) / 200;
          final light = math.max(0.0, 1 - math.sqrt(lx * lx + ly * ly));
          final s = 2.4 +
              4.2 * (0.35 + 0.65 * light) * (1 - math.pow(r, 6) * 0.5);
          canvas.drawCircle(Offset(px, y), s / 2, fill);
        } else if (r > 1 && r < 2.6 && rnd() > 0.55 + (r - 1) * 0.25) {
          canvas.drawCircle(Offset(px, y), 0.8, faint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DottedMochiPainter old) => old.color != color;
}
