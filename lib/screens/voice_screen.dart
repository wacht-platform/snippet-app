import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../desktop_layout.dart';
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

  String _voiceLabel(TtsVoice v) =>
      '${v.name} · ${v.accent} ${v.gender.toLowerCase()}';

  List<Widget> _ambientGroups(AmbientSettings a) {
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

  Widget _section(String text, {bool first = false}) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : S.s32, bottom: S.s4),
        child: Text(text,
            style: sans(13, weight: W.label, color: AppColors.fg3)),
      );

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

  List<Widget> _desktopRows(VoiceSettings v) {
    final lengths = <int>{60, 120, 180, 300, 600, v.maxSeconds}
        .where((s) => s >= v.minSeconds && s <= v.maxSecondsLimit)
        .toList()
      ..sort();
    final a = _ambient;
    return [
      DesktopFormRow(
        label: 'Voice notes',
        description: 'Record and send voice notes from a session.',
        control: SettingsSwitch(
          value: v.enabled,
          onChanged: _busy ? null : (on) => _save(enabled: on),
        ),
      ),
      DesktopFormRow(
        label: 'Longest note',
        description: 'Recordings stop at this length.',
        divider: false,
        control: SettingsPopup<int>(
          label: _lengthLabel(v.maxSeconds),
          selected: v.maxSeconds,
          items: [for (final s in lengths) (s, _lengthLabel(s))],
          onSelected: (s) => _save(maxSeconds: s),
        ),
      ),
      if (a != null) ..._ambientDesktopRows(a),
    ];
  }

  List<Widget> _ambientDesktopRows(AmbientSettings a) {
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
      _section('Speech services'),
      DesktopFormRow(
        label: 'Speech recognition',
        description: 'Keys stay on the server.',
        control: SettingsPopup<String>(
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
      DesktopFormRow(
        label: 'AssemblyAI key',
        control: _keyControl(
            a.assemblyaiKeySet,
            () => _editKey(
                'AssemblyAI',
                a.assemblyaiKeySet,
                'Paste the key from assemblyai.com/dashboard',
                (k) => _saveAmbient(
                    assemblyaiKey: k, done: 'AssemblyAI key saved'))),
      ),
      DesktopFormRow(
        label: 'Deepgram key',
        control: _keyControl(
            a.deepgramKeySet,
            () => _editKey(
                'Deepgram',
                a.deepgramKeySet,
                'Paste the key from console.deepgram.com',
                (k) =>
                    _saveAmbient(deepgramKey: k, done: 'Deepgram key saved'))),
      ),
      DesktopFormRow(
        label: 'Deepgram region',
        control: SettingsPopup<String>(
          label: hostLabel,
          selected: a.deepgramHost,
          items: [for (final h in hosts) (h.$1, h.$2)],
          onSelected: (h) =>
              _saveAmbient(deepgramHost: h, done: 'Region saved'),
        ),
      ),
      if (a.ttsVoices.isNotEmpty)
        DesktopFormRow(
          label: 'Voice',
          description: 'How the assistant sounds when it speaks.',
          divider: false,
          control: SettingsPopup<String>(
            label: voice?.name ?? a.ttsVoice,
            sheetHeightFactor: 0.5,
            selected: a.ttsVoice,
            items: [for (final v in a.ttsVoices) (v.model, _voiceLabel(v))],
            onSelected: (m) => _saveAmbient(ttsVoice: m, done: 'Voice saved'),
          ),
        ),
      _section('Conversation'),
      DesktopFormRow(
        label: 'Wake phrases',
        description: 'A wake phrase starts a conversation, even in Passive mode.',
        control: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
                a.wakePhrases.isEmpty ? 'None' : a.wakePhrases.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg3)),
          ),
          const SizedBox(width: S.s12),
          Btn('Edit',
              small: true,
              variant: BtnVariant.secondary,
              onTap: _busy ? null : () => _editPhrases(a)),
        ]),
      ),
      DesktopFormRow(
        label: 'Ends after silence',
        description: 'How long to wait before a conversation closes.',
        divider: false,
        control: SettingsPopup<int>(
          label: _lengthLabel(a.conversationTimeoutSecs),
          selected: a.conversationTimeoutSecs,
          items: [for (final s in timeouts) (s, _lengthLabel(s))],
          onSelected: (s) => _saveAmbient(timeout: s),
        ),
      ),
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
      body = ListView(
        padding: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s40),
        children: [
          _section('Recording', first: true),
          ..._desktopRows(v),
        ],
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
