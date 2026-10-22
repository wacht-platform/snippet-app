import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ambient/capture.dart';
import '../../../ambient/controller.dart';
import '../../../api.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../widgets.dart';

Color _modeColor(String mode) =>
    mode == 'active' ? AppColors.accent : AppColors.ok;

Color _stateColor(AmbientSettings? s, AmbientStatus st) {
  if (s != null && s.enabled && st.error != null) return AppColors.danger;
  return _modeColor(s?.mode ?? 'passive');
}

class _AmbientModel extends ChangeNotifier {
  _AmbientModel(this.client) {
    ambient.addListener(notifyListeners);
    ambient.bind();
    load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  final DaemonClient client;
  final AmbientController ambient = AmbientController.instance;
  AmbientSettings? settings;
  String? error;
  bool busy = false;
  Timer? _timer;

  AmbientStatus get status => ambient.status;
  bool get on => settings?.enabled ?? false;
  bool get listening => on && status.running;

  Future<void> load() async {
    try {
      settings = await client.getAmbientSettings();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle(bool value) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final (saved, err) = await ambient.setEnabled(client, value);
    if (saved != null) settings = saved;
    error = err;
    busy = false;
    notifyListeners();
    if (value && err == null && !await ambient.ignoringBattery) {
      await ambient.requestBatteryExemption();
    }
  }

  Future<void> shiftMode(int dir) =>
      setMode(dir > 0 ? 'active' : 'passive');

  Future<void> setMode(String mode) async {
    final before = settings;
    if (before == null || before.mode == mode) return;
    settings = AmbientSettings(
        enabled: before.enabled,
        mode: mode,
        keySet: before.keySet,
        devices: before.devices);
    notifyListeners();
    try {
      settings = await client.setAmbientSettings(mode: mode);
    } catch (e) {
      settings = before;
      error = '$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ambient.removeListener(notifyListeners);
    super.dispose();
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.level, this.color, this.alive);
  final double t;
  final double level;
  final Color color;
  final bool alive;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final tau = math.pi * 2;
    final breathe = alive ? 1 + math.sin(t * tau) * 0.025 : 1.0;
    final radius = r * 0.9 * breathe;
    final step = math.max(size.shortestSide / 40, 2.3);
    if (alive) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: 0.16 + level * 0.1),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    final blink = alive && t > 0.86 && t < 0.92;
    final eyeH = blink ? 0.18 : 1.0;
    final eyes = [Offset(-radius * 0.34, radius * 0.06), Offset(radius * 0.34, radius * 0.06)];
    final eyeRx = radius * 0.085, eyeRy = radius * 0.13 * eyeH;
    final paint = Paint();
    final amp = alive ? 0.12 + level * 0.22 : 0.0;
    final rows = (radius * 2 / step).ceil() + 2;
    for (var j = 0; j < rows; j++) {
      final y = -radius + j * step * 0.866;
      final ox = (j % 2) * step / 2;
      for (var x = -radius - step + ox; x <= radius + step; x += step) {
        final d = math.sqrt(x * x + y * y) / radius;
        if (d > 1) continue;
        var skip = false;
        for (final e in eyes) {
          final ex = (x - e.dx) / eyeRx, ey = (y - e.dy) / math.max(eyeRy, 0.01);
          if (ex * ex + ey * ey < 1) skip = true;
        }
        if (!alive && (y - eyes[0].dy).abs() < step * 0.5) {
          for (final e in eyes) {
            if ((x - e.dx).abs() < eyeRx * 1.4) skip = true;
          }
        }
        if (skip) continue;
        final nx = x / radius, ny = y / radius;
        final z = math.sqrt(math.max(0.0, 1 - nx * nx - ny * ny));
        final light = (nx * -0.38 + ny * -0.5 + z * 0.78).clamp(0.0, 1.0);
        var s = step * (0.2 + 0.66 * light) * (1 - math.pow(d, 8) * 0.45);
        var a = alive ? 0.55 + 0.45 * light : 0.22 + 0.25 * light;
        if (alive) {
          final w = math.sin((d * 2.0 - t * 2) * tau);
          s *= 1 + amp * w;
          a = (a + w * 0.12).clamp(0.2, 1.0);
        }
        paint.color = color.withValues(alpha: a);
        canvas.drawCircle(c + Offset(x, y), math.max(s / 2, 0.3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}

class _Orb extends StatefulWidget {
  const _Orb(
      {required this.size,
      required this.color,
      required this.alive,
      required this.level,
      this.period = const Duration(milliseconds: 3200)});
  final double size;
  final Color color;
  final bool alive;
  final double level;
  final Duration period;

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.alive && !reduce;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(_c.value, widget.level, widget.color, widget.alive),
      ),
    );
  }
}

class AmbientHeaderOrb extends StatefulWidget {
  const AmbientHeaderOrb({super.key, required this.client});
  final DaemonClient client;

  @override
  State<AmbientHeaderOrb> createState() => _AmbientHeaderOrbState();
}

class _AmbientHeaderOrbState extends State<AmbientHeaderOrb> {
  late final _AmbientModel _m = _AmbientModel(widget.client)
    ..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(_m.settings, _m.status);
    return Semantics(
      button: true,
      label: 'Ambient listening',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAmbientStage(context, widget.client),
        onLongPress: () {
          if (_m.settings == null) return;
          HapticFeedback.mediumImpact();
          _m.toggle(!_m.on);
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 150) return;
          HapticFeedback.selectionClick();
          _m.shiftMode(v < 0 ? 1 : -1);
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: _Orb(
              size: 38,
              color: color,
              alive: _m.listening,
              level: _m.status.speaking ? 1 : 0,
              period: const Duration(milliseconds: 2400),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAmbientStage(BuildContext context, DaemonClient client) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => AmbientStage(client: client),
    transitionsBuilder: (_, a, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  ));
}

class AmbientStage extends StatefulWidget {
  const AmbientStage({super.key, required this.client});
  final DaemonClient client;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage> {
  static const _modes = ['passive', 'active'];
  late final _AmbientModel _m = _AmbientModel(widget.client)
    ..addListener(_changed);
  PageController? _pager;
  double _page = 0;

  void _changed() {
    if (!mounted) return;
    final s = _m.settings;
    if (s != null && _pager == null) {
      final i = _modes.indexOf(s.mode).clamp(0, 1);
      _page = i.toDouble();
      _pager = PageController(initialPage: i, viewportFraction: 0.8)
        ..addListener(() {
          if (mounted) setState(() => _page = _pager!.page ?? _page);
        });
    } else if (s != null && _pager!.hasClients) {
      final i = _modes.indexOf(s.mode);
      if (i >= 0 && (_pager!.page ?? i).round() != i) {
        _pager!.animateToPage(i,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _m.dispose();
    _pager?.dispose();
    super.dispose();
  }

  String _caption(String mode, bool selected) {
    final running = selected && _m.on;
    if (!running) {
      return mode == 'active'
          ? 'Listens and speaks up when it matters'
          : 'Listens quietly and keeps a record';
    }
    if (!_m.listening) return 'Starting';
    if (_m.status.speaking) return 'Hearing you';
    return mode == 'active' ? 'Listening, ready to speak up' : 'Listening quietly';
  }

  Widget _globe(int i, double size) {
    final mode = _modes[i];
    final selected = _m.settings?.mode == mode;
    final dist = (_page - i).abs().clamp(0.0, 1.0);
    final color = selected ? _stateColor(_m.settings, _m.status) : _modeColor(mode);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected
          ? () {
              if (_m.settings != null) {
                toast(context, _m.on ? 'Hold to stop' : 'Hold to start');
              }
            }
          : () => _pager?.animateToPage(i,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic),
      onLongPress: selected && _m.settings != null && !_m.busy
          ? () {
              HapticFeedback.mediumImpact();
              _m.toggle(!_m.on);
            }
          : null,
      child: Center(
        child: Opacity(
          opacity: 1 - dist * 0.65,
          child: Transform.scale(
            scale: 1 - dist * 0.3,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Orb(
                size: size,
                color: color,
                alive: selected && _m.listening,
                level: selected && _m.status.speaking ? 1 : 0,
              ),
              const SizedBox(height: 8),
              Text(mode == 'active' ? 'Active' : 'Passive',
                  style: sans(16,
                      weight: W.strong,
                      color: selected ? AppColors.fg1 : AppColors.fg3)),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(_caption(mode, selected),
                    key: ValueKey(_caption(mode, selected)),
                    textAlign: TextAlign.center,
                    style: sans(13, color: AppColors.fg4)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final err = _m.error ?? _m.status.error;
    final width = MediaQuery.sizeOf(context).width;
    final globe = math.min(width * 0.7, 320.0);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(children: [
              IconBtn('chevron-down',
                  size: 44,
                  iconSize: 20,
                  tooltip: 'Minimise',
                  onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 4),
              Text('Ambient listening', style: sans(15, color: AppColors.fg2)),
            ]),
          ),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                height: globe + 40,
                child: _pager == null
                    ? const SizedBox.shrink()
                    : PageView.builder(
                        controller: _pager,
                        itemCount: 2,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          _m.setMode(_modes[i]);
                        },
                        itemBuilder: (_, i) => _globe(i, globe),
                      ),
              ),
              if (_m.on && _m.settings?.keySet == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                  child: Text('Add an AssemblyAI key in Voice settings or nothing will be transcribed.',
                      textAlign: TextAlign.center,
                      style: sans(13, color: AppColors.fg3)),
                ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                  child: Text(err,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.danger)),
                ),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
