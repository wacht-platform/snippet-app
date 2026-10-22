import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ambient/controller.dart';
import '../../../ambient/diagnostics.dart';
import '../../../api.dart';
import '../../../models.dart';
import '../../../platform.dart';
import '../../../settings_form.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import '../../shell_nav.dart';

String _modeLabel(AmbientSettings? s) => s == null
    ? 'Ambient'
    : !s.enabled
        ? 'Off'
        : s.mode == 'active'
            ? 'Active'
            : 'Passive';

class AmbientChip extends StatefulWidget {
  final DaemonClient client;
  final void Function(Widget panel) open;
  const AmbientChip({super.key, required this.client, required this.open});

  @override
  State<AmbientChip> createState() => _AmbientChipState();
}

class _AmbientChipState extends State<AmbientChip> {
  AmbientSettings? _settings;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.getAmbientSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();
    final on = settings.enabled;
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.open(AmbientPanel(client: widget.client)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.okBg : AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('mic', size: 12, color: on ? AppColors.ok : AppColors.fg4),
            const SizedBox(width: 6),
            Text(on ? 'Ambient ${_modeLabel(settings).toLowerCase()}' : 'Ambient off',
                style: TS.label(on ? AppColors.ok : AppColors.fg3)),
          ]),
        ),
      ),
    );
  }
}

class AmbientRow extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback onTap;
  const AmbientRow({super.key, required this.client, required this.onTap});

  @override
  State<AmbientRow> createState() => _AmbientRowState();
}

class _AmbientRowState extends State<AmbientRow> {
  AmbientSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AmbientRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.baseUrl != widget.client.baseUrl) _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.getAmbientSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: 'Ambient listening',
      leading: AppIcon('mic', size: 19, color: AppColors.fg3),
      onTap: widget.onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_settings == null ? '' : _modeLabel(_settings),
            style: sans(13, color: AppColors.fg3)),
        const SizedBox(width: S.s6),
        AppIcon('chevron-right', size: 15, color: AppColors.fg4),
      ]),
    );
  }
}

class AmbientPanel extends StatefulWidget {
  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;
  const AmbientPanel(
      {super.key, required this.client, this.embedded = false, this.onBack});

  @override
  State<AmbientPanel> createState() => _AmbientPanelState();
}

class _AmbientPanelState extends State<AmbientPanel> {
  final AmbientController _ambient = AmbientController.instance;
  AmbientSettings _settings = const AmbientSettings();
  bool _loaded = false;
  List<AmbientEvent> _events = [];
  AmbientStats? _stats;
  String? _error;
  bool _busy = false;
  bool _batteryOk = true;
  String _diagnostics = '';
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _ambient.addListener(_changed);
    _ambient.bind().then((_) => _checkBattery());
    _load();
    AmbientDiagnostics.read().then((t) {
      if (mounted) setState(() => _diagnostics = t);
    });
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _ambient.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _checkBattery() async {
    final ok = await _ambient.ignoringBattery;
    if (mounted) setState(() => _batteryOk = ok);
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.getAmbientSettings();
      final events = settings.enabled ? await widget.client.ambientEvents(limit: 20) : _events;
      final stats = settings.enabled ? await widget.client.ambientStats() : _stats;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _events = events;
        _stats = stats;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final (saved, error) = await _ambient.setEnabled(widget.client, on);
    if (mounted) {
      setState(() {
        if (saved != null) _settings = saved;
        _error = error;
        _busy = false;
      });
    }
    unawaited(_load());
  }

