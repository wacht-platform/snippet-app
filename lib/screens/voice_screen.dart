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

  @override
  void initState() {
    super.initState();
    _load();
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
          SettingsRow(
            label: 'AssemblyAI key',
            sub: v.keySet ? 'Saved on this machine' : 'Needed to transcribe',
            onTap: () => _editKey(v),
            trailing: Text(v.keySet ? 'Set' : 'Not set',
                style: sans(kMobile ? 15 : 12.5,
                    color: v.keySet ? AppColors.fg3 : AppColors.danger)),
            chevron: true,
          ),
          if (v.keySet)
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
          SettingsRow(
            label: v.keyterms.isEmpty ? 'Add key terms' : '${v.keyterms.length} terms',
            sub: v.keyterms.isEmpty ? null : v.keyterms.join(', '),
            onTap: () => _editTerms(v),
            chevron: true,
          ),
        ],
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
