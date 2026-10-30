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

final agentColors = ValueNotifier<Map<String, String>>(const {});

Color? parseHexColor(String? hex) {
  final h = hex?.trim().replaceFirst('#', '') ?? '';
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color defaultMochiColor(String agentId) {
  if (agentId == 'mission-control') return mochiPalette.first.$2;
  var h = 0;
  for (final u in agentId.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return mochiPalette[1 + h % (mochiPalette.length - 1)].$2;
}

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
  const MochiIcon({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MochiPainter(color, size)),
      );
}

class AgentMochi extends StatelessWidget {
  const AgentMochi(this.agentId, {super.key, this.size = 18});

  final String agentId;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: agentColors,
        builder: (_, __, ___) =>
            MochiIcon(color: mochiColorFor(agentId), size: size),
      );
}

enum MochiEyes { dot, flat, happy }

class WorkingMochi extends StatefulWidget {
  const WorkingMochi(
      {super.key, this.size = 20, this.squeeze = false, this.color});

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
          : const [
              MochiEyes.dot,
              MochiEyes.dot,
              MochiEyes.flat,
              MochiEyes.happy
            ];
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
      return MochiIcon(color: color, size: size);
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
                    eyes: _eyes, blink: blink, look: widget.squeeze ? 0 : look),
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
      {this.eyes = MochiEyes.dot, this.blink = 0, this.look = 0});

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
    final body = Path()
      ..moveTo(20, 84)
      ..cubicTo(20, 54, 38, 38, 60, 38)
      ..cubicTo(82, 38, 100, 54, 100, 84)
      ..cubicTo(100, 98, 84, 100, 60, 100)
      ..cubicTo(36, 100, 20, 98, 20, 84)
      ..close();
    canvas.drawPath(body, Paint()..color = color);
    final leaf = Path()
      ..moveTo(60, 39)
      ..quadraticBezierTo(66, 25, 80, 28)
      ..quadraticBezierTo(74, 41, 60, 39)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF7FD1A6));
    final ink = Paint()..color = const Color(0xFF15161C);
    if (!small) {
      final blush = Paint()..color = const Color(0xE6F2A7A0);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(39, 81), width: 15, height: 8),
          blush);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(81, 81), width: 15, height: 8),
          blush);
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
      old.look != look;
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
          final s =
              2.4 + 4.2 * (0.35 + 0.65 * light) * (1 - math.pow(r, 6) * 0.5);
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