  Future<void> _startHere() async {
    setState(() => _busy = true);
    final error = await _ambient.start(widget.client);
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _setMode(String mode) async {
    if (_settings.mode == mode) return;
    final before = _settings;
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

  String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _length(int ms) {
    final s = (ms / 1000).round();
    return s >= 3600
        ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m'
        : s >= 60
            ? '${s ~/ 60}m ${s % 60}s'
            : '${s}s';
  }

  Widget _modeRow(String mode, String title, String detail) {
    final selected = _settings.mode == mode;
    return SettingsRow(
      label: title,
      sub: detail,
      onTap: () => _setMode(mode),
      trailing: selected
          ? AppIcon('check', size: 16, color: AppColors.accent)
          : const SizedBox(width: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _ambient.status;
    final settings = _settings;
    final stats = _stats;
    final listeningHere = status.running;
    final children = <Widget>[
      SettingsGroup(
        footer: settings.enabled
            ? (listeningHere
                ? (status.speaking ? 'Hearing speech.' : 'Listening on this device.')
                : 'On, but this device is not listening.')
            : 'Listens through the microphone, detects speech on the device and sends only the speech to your server to be transcribed.',
        children: [
          SettingsRow(
            label: 'Ambient listening',
            trailing: SettingsSwitch(
                value: settings.enabled, onChanged: _busy || !_loaded ? null : _toggle),
          ),
          if (settings.enabled && !listeningHere)
            SettingsRow(
              label: 'Start listening on this device',
              chevron: true,
              onTap: _busy ? null : _startHere,
            ),
        ],
      ),
      if (settings.enabled && !settings.keySet)
        SettingsGroup(
          footer: 'Add an AssemblyAI key in Settings, Voice, or nothing will be transcribed.',
          children: [
            SettingsRow(label: 'No transcription key', danger: true),
          ],
        ),
      SettingsGroup(
        header: 'Mode',
        footer: 'Applies to every device sending to this server.',
        children: [
          _modeRow('passive', 'Passive',
              'Listens and keeps a searchable record. Mission Control stays quiet.'),
          _modeRow('active', 'Active',
              'Mission Control can act on what it hears and speak up when it matters. Not connected yet; it behaves like Passive for now.'),
        ],
      ),
      if (!_batteryOk && settings.enabled)
        SettingsGroup(
          footer: 'Without this, Android may stop listening after a while to save battery.',
          children: [
            SettingsRow(
              label: 'Allow background activity',
              sub: 'Exempt Snippet from battery optimisation',
              chevron: true,
              onTap: () async {
                await _ambient.requestBatteryExemption();
                await _checkBattery();
              },
            ),
          ],
        ),
      if (_error != null || status.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
          child: Text(_error ?? status.error!, style: sans(13, color: AppColors.danger)),
        ),
      if (settings.enabled) ...[
        SettingsGroup(header: 'Today', children: [
          if (listeningHere)
            SettingsRow(
                label: 'This session',
                trailing: Text('${status.segments} captured, ${status.pending} to upload',
                    style: mono(12, color: AppColors.fg2))),
          SettingsRow(
              label: 'Segments, last 24 hours',
              trailing: Text('${stats?.segments ?? 0}', style: mono(13, color: AppColors.fg2))),
          SettingsRow(
              label: 'Speech captured',
              trailing: Text(_length((stats?.audioSeconds ?? 0) * 1000),
                  style: mono(13, color: AppColors.fg2))),
          if ((stats?.byStatus['failed'] ?? 0) > 0)
            SettingsRow(
                label: 'Failed to transcribe',
                trailing: Text('${stats!.byStatus['failed']}',
                    style: mono(13, color: AppColors.danger))),
        ]),
        if (settings.devices.isNotEmpty)
          SettingsGroup(header: 'Devices', footer: 'Heard from in the last 10 minutes.', children: [
            for (final d in settings.devices)
              SettingsRow(
                  label: d.device.isEmpty ? 'Unnamed device' : d.device,
                  trailing: Text(_clock(d.lastSeen), style: mono(13, color: AppColors.fg2))),
          ]),
        SettingsGroup(
          header: 'What it heard',
          footer: _events.isEmpty ? 'Nothing yet.' : null,
          children: [for (final e in _events) _eventRow(e)],
        ),
      ],
      if (_diagnostics.isNotEmpty)
        SettingsGroup(
          header: 'Diagnostics',
          footer: 'Start-up and crash notes from this device.',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(_diagnostics, style: mono(11, color: AppColors.fg3)),
            ),
            SettingsRow(
              label: 'Copy',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _diagnostics));
                if (!context.mounted) return;
                toast(context, 'Copied');
              },
            ),
            SettingsRow(
              label: 'Clear',
              onTap: () async {
                await AmbientDiagnostics.clear();
                if (mounted) setState(() => _diagnostics = '');
              },
            ),
          ],
        ),
    ];
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Ambient listening', onBack: widget.onBack!),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(kMobile ? 16 : 20, 8, kMobile ? 16 : 20, 40),
              children: children,
            ),
          ),
        ],
      );
    }
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: children);
  }

  Widget _eventRow(AmbientEvent e) {
    final pending = e.status == 'pending';
    final failed = e.status == 'failed';
    final empty = e.status == 'empty';
    final body = pending
        ? 'Transcribing'
        : failed
            ? (e.error ?? 'Failed')
            : empty
                ? 'No speech recognised'
                : e.text;
    return SettingsRow(
      label: body,
      labelWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(body,
            style: sans(kMobile ? 15 : 13,
                height: 1.4,
                color: failed
                    ? AppColors.danger
                    : (pending || empty)
                        ? AppColors.fg4
                        : AppColors.fg1)),
        const SizedBox(height: 3),
        Text('${_clock(e.startedAt)}  ·  ${_length(e.durationMs)}  ·  ${e.device}',
            style: sans(12, color: AppColors.fg4)),
      ]),
    );
  }
}
