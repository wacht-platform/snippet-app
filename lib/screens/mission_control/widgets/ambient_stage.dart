import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ambient/capture.dart';
import '../../../ambient/controller.dart';
import '../../../api.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../widgets.dart';

Color _stateColor(AmbientSettings? s, AmbientStatus st) {
  if (s == null || !s.enabled) return AppColors.fg4;
  if (st.error != null) return AppColors.danger;
  return s.mode == 'active' ? AppColors.accent : AppColors.ok;
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
  }

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
  _OrbPainter(this.t, this.level, this.color, this.alive) : super(repaint: null);
  final double t;
  final double level;
  final Color color;
  final bool alive;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (alive) {
      for (var i = 0; i < 3; i++) {
        final p = (t + i / 3) % 1.0;
        final ring = r * (0.62 + 0.38 * p + level * 0.12);
        canvas.drawCircle(
            c,
            ring,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = color.withValues(alpha: (1 - p) * 0.32));
      }
    }
    final breathe = alive ? math.sin(t * math.pi * 2) * 0.03 : 0.0;
    final core = r * (0.5 + breathe + level * 0.14);
    canvas.drawCircle(
        c,
        core * 1.5,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: alive ? 0.30 : 0.10),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: core * 1.5)));
    canvas.drawCircle(
        c,
        core,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: [
              Color.lerp(color, Colors.white, alive ? 0.35 : 0.05)!,
              color.withValues(alpha: alive ? 0.95 : 0.5),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: core)));
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
  const AmbientHeaderOrb(
      {super.key, required this.client, this.onlyWhenOn = true});
  final DaemonClient client;
  final bool onlyWhenOn;

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
    if (widget.onlyWhenOn && !_m.on) return const SizedBox.shrink();
    final color = _stateColor(_m.settings, _m.status);
    return Semantics(
      button: true,
      label: 'Ambient listening',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAmbientStage(context, widget.client),
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

  String get _line {
    if (_m.settings == null) return '';
    if (!_m.on) return 'Off';
    if (!_m.listening) return 'Starting';
    if (_m.status.speaking) return 'Hearing you';
    return 'Listening';
  }

  Widget _mode(String mode, String label, String hint) {
    final selected = _m.settings?.mode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _m.setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(label,
                style: sans(15,
                    weight: W.strong,
                    color: selected ? AppColors.accent : AppColors.fg2)),
            const SizedBox(height: 2),
            Text(hint, style: sans(12, color: AppColors.fg4)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(_m.settings, _m.status);
    final err = _m.error ?? _m.status.error;
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
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Orb(
                  size: math.min(MediaQuery.sizeOf(context).width * 0.78, 320),
                  color: color,
                  alive: _m.listening,
                  level: _m.status.speaking ? 1 : 0,
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(_line,
                      key: ValueKey(_line),
                      style: sans(22, weight: W.strong, color: AppColors.fg1)),
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  _mode('passive', 'Passive', 'Listens quietly'),
                  _mode('active', 'Active', 'Can speak up'),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _m.busy || _m.settings == null
                      ? null
                      : () => _m.toggle(!_m.on),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _m.on ? AppColors.surface3 : AppColors.accentFill,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(_m.on ? 'Stop listening' : 'Start listening',
                        style: sans(16,
                            weight: W.strong,
                            color: _m.on ? AppColors.fg1 : AppColors.accentFg)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
