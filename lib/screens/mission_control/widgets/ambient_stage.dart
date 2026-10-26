import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ambient/capture.dart';
import '../../../ambient/controller.dart';
import '../../../ambient/voice.dart';
import '../../../api.dart';
import '../../../models.dart';
import '../../../platform.dart';
import '../../../settings_form.dart';
import '../../../theme.dart';
import '../../../widgets.dart';

final ValueNotifier<AmbientStateEvent?> _emptyAmbientState = ValueNotifier(null);

Color _modeColor(String mode) =>
    mode == 'active' ? AppColors.accent : AppColors.ok;

Color _stateColor(AmbientSettings? s, AmbientStatus st) {
  if (s != null && s.enabled && st.error != null) return AppColors.danger;
  return _modeColor(s?.shownMode ?? 'passive');
}

class _AmbientModel extends ChangeNotifier {
  _AmbientModel(this.client) {
    ambient.addListener(notifyListeners);
    ambient.bind();
    ambient.deviceId.then((v) {
      selfId = v;
      notifyListeners();
    });
    load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  final DaemonClient client;
  final AmbientController ambient = AmbientController.instance;
  AmbientSettings? settings;
  String selfId = '';
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

  bool get elsewhere {
    final id = settings?.listeningId;
    return id != null && selfId.isNotEmpty && id != selfId;
  }

  Future<void> press() async {
    if (on && listening) return toggle(false);
    if (on) {
      if (busy) return;
      busy = true;
      notifyListeners();
      error = await ambient.start(client);
      busy = false;
      notifyListeners();
      load();
      return;
    }
    return toggle(true);
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
    settings = before.withMode(mode);
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
          _m.press();
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
  Rect? anchor;
  if (!kMobile) {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      anchor = ro.localToGlobal(Offset.zero) & ro.size;
    }
  }
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: Motion.open,
    reverseTransitionDuration: Motion.close,
    pageBuilder: (_, animation, __) =>
        AmbientStage(client: client, animation: animation, anchor: anchor),
  ));
}

class AmbientStage extends StatefulWidget {
  const AmbientStage({
    super.key,
    required this.client,
    required this.animation,
    this.anchor,
  });
  final DaemonClient client;
  final Animation<double> animation;
  final Rect? anchor;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage> {
  late final _AmbientModel _m = _AmbientModel(widget.client)
    ..addListener(_changed);
  late final CurvedAnimation _a = CurvedAnimation(
      parent: widget.animation, curve: Motion.enter, reverseCurve: Motion.exit);
  List<AmbientEvent> _recent = const [];
  Timer? _recentTimer;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _recentTimer =
        Timer.periodic(const Duration(seconds: 8), (_) => _loadRecent());
  }

