import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

const _languages = [
  ('', 'Auto-detect'),
  ('en', 'English'),
  ('hi', 'Hindi'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('pt', 'Portuguese'),
  ('it', 'Italian'),
  ('nl', 'Dutch'),
  ('ja', 'Japanese'),
  ('zh', 'Chinese'),
];

const _modelLabels = {
  '': 'Automatic',
  'universal-3-5-pro': 'Universal 3.5 Pro',
  'universal-2': 'Universal 2',
};

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
  bool _customLanguage = false;
  final _keyField = TextEditingController();
  final _langField = TextEditingController();
  final _termField = TextEditingController();
  final _termFocus = FocusNode();

  @override
  void dispose() {
    _modelTimer?.cancel();
    _keyField.dispose();
    _langField.dispose();
    _termField.dispose();
    _termFocus.dispose();
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
    String? speechModel,
    String? language,
    List<String>? keyterms,
    int? maxSeconds,
    String? apiKey,
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.setVoice(
        enabled: enabled,
        speechModel: speechModel,
        language: language,
        keyterms: keyterms,
        maxSeconds: maxSeconds,
        apiKey: apiKey,
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

  bool _isKnownLanguage(String code) => _languages.any((l) => l.$1 == code);

  Future<void> _saveKeyInline() async {
    final key = _keyField.text.trim();
    if (key.isEmpty) return;
    await _save(apiKey: key, done: 'Key saved');
    if (mounted && _voice?.keySet == true) _keyField.clear();
  }

  Future<void> _addTermInline(VoiceSettings v) async {
    final added = [
      for (final t in _termField.text.split(',')) if (t.trim().isNotEmpty) t.trim()
    ];
    if (added.isEmpty) return;
    await _save(keyterms: [...v.keyterms, ...added]);
    if (!mounted) return;
    _termField.clear();
    _termFocus.requestFocus();
  }

  Widget _desktopLanguage(VoiceSettings v) {
    final custom = _customLanguage || !_isKnownLanguage(v.language);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (custom) ...[
        SettingsField(
          controller: _langField,
          hint: 'code, e.g. ta',
          width: 110,
          mono: true,
          onSubmitted: (code) => _save(language: code.trim()),
        ),
        const SizedBox(width: 8),
      ],
      SettingsPopup<String>(
        label: custom
            ? 'Other'
            : _languages.firstWhere((l) => l.$1 == v.language).$2,
        selected: custom ? '\u0000other' : v.language,
        items: [
          for (final (code, label) in _languages)
            (code, code.isEmpty ? label : '$label ($code)'),
          ('\u0000other', 'Other…'),
        ],
        onSelected: (code) {
          if (code == '\u0000other') {
            setState(() {
              _customLanguage = true;
              _langField.text = _isKnownLanguage(v.language) ? '' : v.language;
            });
          } else {
            setState(() => _customLanguage = false);
            _save(language: code);
          }
        },
      ),
    ]);
  }

  Widget _desktopKey(VoiceSettings v) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SettingsField(
        controller: _keyField,
        hint: v.keySet ? 'Paste a new key to replace' : 'Paste your API key',
        width: 260,
        mono: true,
        obscure: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _saveKeyInline(),
      ),
      if (_keyField.text.trim().isNotEmpty) ...[
        const SizedBox(width: 8),
        Btn('Save', small: true, onTap: _busy ? null : _saveKeyInline),
      ],
      if (v.keySet) ...[
        const SizedBox(width: 6),
        Btn('Remove',
            small: true,
            variant: BtnVariant.secondary,
            onTap: _busy ? null : () => _save(apiKey: '', done: 'Key removed')),
      ],
    ]);
  }

  Widget _desktopTerms(VoiceSettings v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in v.keyterms)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 3, 3, 3),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t, style: sans(12.5, color: AppColors.fg1)),
                const SizedBox(width: 2),
                IconBtn('x',
                    size: 20,
                    iconSize: 11,
                    tooltip: 'Remove $t',
                    onTap: _busy
                        ? null
                        : () => _save(
                            keyterms: [...v.keyterms]..remove(t))),
              ]),
            ),
          SettingsField(
            controller: _termField,
            focusNode: _termFocus,
            hint: v.keyterms.isEmpty
                ? 'Type a name or word, then Enter'
                : 'Add another…',
            width: 230,
            onSubmitted: (_) => _addTermInline(v),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext anchor, VoiceSettings v) async {
    final known = {for (final (code, _) in _languages) code};
    String? picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      items: [
        for (final (code, label) in _languages)
          appMenuItem(
              value: code,
              label: code.isEmpty ? label : '$label ($code)',
              selected: v.language == code),
        appMenuItem(
            value: '\u0000other',
            label: known.contains(v.language)
                ? 'Other language code…'
                : 'Other: ${v.language}',
            selected: !known.contains(v.language)),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == '\u0000other') {
      picked = await promptText(context,
          title: 'Language code',
          initial: known.contains(v.language) ? '' : v.language,
          hint: 'e.g. ta, ko, ar');
      if (picked == null || !mounted) return;
    }
    await _save(language: picked.trim());
  }

  Future<void> _editTerms(VoiceSettings v) async {
    final text = await promptText(context,
        title: 'Key terms',
        initial: v.keyterms.join('\n'),
        hint: 'One per line: names, products, jargon',
        minLines: 4,
        maxLines: 10);
    if (text == null || !mounted) return;
    final terms = [
      for (final t in text.split(RegExp(r'[\n,]')))
        if (t.trim().isNotEmpty) t.trim()
    ];
    await _save(keyterms: terms);
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
    String? voice,
    String? sttModel,
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
          voice: voice,
          sttModel: sttModel,
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
        children: [for (final m in _models.where((m) => m.kind == 'stt')) _modelRow(m, a.sttModel == m.id, (id) => _saveAmbient(sttModel: id))],
      ),
      SettingsGroup(
        header: 'Reply voice',
        footer: 'Mission Control\'s spoken replies are made on this machine and played on the listening device.',
        children: [for (final m in _models.where((m) => m.kind == 'tts')) _modelRow(m, a.voice == m.id, (id) => _saveAmbient(voice: id))],
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

  Future<void> _editKey(VoiceSettings v) async {
    final key = await promptText(context,
        title: v.keySet ? 'Replace AssemblyAI key' : 'AssemblyAI API key',
        hint: 'Paste the key from assemblyai.com',
        saveLabel: 'Save key');
    if (key == null || key.trim().isEmpty || !mounted) return;
    await _save(apiKey: key.trim(), done: 'Key saved');
  }

  List<Widget> _groups(VoiceSettings v) {
    final lengths = <int>{60, 120, 180, 300, 600, v.maxSeconds}
        .where((s) => s >= v.minSeconds && s <= v.maxSecondsLimit)
        .toList()
      ..sort();
    final languageLabel = v.language.isEmpty
        ? 'Auto-detect'
        : _languages
            .firstWhere((l) => l.$1 == v.language, orElse: () => (v.language, v.language))
            .$2;
    return [
      SettingsGroup(
        footer: 'Voice notes you record in the app are transcribed on this '
            'machine with AssemblyAI before the message is sent.',
        children: [
          SettingsRow(
            label: 'Voice notes',
            trailing: SettingsSwitch(
              value: v.enabled,
              onChanged: _busy ? null : (on) => _save(enabled: on),
            ),
          ),
          if (!kMobile)
            SettingsRow(
              label: 'AssemblyAI key',
              sub: v.keySet ? 'Saved on this machine' : 'Needed to transcribe',
              trailing: _desktopKey(v),
            )
          else
            SettingsRow(
              label: 'AssemblyAI key',
              sub: v.keySet ? 'Saved on this machine' : 'Needed to transcribe',
              onTap: () => _editKey(v),
              trailing: Text(v.keySet ? 'Set' : 'Not set',
                  style: sans(15,
                      color: v.keySet ? AppColors.fg3 : AppColors.danger)),
              chevron: true,
            ),
          if (kMobile && v.keySet)
            SettingsRow(
              label: 'Remove key',
              danger: true,
              onTap: _busy ? null : () => _save(apiKey: '', done: 'Key removed'),
            ),
        ],
      ),
      SettingsGroup(
        header: 'Transcription',
        children: [
          SettingsRow(
            label: 'Speech model',
            trailing: SettingsPopup<String>(
              label: _modelLabels[v.speechModel] ?? v.speechModel,
              selected: v.speechModel,
              items: [
                ('', _modelLabels['']!),
                for (final m in v.speechModels) (m, _modelLabels[m] ?? m),
              ],
              onSelected: (m) => _save(speechModel: m),
            ),
          ),
          if (!kMobile)
            SettingsRow(label: 'Language', trailing: _desktopLanguage(v))
          else
          Builder(
            builder: (anchor) => SettingsRow(
              label: 'Language',
              onTap: () => _pickLanguage(anchor, v),
              trailing: Text(languageLabel,
                  style: sans(kMobile ? 15 : 12.5, color: AppColors.fg3)),
              chevron: true,
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
      SettingsGroup(
        header: 'Key terms',
        footer: 'Names and words the transcriber should get right, such as '
            'people, products and project jargon.',
        children: [
          if (!kMobile)
            _desktopTerms(v)
          else
          SettingsRow(
            label: v.keyterms.isEmpty ? 'Add key terms' : '${v.keyterms.length} terms',
            sub: v.keyterms.isEmpty ? null : v.keyterms.join(', '),
            onTap: () => _editTerms(v),
            chevron: true,
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
