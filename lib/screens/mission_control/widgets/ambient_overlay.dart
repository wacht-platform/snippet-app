import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ambient/capture.dart';
import '../../../ambient/controller.dart';
import '../../../api.dart';
import '../../../models.dart';
import '../../../settings_form.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import 'ambient_panel.dart';

class AmbientOverlay extends StatefulWidget {
  const AmbientOverlay({super.key, required this.client, required this.openPanel});
  final DaemonClient client;
  final void Function(Widget panel) openPanel;

  @override
  State<AmbientOverlay> createState() => _AmbientOverlayState();
}

class _AmbientOverlayState extends State<AmbientOverlay>
    with SingleTickerProviderStateMixin {
  final AmbientController _ambient = AmbientController.instance;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  AmbientSettings? _settings;
  AmbientEvent? _latest;
  bool _open = false;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ambient.addListener(_changed);
    _ambient.bind();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ambient.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.getAmbientSettings();
      AmbientEvent? latest;
      if (settings.enabled) {
        final events = await widget.client.ambientEvents(limit: 3);
        latest = events.where((e) => e.status == 'done').firstOrNull;
      }
      if (mounted) {
        setState(() {
          _settings = settings;
          _latest = latest;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final (saved, error) = await _ambient.setEnabled(widget.client, on);
    if (!mounted) return;
    setState(() {
      if (saved != null) _settings = saved;
      _error = error;
      _busy = false;
    });
    unawaited(_load());
  }

  Future<void> _mode(String mode) async {
    final before = _settings;
    if (before == null || before.mode == mode) return;
    setState(() => _settings = AmbientSettings(
        enabled: before.enabled, mode: mode, keySet: before.keySet, devices: before.devices));
    try {
      final saved = await widget.client.setAmbientSettings(mode: mode);
      if (mounted) setState(() => _settings = saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _settings = before;
          _error = '$e';
        });
      }
    }
  }

  void _syncPulse(bool listening) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (listening && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();
    final status = _ambient.status;
    final listening = settings.enabled && status.running;
    _syncPulse(listening);
    final active = settings.mode == 'active';
    final tint = !settings.enabled
        ? AppColors.fg4
        : active
            ? AppColors.accent
            : AppColors.ok;
    return Stack(clipBehavior: Clip.none, children: [
      if (_open)
        Positioned.fill(
          left: -2000,
          right: -2000,
          top: -2000,
          bottom: -2000,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = false),
              child: const SizedBox.expand()),
        ),
      Align(
        alignment: Alignment.topRight,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          child: _open
              ? _card(settings, status, listening, tint, active)
              : _orb(settings, status, listening, tint, active),
        ),
      ),
    ]);
  }

  Widget _orb(AmbientSettings settings, AmbientStatus status, bool listening,
      Color tint, bool active) {
    final hasError = status.error != null || _error != null;
    return GestureDetector(
      key: const ValueKey('orb'),
      onTap: () => setState(() => _open = true),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => CustomPaint(
            painter: _OrbPainter(
              progress: _pulse.value,
              level: status.speaking ? math.max(0.3, status.probability) : 0,
              tint: tint,
              fill: settings.enabled ? AppColors.okBg : AppColors.surface2,
              line: AppColors.line,
              listening: listening,
              active: active && settings.enabled,
            ),
            child: Center(
              child: Stack(clipBehavior: Clip.none, children: [
                AppIcon('mic', size: 17, color: tint),
                if (hasError)
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: AppColors.danger, shape: BoxShape.circle)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(AmbientSettings settings, AmbientStatus status, bool listening,
      Color tint, bool active) {
    final line = !settings.enabled
        ? 'Off'
        : listening
            ? (status.speaking ? 'Hearing speech' : 'Listening')
            : 'On, not listening here';
    final latest = _latest;
    return Container(
      key: const ValueKey('card'),
      width: 292,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: settings.enabled ? AppColors.okBg : AppColors.surface3,
                shape: BoxShape.circle),
            child: Center(child: AppIcon('mic', size: 15, color: tint)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ambient listening', style: sans(14, color: AppColors.fg1)),
              Text(line, style: sans(12, color: AppColors.fg3)),
            ]),
          ),
          SettingsSwitch(
              value: settings.enabled, onChanged: _busy ? null : _toggle),
        ]),
        const SizedBox(height: 12),
        _segments(settings),
        if (latest != null && settings.enabled) ...[
          const SizedBox(height: 12),
          Text('“${latest.text}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12.5, height: 1.4, color: AppColors.fg2)),
        ],
        if (_error != null || status.error != null) ...[
          const SizedBox(height: 8),
          Text(_error ?? status.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.danger)),
        ],
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _open = false);
            widget.openPanel(AmbientPanel(client: widget.client));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text('Details', style: sans(12.5, color: AppColors.accent)),
              const SizedBox(width: 4),
              AppIcon('chevron-right', size: 13, color: AppColors.accent),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _segments(AmbientSettings settings) {
    Widget seg(String mode, String label) {
      final selected = settings.mode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _mode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.accentBg : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: sans(13,
                    weight: selected ? W.label : W.body,
                    color: selected ? AppColors.accent : AppColors.fg3)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: AppColors.surface3, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [seg('passive', 'Passive'), seg('active', 'Active')]),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.progress,
    required this.level,
    required this.tint,
    required this.fill,
    required this.line,
    required this.listening,
    required this.active,
  });

  final double progress;
  final double level;
  final Color tint;
  final Color fill;
  final Color line;
  final bool listening;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const base = 20.0;
    if (listening) {
      for (var i = 0; i < 2; i++) {
        final t = (progress + i * 0.5) % 1.0;
        final radius = base + t * (5 + 7 * level);
        canvas.drawCircle(
            c,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = tint.withValues(alpha: (1 - t) * (0.45 + 0.4 * level)));
      }
    }
    canvas.drawCircle(c, base, Paint()..color = fill);
    canvas.drawCircle(
        c,
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = listening ? tint.withValues(alpha: 0.7) : line);
    if (active) {
      canvas.drawCircle(c + const Offset(14, -14), 3.5, Paint()..color = tint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