  Future<void> _loadRecent() async {
    try {
      final events = await widget.client.ambientEvents(limit: 16);
      if (!mounted) return;
      setState(() => _recent = events
          .where((e) =>
              e.status == 'done' &&
              e.kept &&
              e.text.trim().isNotEmpty &&
              !const {'media', 'noise', 'background', 'echo'}
                  .contains(e.verdict))
          .take(3)
          .toList());
    } catch (_) {}
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recentTimer?.cancel();
    _m.removeListener(_changed);
    _m.dispose();
    _a.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  String get _mode => _m.settings?.shownMode ?? 'passive';
  bool get _live => _m.on && _m.listening;
  bool get _canToggle => !kIsWeb && _m.settings != null && !_m.busy;

  void _toggle() {
    if (!_canToggle) return;
    HapticFeedback.mediumImpact();
    _m.press();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    _m.setMode(mode);
  }

  String _caption(AmbientStateEvent? event) {
    if (kIsWeb) return 'Runs in the phone and desktop apps';
    if (_m.elsewhere) {
      return 'Listening on ${_m.settings?.listeningDevice ?? 'another device'}';
    }
    if (_m.status.displaced) return 'Another device took over';
    if (_m.busy) return _live ? 'Stopping' : 'Starting';
    if (!_live) return 'Not listening';
    if (event != null) {
      if (event.sub == 'speaking') return 'Speaking';
      if (event.sub == 'thinking') return 'Thinking';
      if (event.mode == 'active') return 'In conversation';
      if (event.mode == 'pinned') return 'Ready to talk';
    }
    if (_m.status.assistantSpeaking) return 'Speaking';
    if (_m.settings?.conversationOpen ?? false) return 'In conversation';
    if (_m.status.speaking) return 'Hearing you';
    return _mode == 'active' ? 'Listening, ready to speak up' : 'Listening quietly';
  }

  (String, Color) _status() {
    if (kIsWeb) return ('Unavailable', AppColors.fg4);
    if (_m.on && (_m.error ?? _m.status.error) != null) {
      return ('Error', AppColors.danger);
    }
    if (_m.elsewhere) return ('Elsewhere', AppColors.fg3);
    if (_live) return ('Live', _modeColor(_mode));
    return ('Off', AppColors.fg4);
  }

  Widget _pill() {
    final (label, color) = _status();
    return AnimatedContainer(
      duration: Motion.fast,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: sans(12, weight: W.label, color: color)),
      ]),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Widget _surfaceCard({required List<Widget> children, EdgeInsets? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );

  Widget _recentList() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text('Recently heard',
                style: sans(12, weight: W.label, color: AppColors.fg3)),
          ),
          _surfaceCard(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < _recent.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: AppColors.line),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(_recent[i].text.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                sans(12.5, height: 1.4, color: AppColors.fg2)),
                      ),
                      const SizedBox(width: 10),
                      Text(_ago(_recent[i].startedAt),
                          style: mono(11, color: AppColors.fg4)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      );

  Widget _panel(bool wide, double orb) {
    final err = _m.error ?? _m.status.error;
    final color = _stateColor(_m.settings, _m.status);
    final popover = wide && widget.anchor != null;
    return Container(
      width: popover ? 336 : (wide ? 360 : double.infinity),
      padding: EdgeInsets.fromLTRB(16, wide ? 16 : 10, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(wide ? R.lg : 20),
        border: Border.all(color: AppColors.border),
        boxShadow: overlayShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wide)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
          _surfaceCard(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: _live ? 'Stop listening' : 'Start listening',
                    child: GestureDetector(
                      onTap: _canToggle ? _toggle : null,
                      onLongPress: _canToggle ? _toggle : null,
                      child: _Orb(
                        size: orb,
                        color: color,
                        alive: _live,
                        level: _live &&
                                (_m.status.speaking ||
                                    _m.status.assistantSpeaking)
                            ? 1
                            : 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ValueListenableBuilder<AmbientVoice?>(
                      valueListenable: AmbientController.instance.voice,
                      builder: (context, voice, _) =>
                          ValueListenableBuilder<AmbientStateEvent?>(
                        valueListenable: voice?.state ?? _emptyAmbientState,
                        builder: (context, event, _) {
                          final caption = _caption(event);
                          final why = event?.reason
                                      ?.startsWith('mission_control:') ==
                                  true
                              ? event!.reason!
                                  .substring('mission_control:'.length)
                                  .trim()
                              : null;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                Text('Ambient',
                                    style: sans(14,
                                        weight: W.strong,
                                        color: AppColors.fg1)),
                                const SizedBox(width: 8),
                                _pill(),
                              ]),
                              const SizedBox(height: 3),
                              Text(caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(12.5, color: AppColors.fg3)),
                              if (why != null && why.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(why,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sans(11.5, color: AppColors.fg4)),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_m.elsewhere)
                    Btn('Take over',
                        small: true,
                        variant: BtnVariant.secondary,
                        disabled: !_canToggle,
                        onTap: _canToggle ? _toggle : null)
                  else
                    SettingsSwitch(
                      value: _live,
                      onChanged: _canToggle ? (_) => _toggle() : null,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _surfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Mode',
                            style:
                                sans(13, weight: W.label, color: AppColors.fg1)),
                        const SizedBox(height: 2),
                        Text(
                          _mode == 'active'
                              ? 'Speaks up when it matters'
                              : 'Quiet notes in chat',
                          style: sans(12, color: AppColors.fg3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Pills<String>(
                    items: const [
                      ('passive', 'Passive'),
                      ('active', 'Active'),
                    ],
                    selected: _mode,
                    onSelect: _setMode,
                  ),
                ],
              ),
            ],
          ),
          if (err != null && !kIsWeb) ...[
            const SizedBox(height: 8),
            NoteLine(err, error: true),
          ],
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            _recentList(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final anchor = wide ? widget.anchor : null;
    final still = reduceMotion(context);
    final orb = wide ? 52.0 : 58.0;
    final panel = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: anchor != null
            ? (size.height - anchor.bottom - 24).clamp(280.0, size.height * 0.86)
            : size.height * 0.92,
      ),
      child: SingleChildScrollView(child: _panel(wide, orb)),
    );
    final Widget placed = anchor != null
        ? Builder(builder: (_) {
            const width = 336.0;
            final left =
                (anchor.center.dx - width + 24).clamp(12.0, size.width - width - 12);
            final top = (anchor.bottom + 8).clamp(12.0, size.height - 320.0);
            final alignX =
                (((anchor.center.dx - left) / width) * 2 - 1).clamp(-0.9, 0.9);
            return Stack(children: [
              Positioned(
                left: left,
                top: top,
                child: FadeTransition(
                  opacity: _a,
                  child: still
                      ? panel
                      : ScaleTransition(
                          alignment: Alignment(alignX, -1.0),
                          scale: Tween(begin: 0.94, end: 1.0).animate(_a),
                          child: panel),
                ),
              ),
            ]);
          })
        : wide
            ? Center(
                child: FadeTransition(
                  opacity: _a,
                  child: still
                      ? panel
                      : ScaleTransition(
                          scale: Tween(begin: 0.96, end: 1.0).animate(_a),
                          child: panel),
                ),
              )
            : Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _a,
              builder: (_, child) => Opacity(
                opacity: still ? _a.value : 1,
                child: Transform.translate(
                  offset: Offset(0, (still ? 0 : (1 - _a.value) * 360) + _drag),
                  child: child,
                ),
              ),
              child: GestureDetector(
                onVerticalDragUpdate: (d) =>
                    setState(() => _drag = math.max(0, _drag + d.delta.dy)),
                onVerticalDragEnd: (d) {
                  if (_drag > 90 || (d.primaryVelocity ?? 0) > 700) {
                    _close();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: panel,
                ),
              ),
            ),
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _setMode('passive'),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _setMode('active'),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: AnimatedBuilder(
                  animation: _a,
                  builder: (_, __) {
                    final v = _a.value.clamp(0.0, 1.0);
                    if (anchor != null) {
                      return ColoredBox(
                          color: Colors.black.withValues(alpha: 0.14 * v));
                    }
                    return BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14 * v, sigmaY: 14 * v),
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.4 * v)),
                    );
                  },
                ),
              ),
            ),
            placed,
          ]),
        ),
      ),
    );
  }
}
