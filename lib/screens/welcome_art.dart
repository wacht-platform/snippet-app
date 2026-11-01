import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A computer with a terminal and a running-service light, ringed by slow radar pulses.
class ServiceArt extends StatelessWidget {
  const ServiceArt({super.key, required this.time, required this.hover});
  final Animation<double> time;
  final double hover;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ServicePainter(time, hover), size: Size.infinite);
}

/// A globe linked to a laptop, a phone and a server, with packets travelling the links.
class RemoteArt extends StatelessWidget {
  const RemoteArt({super.key, required this.time, required this.hover});
  final Animation<double> time;
  final double hover;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RemotePainter(time, hover), size: Size.infinite);
}

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

Paint _fill(Color c) => Paint()..color = c;

void _rings(Canvas canvas, Offset c, double u, double t, double hover,
    {double from = 64, double span = 90, int count = 3}) {
  for (var i = 0; i < count; i++) {
    final p = (t + i / count) % 1.0;
    final a = (1 - p) * (0.07 + 0.17 * hover);
    canvas.drawCircle(c, u * (from + p * span),
        _stroke(AppColors.accent.withValues(alpha: a), 1.2));
  }
}

class _ServicePainter extends CustomPainter {
  _ServicePainter(this.time, this.hover) : super(repaint: time);
  final Animation<double> time;
  final double hover;

  @override
  void paint(Canvas canvas, Size size) {
    final u = math.min(size.width, size.height) / 230;
    final c = Offset(size.width / 2, size.height / 2);
    final t = time.value;
    _rings(canvas, c, u, t, hover);

    final sw = u * 156, sh = u * 100;
    final screen = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c.translate(0, -u * 8), width: sw, height: sh),
        Radius.circular(u * 11));
    canvas.drawRRect(screen, _fill(AppColors.surface2));
    canvas.drawRRect(
        screen,
        _stroke(
            Color.lerp(
                AppColors.border2, AppColors.accent, 0.35 + 0.4 * hover)!,
            1.4));

    final left = screen.left + u * 14;
    final top = screen.top + u * 14;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(left + i * u * 9, top), u * 2.4,
          _fill(AppColors.fg4.withValues(alpha: 0.45)));
    }

    final widths = [0.74, 0.5, 0.82, 0.38];
    final full = sw - u * 28;
    for (var i = 0; i < widths.length; i++) {
      final y = top + u * 18 + i * u * 12;
      final w = full * widths[i];
      final bar = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y, w, u * 5), Radius.circular(u * 2.5));
      canvas.drawRRect(bar, _fill(AppColors.fg4.withValues(alpha: 0.28)));
      final sweep = ((t * 2 + i * 0.22) % 1.0);
      final fillW = w * (hover * sweep + (1 - hover) * 0.0);
      if (fillW > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(left, y, fillW, u * 5), Radius.circular(u * 2.5)),
            _fill(AppColors.accent.withValues(alpha: 0.75)));
      }
    }

    final blink = (math.sin(t * math.pi * 6) > 0) ? 1.0 : 0.25;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top + u * 18 + 4 * u * 12, u * 6, u * 8),
            Radius.circular(u * 1.5)),
        _fill(AppColors.accent.withValues(alpha: 0.9 * blink)));

    final dot = Offset(screen.right - u * 14, top);
    final pulse = (t * 2) % 1.0;
    canvas.drawCircle(dot, u * (3 + pulse * 7),
        _fill(AppColors.ok.withValues(alpha: (1 - pulse) * 0.28)));
    canvas.drawCircle(dot, u * 3.2, _fill(AppColors.ok));

    final stand = Path()
      ..moveTo(c.dx - u * 16, screen.bottom)
      ..lineTo(c.dx + u * 16, screen.bottom)
      ..lineTo(c.dx + u * 24, screen.bottom + u * 20)
      ..lineTo(c.dx - u * 24, screen.bottom + u * 20)
      ..close();
    canvas.drawPath(stand, _fill(AppColors.surface3));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, screen.bottom + u * 23),
                width: u * 84,
                height: u * 6),
            Radius.circular(u * 3)),
        _fill(AppColors.border2));
  }

  @override
  bool shouldRepaint(_ServicePainter old) => old.hover != hover;
}

class _RemotePainter extends CustomPainter {
  _RemotePainter(this.time, this.hover) : super(repaint: time);
  final Animation<double> time;
  final double hover;

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
        d += 10;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = math.min(size.width, size.height) / 230;
    final c = Offset(size.width / 2, size.height / 2);
    final t = time.value;
    _rings(canvas, c, u, t, hover, from: 40, span: 80, count: 3);

    final nodes = <(Offset, Size, double)>[
      (c.translate(-u * 96, u * 38), Size(u * 50, u * 32), 5),
      (c.translate(u * 98, -u * 30), Size(u * 24, u * 42), 6),
      (c.translate(u * 62, u * 70), Size(u * 38, u * 26), 4),
    ];
    final link = _stroke(
        Color.lerp(AppColors.border2, AppColors.accent, 0.3 + 0.5 * hover)!,
        1.2);
    for (var i = 0; i < nodes.length; i++) {
      final to = nodes[i].$1;
      final mid = Offset((c.dx + to.dx) / 2, (c.dy + to.dy) / 2 - u * 22);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
      _dashed(canvas, path, link);
      final m = path.computeMetrics().first;
      final p = (t * (1 + 2 * hover) + i * 0.33) % 1.0;
      final pos = m.getTangentForOffset(m.length * p)!.position;
      canvas.drawCircle(pos, u * 3.4,
          _fill(AppColors.accent.withValues(alpha: 0.35 + 0.6 * hover)));
    }

    for (final (at, sz, r) in nodes) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: sz.width, height: sz.height),
          Radius.circular(u * r));
      canvas.drawRRect(rr, _fill(AppColors.surface2));
      canvas.drawRRect(rr, _stroke(AppColors.border2, 1.3));
      canvas.drawCircle(at.translate(0, sz.height * 0.28), u * 1.8,
          _fill(AppColors.fg4.withValues(alpha: 0.6)));
    }

    final r = u * 36;
    canvas.drawCircle(c, r, _fill(AppColors.surface2));
    final line =
        _stroke(AppColors.accent.withValues(alpha: 0.45 + 0.4 * hover), 1.3);
    canvas.drawCircle(c, r, line);
    canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), line);
    for (final k in [0.42, 0.8]) {
      canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 2 * k, height: r * 2), line);
    }
    final lat = u * 17;
    for (final dy in [-lat, lat]) {
      final half = math.sqrt(math.max(0, r * r - dy * dy));
      canvas.drawLine(c.translate(-half, dy), c.translate(half, dy), line);
    }
  }

  @override
  bool shouldRepaint(_RemotePainter old) => old.hover != hover;
}
