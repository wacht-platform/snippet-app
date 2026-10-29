import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../voiceprint_enrol.dart';
import '../widgets.dart';
import 'shell_nav.dart';

String _lengthLabel(int seconds) =>
    seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  VoiceSettings? _voice;
  Object? _error;
  bool _busy = false;
  EnrolPhase _phase = EnrolPhase.idle;
  String? _enrolError;
  bool _manageOpen = false;
  AudioRecorder? _sampleRecorder;
  StreamSubscription<Uint8List>? _sampleSub;
  Timer? _tick;
  BytesBuilder _chunks = BytesBuilder(copy: false);
  double _rawLevel = 0;
  double _smooth = 0;
  List<double> _levels = List.filled(12, 0.0);
  final ValueNotifier<EnrolLive> _live =
      ValueNotifier(EnrolLive(Duration.zero, List.filled(12, 0.0)));

  @override
  void dispose() {
    _tick?.cancel();
    _sampleSub?.cancel();
    _sampleRecorder?.dispose();
    _live.dispose();
    super.dispose();
  }

  void _resetLive() => _live.value = const EnrolLive(
      Duration.zero, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  Future<void> _teardownRecorder() async {
    _tick?.cancel();
    _tick = null;
    final sub = _sampleSub;
    final rec = _sampleRecorder;
    _sampleSub = null;
    _sampleRecorder = null;
    await sub?.cancel();
    try {
      await rec?.stop();
    } catch (_) {}
    await rec?.dispose();
  }

  Future<void> _startSample() async {
    if (_busy || _phase != EnrolPhase.idle) return;
    final rec = AudioRecorder();
    _sampleRecorder = rec;
    setState(() => _enrolError = null);
    try {
      if (!await rec.hasPermission()) {
        await _teardownRecorder();
        if (mounted) {
          setState(() => _enrolError =
              'Microphone access is off. Allow it in system settings, then retry.');
        }
        return;
      }
      _chunks = BytesBuilder(copy: false);
      _rawLevel = 0;
      _smooth = 0;
      _levels = List.filled(12, 0.0);
      _resetLive();
      final stream = await rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _sampleSub = stream.listen((data) {
        _chunks.add(data);
        _rawLevel = pcmLevel(data);
      });
      final clock = Stopwatch()..start();
      _tick = Timer.periodic(const Duration(milliseconds: 60), (_) {
        _smooth = _rawLevel > _smooth
            ? _smooth + (_rawLevel - _smooth) * 0.6
            : _smooth * 0.8;
        _levels = [..._levels.skip(1), _smooth];
        _live.value = EnrolLive(clock.elapsed, _levels);
        if (clock.elapsed >= kEnrolMax) _finishSample();
      });
      if (mounted) setState(() => _phase = EnrolPhase.recording);
    } catch (e) {
      await _teardownRecorder();
      if (mounted) setState(() => _enrolError = "Couldn't start recording: $e");
    }
  }

  Future<void> _cancelSample() async {
    await _teardownRecorder();
    if (mounted) setState(() => _phase = EnrolPhase.idle);
  }

  Future<void> _finishSample() async {
    if (_phase != EnrolPhase.recording) return;
    _phase = EnrolPhase.saving;
    await _teardownRecorder();
    if (!mounted) return;
    setState(() {});
    final audio = _chunks.takeBytes();
    if (voicedDuration(audio) < kEnrolMinVoiced) {
      setState(() {
        _phase = EnrolPhase.idle;
        _enrolError = kEnrolTooQuiet;
      });
      return;
    }
    await _enroll(() => widget.client.enrollVoiceprint(
          audioBytes: audio,
          label: 'Sample ${(_ambient?.voiceprints.length ?? 0) + 1}',
        ));
  }

  Future<void> _enroll(Future<AmbientSettings> Function() call) async {
    setState(() {
      _phase = EnrolPhase.saving;
      _enrolError = null;
    });
    try {
      final next = await call();
      if (!mounted) return;
      setState(() => _ambient = next);
    } catch (e) {
      final msg = '$e';
      if (mounted) {
        setState(() => _enrolError = msg.contains('Not enough')
            ? kEnrolTooQuiet
            : "Couldn't save that sample: ${msg.replaceFirst('Exception: ', '')}");
      }
    } finally {
      if (mounted) setState(() => _phase = EnrolPhase.idle);
    }
  }

  Future<void> _enrollFromRecent() async {
    if (_busy || _phase != EnrolPhase.idle) return;
    await _enroll(() => widget.client.enrollVoiceprint(
          fromRecent: true,
          label: 'Sample ${(_ambient?.voiceprints.length ?? 0) + 1}',
        ));
  }

  Future<void> _deleteVoiceprint(String? id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.deleteVoiceprint(id: id);
      if (!mounted) return;
      setState(() => _ambient = next);
      toast(context, id == null ? 'Cleared voice samples' : 'Removed sample');
    } catch (e) {
      if (mounted) toast(context, "Couldn't remove sample: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadAmbient();
  }

  Future<void> _load() async {
    try {
      final c = await widget.client.getConfig(force: true);
      if (mounted) {
        setState(() {
          _voice = c.voice;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save({
    bool? enabled,
    int? maxSeconds,
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.setVoice(
        enabled: enabled,
        maxSeconds: maxSeconds,
      );
      if (!mounted) return;
      setState(() => _voice = next);
      if (done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, "Couldn't save: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AmbientSettings? _ambient;

  Future<void> _loadAmbient() async {
    try {
      final a = await widget.client.getAmbientSettings();
      if (mounted) setState(() => _ambient = a);
    } catch (_) {}
  }

  Future<void> _saveAmbient({
    int? timeout,
    List<String>? phrases,
    String? assemblyaiKey,
    String? deepgramKey,
    String? typesafeKey,
    String? deepgramHost,
    String? ttsVoice,
    int? ttsSpeed,
    String? stt,
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.setAmbientSettings(
          conversationTimeoutSecs: timeout,
          wakePhrases: phrases,
          assemblyaiKey: assemblyaiKey,
          deepgramKey: deepgramKey,
          typesafeKey: typesafeKey,
          deepgramHost: deepgramHost,
          ttsVoice: ttsVoice,
          ttsSpeed: ttsSpeed,
          stt: stt);
      if (!mounted) return;
      setState(() => _ambient = next);
      if (done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, "Couldn't save: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPhrases(AmbientSettings a) async {
    final text = await promptText(context,
        title: 'Wake phrases',
        hint: 'One per line, e.g. snippet',
        initial: a.wakePhrases.join('\n'),
        saveLabel: 'Save',
        maxLines: 6);
    if (text == null || !mounted) return;
    await _saveAmbient(phrases: [
      for (final t in text.split(RegExp(r'[\n,]')))
        if (t.trim().isNotEmpty) t.trim()
    ]);
  }

  Future<void> _editKey(String service, bool keySet, String hint,
      Future<void> Function(String key) save) async {
    final key = await promptText(context,
        title: keySet ? 'Replace $service key' : '$service API key',
        hint: hint,
        saveLabel: 'Save key');
    if (key == null || key.trim().isEmpty || !mounted) return;
    await save(key.trim());
  }

  Widget _keyRow(String label, bool keySet, VoidCallback onTap) => kMobile
      ? SettingsRow(
          label: label,
          onTap: _busy ? null : onTap,
          trailing: Text(keySet ? 'Set' : 'Not set',
              style:
                  sans(15, color: keySet ? AppColors.fg3 : AppColors.danger)),
          chevron: true,
        )
      : SettingsRow(
          label: label,
          trailing: _keyControl(keySet, onTap),
        );

  String _voiceLabel(TtsVoice v) =>
      '${v.name} · ${v.accent} ${v.gender.toLowerCase()}';

  String _speedLabel(int pct) =>
      '${(pct / 100).toStringAsFixed(pct % 10 == 0 ? 1 : 2)}×';

  List<Widget> _ambientGroups(AmbientSettings a) {
    final speeds = <int>{90, 100, 110, 115, 125, 135, 150, a.ttsSpeed}.toList()
      ..sort();
    final timeouts =
        <int>{30, 60, 90, 180, 300, a.conversationTimeoutSecs}.toList()..sort();
    final hosts = a.deepgramHosts.isEmpty
        ? [(a.deepgramHost, a.deepgramHost)]
        : a.deepgramHosts;
    final hostLabel = hosts
        .firstWhere((h) => h.$1 == a.deepgramHost,
            orElse: () => (a.deepgramHost, a.deepgramHost))
        .$2;
    final voice = a.ttsVoices.where((v) => v.model == a.ttsVoice).firstOrNull;
    return [
      SettingsGroup(
        header: 'Speech services',
        footer: 'Keys stay on the server.',
        children: [
          SettingsRow(
            label: 'Speech recognition',
            trailing: SettingsPopup<String>(
              label: a.stt == 'flux' ? 'Deepgram Flux' : 'AssemblyAI',
              selected: a.stt,
              items: const [
                ('assemblyai', 'AssemblyAI'),
                ('flux', 'Deepgram Flux')
              ],
              onSelected: (v) =>
                  _saveAmbient(stt: v, done: 'Speech recognition saved'),
            ),
          ),
          _keyRow(
              'AssemblyAI key',
              a.assemblyaiKeySet,
              () => _editKey(
                  'AssemblyAI',
                  a.assemblyaiKeySet,
                  'Paste the key from assemblyai.com/dashboard',
                  (k) => _saveAmbient(
                      assemblyaiKey: k, done: 'AssemblyAI key saved'))),
          _keyRow(
              'Deepgram key',
              a.deepgramKeySet,
              () => _editKey(
                  'Deepgram',
                  a.deepgramKeySet,
                  'Paste the key from console.deepgram.com',
                  (k) => _saveAmbient(
                      deepgramKey: k, done: 'Deepgram key saved'))),
          _keyRow(
              'Typesafe key',
              a.watcherKeySet,
              () => _editKey(
                  'Typesafe',
                  a.watcherKeySet,
                  'Paste your Typesafe API key',
                  (k) => _saveAmbient(
                      typesafeKey: k, done: 'Typesafe key saved'))),
          SettingsRow(
            label: 'Deepgram region',
            trailing: SettingsPopup<String>(
              label: hostLabel,
              selected: a.deepgramHost,
              items: [for (final h in hosts) (h.$1, h.$2)],
              onSelected: (h) =>
                  _saveAmbient(deepgramHost: h, done: 'Region saved'),
            ),
          ),
          if (a.ttsVoices.isNotEmpty)
            SettingsRow(
              label: 'Voice',
              trailing: SettingsPopup<String>(
                label: voice?.name ?? a.ttsVoice,
                sheetHeightFactor: 0.5,
                selected: a.ttsVoice,
                items: [for (final v in a.ttsVoices) (v.model, _voiceLabel(v))],
                onSelected: (m) =>
                    _saveAmbient(ttsVoice: m, done: 'Voice saved'),
              ),
            ),
          SettingsRow(
            label: 'Speech speed',
            trailing: SettingsPopup<int>(
              label: _speedLabel(a.ttsSpeed),
              selected: a.ttsSpeed,
              items: [for (final s in speeds) (s, _speedLabel(s))],
              onSelected: (s) =>
                  _saveAmbient(ttsSpeed: s, done: 'Speech speed saved'),
            ),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Conversation',
        footer: 'A wake phrase starts a conversation, even in Passive mode.',
        children: [
          SettingsRow(
            label: 'Wake phrases',
            sub: a.wakePhrases.isEmpty ? 'None' : a.wakePhrases.join(', '),
            chevron: true,
            onTap: () => _editPhrases(a),
          ),
          SettingsRow(
            label: 'Ends after silence',
            trailing: SettingsPopup<int>(
              label: _lengthLabel(a.conversationTimeoutSecs),
              selected: a.conversationTimeoutSecs,
              items: [for (final s in timeouts) (s, _lengthLabel(s))],
              onSelected: (s) => _saveAmbient(timeout: s),
            ),
          ),
        ],
      ),
      VoiceprintGroup(
        ambient: a,
        phase: _phase,
        live: _live,
        manageOpen: _manageOpen,
        busy: _busy,
        error: _enrolError,
        onRecord: _startSample,
        onStop: _finishSample,
        onCancel: _cancelSample,
        onRecent: _enrollFromRecent,
        onToggleManage: () => setState(() => _manageOpen = !_manageOpen),
        onRemove: _deleteVoiceprint,
        onClear: () => _deleteVoiceprint(null),
      ),
    ];
  }

  List<Widget> _groups(VoiceSettings v) {
    final lengths = <int>{60, 120, 180, 300, 600, v.maxSeconds}
        .where((s) => s >= v.minSeconds && s <= v.maxSecondsLimit)
        .toList()
      ..sort();
    return [
      SettingsGroup(
        children: [
          SettingsRow(
            label: 'Voice notes',
            trailing: SettingsSwitch(
              value: v.enabled,
              onChanged: _busy ? null : (on) => _save(enabled: on),
            ),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Transcription',
        children: [
          SettingsRow(
            label: 'Longest note',
            trailing: SettingsPopup<int>(
              label: _lengthLabel(v.maxSeconds),
              selected: v.maxSeconds,
              items: [for (final s in lengths) (s, _lengthLabel(s))],
              onSelected: (s) => _save(maxSeconds: s),
            ),
          ),
        ],
      ),
      if (_ambient != null) ..._ambientGroups(_ambient!),
    ];
  }

  Widget _keyControl(bool keySet, VoidCallback onTap) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(keySet ? 'Set' : 'Not set',
            style: sans(13, color: keySet ? AppColors.fg3 : AppColors.danger)),
        const SizedBox(width: S.s12),
        Btn(keySet ? 'Replace' : 'Add key',
            small: true,
            variant: BtnVariant.secondary,
            onTap: _busy ? null : onTap),
      ]);

  @override
  Widget build(BuildContext context) {
    final v = _voice;
    if (!kMobile && widget.embedded && widget.onBack == null) {
      if (v == null) {
        return SettingsGroup(children: [
          _error == null
              ? const SettingsRow(label: 'Loading voice settings…')
              : SettingsRow(
                  label: "Couldn't load voice settings",
                  sub: '$_error',
                  danger: true,
                  trailing: Btn('Retry',
                      small: true, variant: BtnVariant.secondary, onTap: _load),
                ),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _groups(v),
      );
    }
    final Widget body;
    if (v == null) {
      body = _error == null
          ? const ListSkeleton()
          : EmptyState(
              icon: 'alert-triangle',
              title: "Couldn't load voice settings",
              body: '$_error',
              action: Btn('Retry', small: true, onTap: _load),
            );
    } else {
      body = ListView(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(16, 8, 16, 40)
            : const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s40),
        children: _groups(v),
      );
    }
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Voice', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return body;
  }
}
