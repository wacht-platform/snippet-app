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
      _pager = PageController(initialPage: i, viewportFraction: 0.62)
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

  String get _line {
    if (_m.settings == null) return '';
    if (!_m.on) return 'Off';
    if (!_m.listening) return 'Starting';
    if (_m.status.speaking) return 'Hearing you';
    return 'Listening';
  }

  Widget _globe(int i, double size) {
    final mode = _modes[i];
    final selected = _m.settings?.mode == mode;
    final dist = (_page - i).abs().clamp(0.0, 1.0);
    final color = selected ? _stateColor(_m.settings, _m.status) : _modeColor(mode);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected ? null : () => _pager?.animateToPage(i,
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
              const SizedBox(height: 2),
              Text(mode == 'active' ? 'Can speak up' : 'Listens quietly',
                  style: sans(12.5, color: AppColors.fg4)),
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
    final globe = math.min(width * 0.5, 230.0);
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
                height: globe + 70,
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
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(_line,
                    key: ValueKey(_line),
                    style: sans(22, weight: W.strong, color: AppColors.fg1)),
              ),
              const SizedBox(height: 6),
              Text(_m.on ? 'Hold the globe to stop' : 'Hold the globe to start',
                  style: sans(13, color: AppColors.fg4)),
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
