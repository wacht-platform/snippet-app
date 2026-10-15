import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

class _MochiPainter extends CustomPainter {
  _MochiPainter(this.color, this.size);

  final Color color;
  final double size;

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
      canvas.drawOval(Rect.fromCenter(center: const Offset(39, 81), width: 15, height: 8), blush);
      canvas.drawOval(Rect.fromCenter(center: const Offset(81, 81), width: 15, height: 8), blush);
    }
    final r = small ? 6.0 : 4.6;
    canvas.drawCircle(Offset(small ? 47 : 48, 72), r, ink);
    canvas.drawCircle(Offset(small ? 73 : 72, 72), r, ink);
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
  bool shouldRepaint(_MochiPainter old) => old.color != color || old.size != size;
}
