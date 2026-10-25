import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
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

  @override
  void dispose() {
    super.dispose();
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
    String? deepgramHost,
    String? ttsVoice,
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
          deepgramHost: deepgramHost,
          ttsVoice: ttsVoice,
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

  Widget _keyRow(String label, bool keySet, VoidCallback onTap) => SettingsRow(
        label: label,
        onTap: _busy ? null : onTap,
        trailing: Text(keySet ? 'Set' : 'Not set',
            style: sans(15, color: keySet ? AppColors.fg3 : AppColors.danger)),
        chevron: true,
      );

  String _voiceLabel(TtsVoice v) => '${v.name} · ${v.accent} ${v.gender.toLowerCase()}';

  List<Widget> _ambientGroups(AmbientSettings a) {
    final timeouts = <int>{30, 60, 90, 180, 300, a.conversationTimeoutSecs}.toList()..sort();
    final hosts = a.deepgramHosts.isEmpty ? [(a.deepgramHost, a.deepgramHost)] : a.deepgramHosts;
    final hostLabel = hosts.firstWhere((h) => h.$1 == a.deepgramHost, orElse: () => (a.deepgramHost, a.deepgramHost)).$2;
    final voice = a.ttsVoices.where((v) => v.model == a.ttsVoice).firstOrNull;
    return [
      SettingsGroup(
        header: 'Speech services',
        footer: 'Speech recognition turns what you say into text; Deepgram speaks the replies. '
            'Deepgram Flux uses the Deepgram key and region, so it needs no AssemblyAI key. '
            'Keys stay on the server and are never shown after saving. '
            'Pick the Deepgram region closest to the server for the fastest replies.',
        children: [
          SettingsRow(
            label: 'Speech recognition',
            trailing: SettingsPopup<String>(
              label: a.stt == 'flux' ? 'Deepgram Flux' : 'AssemblyAI',
              selected: a.stt,
              items: const [('assemblyai', 'AssemblyAI'), ('flux', 'Deepgram Flux')],
              onSelected: (v) => _saveAmbient(stt: v, done: 'Speech recognition saved'),
            ),
          ),
          _keyRow('AssemblyAI key', a.assemblyaiKeySet,
              () => _editKey('AssemblyAI', a.assemblyaiKeySet, 'Paste the key from assemblyai.com/dashboard',
                  (k) => _saveAmbient(assemblyaiKey: k, done: 'AssemblyAI key saved'))),
          _keyRow('Deepgram key', a.deepgramKeySet,
              () => _editKey('Deepgram', a.deepgramKeySet, 'Paste the key from console.deepgram.com',
                  (k) => _saveAmbient(deepgramKey: k, done: 'Deepgram key saved'))),
          SettingsRow(
            label: 'Deepgram region',
            trailing: SettingsPopup<String>(
              label: hostLabel,
              selected: a.deepgramHost,
              items: [for (final h in hosts) (h.$1, h.$2)],
              onSelected: (h) => _saveAmbient(deepgramHost: h, done: 'Region saved'),
            ),
          ),
          if (a.ttsVoices.isNotEmpty)
            SettingsRow(
              label: 'Voice',
              trailing: SettingsPopup<String>(
                label: voice?.name ?? a.ttsVoice,
                selected: a.ttsVoice,
                items: [for (final v in a.ttsVoices) (v.model, _voiceLabel(v))],
                onSelected: (m) => _saveAmbient(ttsVoice: m, done: 'Voice saved'),
              ),
            ),
        ],
      ),
      SettingsGroup(
        header: 'Conversation',
        footer: 'Saying a wake phrase at the start of a sentence opens a spoken '
            'conversation with Mission Control, even in Passive mode.',
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
    ];
  }

  List<Widget> _groups(VoiceSettings v) {
    final lengths = <int>{60, 120, 180, 300, 600, v.maxSeconds}
        .where((s) => s >= v.minSeconds && s <= v.maxSecondsLimit)
        .toList()
      ..sort();
    return [
      SettingsGroup(
        footer: 'Voice notes are transcribed by the configured cloud speech service before the message is sent.',
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

  @override
  Widget build(BuildContext context) {
    final v = _voice;
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
    } else if (kMobile) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: _groups(v),
      );
    } else {
      body = PageBody(topPadding: 4, children: _groups(v));
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
