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
    _modelTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadAmbient();
    _loadModels();
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
  List<ModelInfo> _models = const [];
  Timer? _modelTimer;

  Future<void> _loadModels() async {
    try {
      final list = await widget.client.listModels();
      if (!mounted) return;
      setState(() => _models = list);
      _modelTimer?.cancel();
      if (list.any((m) => m.downloading)) {
        _modelTimer = Timer(const Duration(seconds: 2), _loadModels);
      } else {
        _loadAmbient();
      }
    } catch (_) {}
  }

  Future<void> _modelAction(Future<List<ModelInfo>> Function() run) async {
    try {
      final list = await run();
      if (!mounted) return;
      setState(() => _models = list);
      _modelTimer?.cancel();
      _modelTimer = Timer(const Duration(seconds: 1), _loadModels);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _modelRow(ModelInfo m, bool selected, Future<void> Function(String id) use) {
    Widget trailing;
    if (m.downloading) {
      trailing = Text('${m.percent}%', style: sans(kMobile ? 15 : 12.5, color: AppColors.fg3));
    } else if (m.ready) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        if (selected)
          AppIcon('check', size: 16, color: AppColors.accent)
        else
          Text('Use', style: sans(kMobile ? 15 : 12.5, color: AppColors.accent)),
        const SizedBox(width: 10),
        IconBtn('trash',
            size: 32,
            iconSize: 15,
            tooltip: 'Remove',
            onTap: () => _modelAction(() => widget.client.deleteModel(m.id))),
      ]);
    } else {
      trailing = Text(m.status == 'failed' ? 'Retry' : 'Download',
          style: sans(kMobile ? 15 : 12.5, color: AppColors.accent));
    }
    final sub = m.status == 'failed'
        ? (m.error ?? 'Download failed')
        : '${m.detail} ${m.sizeMb} MB';
    return SettingsRow(
      label: m.name,
      sub: sub,
      trailing: trailing,
      onTap: m.downloading
          ? null
          : m.ready
              ? (selected ? null : () => use(m.id))
              : () => _modelAction(() => widget.client.downloadModel(m.id)),
    );
  }

  Future<void> _loadAmbient() async {
    try {
      final a = await widget.client.getAmbientSettings();
      if (mounted) setState(() => _ambient = a);
    } catch (_) {}
  }

  Future<void> _saveAmbient({
    String? watcher,
    bool? chatContext,
    String? typesafeKey,
    int? timeout,
    List<String>? phrases,
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.setAmbientSettings(
          watcher: watcher,
          watcherChatContext: chatContext,
          typesafeKey: typesafeKey,
          conversationTimeoutSecs: timeout,
          wakePhrases: phrases);
      if (!mounted) return;
      setState(() => _ambient = next);
      if (done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, "Couldn't save: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editWatcherKey(AmbientSettings a) async {
    final key = await promptText(context,
        title: a.watcherKeySet ? 'Replace TypeSafe key' : 'TypeSafe API key',
        hint: 'Paste the key from typesafe.ai',
        saveLabel: 'Save key');
    if (key == null || key.trim().isEmpty || !mounted) return;
    await _saveAmbient(typesafeKey: key.trim(), done: 'Key saved');
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

  List<Widget> _ambientGroups(AmbientSettings a) {
    final timeouts = <int>{30, 60, 90, 180, 300, a.conversationTimeoutSecs}.toList()..sort();
    return [
      SettingsGroup(
        header: 'Ambient listening',
        footer: 'Each line of speech is sent to TypeSafe (Jev) to tell real '
            'conversation from TV and background, and to notice when you are '
            'talking to the assistant. With chat context on, a short, redacted '
            'tail of your Mission Control chat goes too. Without Jev, only a '
            'wake phrase works.',
        children: [
          SettingsRow(
            label: 'Filter with Jev',
            trailing: SettingsSwitch(
              value: a.watcher == 'jev',
              onChanged: _busy ? null : (on) => _saveAmbient(watcher: on ? 'jev' : 'off'),
            ),
          ),
          SettingsRow(
            label: 'Share chat context',
            sub: 'Send recent Mission Control chat and its open question to Jev',
            trailing: SettingsSwitch(
              value: a.watcherChatContext,
              onChanged: _busy || a.watcher != 'jev'
                  ? null
                  : (on) => _saveAmbient(chatContext: on),
            ),
          ),
          SettingsRow(
            label: 'TypeSafe key',
            sub: a.watcherKeySet ? 'Saved on this machine' : 'Needed for Jev',
            chevron: true,
            onTap: () => _editWatcherKey(a),
          ),
        ],
      ),
      SettingsGroup(
        header: 'Speech recognition',
        footer: 'Runs on this machine, so your audio never leaves it. Ambient listening needs one downloaded.',
        children: [for (final m in _models.where((m) => m.kind == 'stt')) _modelRow(m, false, (_) async {})],
      ),
      SettingsGroup(
        header: 'Reply voice',
        footer: 'Mission Control\'s spoken replies are made on this machine and played on the listening device.',
        children: [for (final m in _models.where((m) => m.kind == 'tts')) _modelRow(m, false, (_) async {})],
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
        footer: 'Voice notes are transcribed on this machine with the downloaded speech model before the message is sent.',
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
