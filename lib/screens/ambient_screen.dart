import 'dart:async';

import 'package:flutter/material.dart';

import '../ambient/controller.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

class AmbientScreen extends StatefulWidget {
  const AmbientScreen({super.key, required this.client});
  final DaemonClient client;

  @override
  State<AmbientScreen> createState() => _AmbientScreenState();
}

class _AmbientScreenState extends State<AmbientScreen> {
  final AmbientController _ambient = AmbientController.instance;
  List<AmbientEvent> _events = [];
  AmbientStats? _stats;
  String? _error;
  String? _startError;
  bool _busy = false;
  bool _batteryOk = true;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _ambient.addListener(_changed);
    _ambient.bind().then((_) => _checkBattery());
    _load();
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
      final events = await widget.client.ambientEvents();
      final stats = await widget.client.ambientStats();
      if (!mounted) return;
      setState(() {
        _events = events;
        _stats = stats;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _startError = null;
    });
    if (_ambient.running) {
      await _ambient.stop();
    } else {
      final error = await _ambient.start(widget.client);
      if (mounted) setState(() => _startError = error);
    }
    if (mounted) setState(() => _busy = false);
    unawaited(_load());
  }

  String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _length(int ms) {
    final s = (ms / 1000).round();
    return s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final status = _ambient.status;
    final stats = _stats;
    final padding = EdgeInsets.fromLTRB(kMobile ? 16 : 24, 8, kMobile ? 16 : 24, 40);
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          NavBackRow(
              title: 'Ambient listening',
              backLabel: 'Voice',
              onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(padding: padding, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
                    border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: !status.running
                                ? AppColors.fg4
                                : status.speaking
                                    ? AppColors.accent
                                    : AppColors.ok,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(
                        !status.running
                            ? 'Not listening'
                            : status.speaking
                                ? 'Hearing speech'
                                : 'Listening',
                        style: sans(18, color: AppColors.fg1)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                      status.running
                          ? '${status.segments} segments this session, ${status.pending} waiting to upload'
                          : 'Speech is detected on this device and only the speech is sent to your server to be transcribed.',
                      style: sans(13, height: 1.5, color: AppColors.fg3)),
                ]),
              ),
              const SizedBox(height: 14),
              Btn(_ambient.running ? 'Stop listening' : 'Start listening',
                  full: true,
                  disabled: _busy,
                  variant: _ambient.running ? BtnVariant.secondary : BtnVariant.primary,
                  onTap: _toggle),
              if (_startError != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_startError!, style: sans(13, color: AppColors.danger))),
              if (status.error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(status.error!, style: sans(13, color: AppColors.danger))),
              const SizedBox(height: 22),
              if (!_batteryOk)
                SettingsGroup(
                    footer:
                        'Without this, Android may stop listening after a while to save battery.',
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
                    ]),
              SettingsGroup(header: 'Last 24 hours', children: [
                SettingsRow(
                    label: 'Segments',
                    trailing: Text('${stats?.segments ?? 0}',
                        style: mono(13, color: AppColors.fg2))),
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
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: sans(13, color: AppColors.danger))),
              SettingsGroup(
                  header: 'What it heard',
                  footer: _events.isEmpty
                      ? 'Nothing yet. Start listening and say something.'
                      : null,
                  children: [for (final e in _events) _eventRow(e)]),
            ]),
          ),
        ]),
      ),
    );
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
