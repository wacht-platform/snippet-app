import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../inline_key_row.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../voice_picker.dart';
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

  void _resetLive() => _live.value =
      const EnrolLive(Duration.zero, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

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
    _loadRecording();
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

  RecordingPolicy? _rec;

  Future<void> _loadRecording() async {
    try {
      final r = await widget.client.getRecording();
      if (mounted) setState(() => _rec = r);
    } catch (_) {}
  }

  Future<void> _recAct(Future<RecordingPolicy?> Function() call,
      {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await call();
      if (!mounted) return;
      if (next != null) setState(() => _rec = next);
      if (done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, "Couldn't save: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeRule(String id, String label) async {
    final ok = await confirmAction(context,
        title: 'Remove rule?',
        body: 'Mission Control will stop applying "$label".',
        confirmLabel: 'Remove');
    if (!ok || !mounted) return;
    await _recAct(() => widget.client.setRecording(removeRule: id),
        done: 'Rule removed');
  }

  Future<void> _removeWindow(String id, String label) async {
    final ok = await confirmAction(context,
        title: 'Remove window?',
        body: 'Mission Control will stop applying "$label".',
        confirmLabel: 'Remove');
    if (!ok || !mounted) return;
    await _recAct(() => widget.client.setRecording(removeWindow: id),
        done: 'Window removed');
  }

  Future<void> _deleteRecording(RecordingEntry e, bool redact) async {
    final ok = await confirmAction(context,
        title: redact ? 'Redact recording?' : 'Delete recording?',
        body: redact
            ? 'The transcript is kept but its text is removed.'
            : 'This recording is deleted for good.',
        confirmLabel: redact ? 'Redact' : 'Delete');
    if (!ok || !mounted) return;
    await _recAct(() async {
      await widget.client.deleteRecording(e.id, redact ? 'redact' : 'delete');
      return widget.client.getRecording();
    }, done: redact ? 'Recording redacted' : 'Recording deleted');
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _when(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[t.month - 1]} ${t.day}, ${_clock(t)}';
  }

  String _snoozeLabel(RecordingPolicy r) {
    final until = r.snoozeUntil;
    if (until == null) return 'Off';
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return 'Off';
    final mins = (left / 60000).ceil();
    if (mins < 60) return '$mins min left';
    final h = mins ~/ 60;
    return mins % 60 == 0 ? '$h h left' : '$h h ${mins % 60} min left';
  }

  int _untilTomorrowMinutes() {
    final n = DateTime.now();
    final t = DateTime(n.year, n.month, n.day + 1);
    return t.difference(n).inMinutes + 1;
  }

  String _retentionLabel(int d) => d == 0 ? 'Forever' : '$d days';

  List<Widget> _recordingGroups() {
    final r = _rec;
    if (r == null) return const [];
    final days = <int>{7, 30, 60, 90, r.retentionDays}.toList()..sort();
    final snoozing = _snoozeLabel(r) != 'Off';
    final ruleRows = <Widget>[
      for (final x in r.rules.where((x) => x.mode != 'ask'))
        SettingsRow(
          label: x.label,
          sub: x.mode == 'auto'
              ? (x.basis.isEmpty
                  ? 'Always record'
                  : 'Always record · "${x.basis}"')
              : 'Never record',
          trailing: Btn('Remove',
              small: true,
              variant: BtnVariant.ghost,
              disabled: _busy,
              onTap: () => _removeRule(x.id, x.label)),
        ),
      for (final w in r.windows)
        SettingsRow(
          label: w.label,
          sub: w.mode == 'auto'
              ? (w.basis.isEmpty
                  ? 'Record · ${_when(w.fromMs)} to ${_when(w.toMs)}'
                  : 'Record · "${w.basis}"')
              : 'Never record · ${_when(w.fromMs)} to ${_when(w.toMs)}',
          trailing: Btn('Remove',
              small: true,
              variant: BtnVariant.ghost,
              disabled: _busy,
              onTap: () => _removeWindow(w.id, w.label)),
        ),
    ];
    return [
      SettingsGroup(
        header: 'Recording',
        footer: 'Snoozing stops automatic recording for a while.',
        children: [
          SettingsRow(
            label: 'Snooze',
            trailing: SettingsPopup<int>(
              label: _snoozeLabel(r),
              selected: snoozing ? -1 : 0,
              items: const [
                (0, 'Off'),
                (60, '1 hour'),
                (240, '4 hours'),
                (-2, 'Until tomorrow'),
              ],
              onSelected: (m) => _recAct(() => widget.client.setRecording(
                  snoozeMinutes: m == -2 ? _untilTomorrowMinutes() : m)),
            ),
          ),
          SettingsRow(
            label: 'Keep recordings',
            trailing: SettingsPopup<int>(
              label: _retentionLabel(r.retentionDays),
              selected: r.retentionDays,
              items: [
                for (final d in days.where((d) => d > 0)) (d, _retentionLabel(d)),
                (0, 'Forever'),
              ],
              onSelected: (d) =>
                  _recAct(() => widget.client.setRecording(retentionDays: d)),
            ),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Rules',
        footer: ruleRows.isEmpty
            ? null
            : 'Rules are set by asking Mission Control.',
        children: ruleRows.isEmpty
            ? [
                SettingsRow(
                    label:
                        'Ask Mission Control, for example: always record my Monday standup.')
              ]
            : ruleRows,
      ),
      SettingsGroup(
        header: 'Recordings',
        children: r.recordings.isEmpty
            ? const [SettingsRow(label: 'No recordings yet')]
            : [
                for (final e in r.recordings)
                  SettingsRow(
                    label: _when(e.started),
                    sub: '${e.lines} ${e.lines == 1 ? 'line' : 'lines'}',
                    trailing: SettingsPopup<String>(
                      label: 'Manage',
                      selected: '',
                      items: const [('delete', 'Delete'), ('redact', 'Redact')],
                      onSelected: (m) => _deleteRecording(e, m == 'redact'),
                    ),
                  ),
              ],
      ),
    ];
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
    String? rimeKey,
    String? ttsProvider,
    String? rimeModel,
    String? rimeVoice,
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
          rimeKey: rimeKey,
          ttsProvider: ttsProvider,
          rimeModel: rimeModel,
          rimeVoice: rimeVoice,
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
    final flux = a.stt == 'flux';
    final rime = a.ttsProvider == 'rime';
    final usesDeepgram = flux || !rime;
    Widget key(String label, bool set, String hint,
            Future<void> Function(String) save,
            {bool optional = false}) =>
        InlineKeyRow(
            label: label,
            keySet: set,
            hint: hint,
            busy: _busy,
            optional: optional,
            onSave: save);
    final deepgramKey = key(
        'API key',
        a.deepgramKeySet,
        'Paste the key from console.deepgram.com',
        (k) => _saveAmbient(deepgramKey: k, done: 'Deepgram key saved'));
    var keyFooterShown = false;
    String? keyFooter() {
      if (keyFooterShown) return null;
      keyFooterShown = true;
      return 'Keys stay on the server. Replies need a Deepgram or Rime key.';
    }

    return [
      SettingsGroup(
        header: 'Listening',
        children: [
          SettingsRow(
            label: 'Speech recognition',
            trailing: SettingsPopup<String>(
              label: flux ? 'Deepgram Flux' : 'AssemblyAI',
              selected: a.stt,
              items: const [
                ('assemblyai', 'AssemblyAI'),
                ('flux', 'Deepgram Flux')
              ],
              onSelected: (v) =>
                  _saveAmbient(stt: v, done: 'Speech recognition saved'),
            ),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Replies',
        children: [
          SettingsRow(
            label: 'Reply voice',
            trailing: SettingsPopup<String>(
              label: rime ? 'Rime' : 'Deepgram',
              selected: a.ttsProvider,
              items: const [('deepgram', 'Deepgram'), ('rime', 'Rime')],
              onSelected: (v) => _saveAmbient(
                  ttsProvider: v,
                  done: v == 'rime'
                      ? 'Replies now use Rime'
                      : 'Replies now use Deepgram'),
            ),
          ),
          if (rime) ...[
            SettingsRow(
              label: 'Rime model',
              trailing: SettingsPopup<String>(
                label: a.rimeModel == 'coda' ? 'Coda' : 'Mist v3 (fastest)',
                selected: a.rimeModel,
                items: const [('mistv3', 'Mist v3 (fastest)'), ('coda', 'Coda')],
                onSelected: (m) => _saveAmbient(
                    rimeModel: m,
                    rimeVoice: m == 'coda' ? 'lyra' : 'cove',
                    done: 'Rime model saved'),
              ),
            ),
            SettingsRow(
              label: 'Voice',
              trailing: _VoiceButton(
                label: a.rimeVoice.isEmpty
                    ? 'Choose'
                    : a.rimeVoice[0].toUpperCase() + a.rimeVoice.substring(1),
                onTap: _busy
                    ? null
                    : () async {
                        final list = await rimeVoices(a.rimeModel);
                        if (!mounted) return;
                        if (list.isEmpty) {
                          toast(context, "Couldn't load the Rime voice list",
                              danger: true);
                          return;
                        }
                        final v = await showVoicePicker(context,
                            title: 'Rime voice',
                            voices: list,
                            selected: a.rimeVoice);
                        if (v != null && mounted) {
                          await _saveAmbient(
                              rimeVoice: v, done: 'Voice saved');
                        }
                      },
              ),
            ),
          ] else if (a.ttsVoices.isNotEmpty)
            SettingsRow(
              label: 'Voice',
              trailing: _VoiceButton(
                label: voice?.name ?? a.ttsVoice,
                onTap: _busy
                    ? null
                    : () async {
                        final v = await showVoicePicker(context,
                            title: 'Deepgram voice',
                            voices: [
                              for (final t in a.ttsVoices)
                                PickVoice(t.model, t.name,
                                    sub:
                                        '${t.accent} · ${t.gender.toLowerCase()}',
                                    group: t.gender)
                            ],
                            selected: a.ttsVoice);
                        if (v != null && mounted) {
                          await _saveAmbient(ttsVoice: v, done: 'Voice saved');
                        }
                      },
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
      if (usesDeepgram)
        SettingsGroup(
          header: 'Deepgram',
          footer: keyFooter(),
          children: [
            deepgramKey,
            SettingsRow(
              label: 'Region',
              trailing: SettingsPopup<String>(
                label: hostLabel,
                selected: a.deepgramHost,
                items: [for (final h in hosts) (h.$1, h.$2)],
                onSelected: (h) =>
                    _saveAmbient(deepgramHost: h, done: 'Region saved'),
              ),
            ),
          ],
        ),
      if (!flux)
        SettingsGroup(
          header: 'AssemblyAI',
          footer: keyFooter(),
          children: [
            key(
                'API key',
                a.assemblyaiKeySet,
                'Paste the key from assemblyai.com/dashboard',
                (k) => _saveAmbient(
                    assemblyaiKey: k, done: 'AssemblyAI key saved')),
          ],
        ),
      if (rime)
        SettingsGroup(
          header: 'Rime',
          footer: keyFooter(),
          children: [
            key('API key', a.rimeKeySet, 'Paste the key from rime.ai',
                (k) => _saveAmbient(rimeKey: k, done: 'Rime key saved')),
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
      ..._recordingGroups(),
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
      SettingsGroup(
        header: 'Classifier',
        children: [
          key('Typesafe key', a.watcherKeySet, 'Paste your Typesafe API key',
              (k) => _saveAmbient(typesafeKey: k, done: 'Typesafe key saved'),
              optional: true),
        ],
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
        header: 'Voice notes',
        children: [
          SettingsRow(
            label: 'Voice notes',
            trailing: SettingsSwitch(
              value: v.enabled,
              onChanged: _busy ? null : (on) => _save(enabled: on),
            ),
          ),
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

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: kMobile ? Colors.transparent : AppColors.surface2,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: sans(kMobile ? 15 : 13, color: AppColors.fg2)),
              const SizedBox(width: 6),
              AppIcon('chevron-right', size: 12, color: AppColors.fg4),
            ]),
          ),
        ),
      );
}
