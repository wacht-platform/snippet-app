import 'package:flutter/material.dart';
import '../api.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

class WebSearchScreen extends StatefulWidget {
  const WebSearchScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends State<WebSearchScreen> {
  bool? _keySet;
  Object? _error;
  bool _busy = false;
  final _keyField = TextEditingController();

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

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
          _keySet = c.webSearchKeySet;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(String apiKey, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final set = await widget.client.setWebSearchKey(apiKey);
      if (!mounted) return;
      setState(() => _keySet = set);
      if (set) _keyField.clear();
      toast(context, done);
    } catch (e) {
      if (mounted) toast(context, "Couldn't save: $e", danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKeyInline() async {
    final key = _keyField.text.trim();
    if (key.isEmpty) return;
    await _save(key, 'Key saved');
  }

  Future<void> _editKey(bool keySet) async {
    final key = await promptText(context,
        title: keySet ? 'Replace Exa key' : 'Exa API key',
        hint: 'Paste the key from dashboard.exa.ai',
        saveLabel: 'Save key');
    if (key == null || key.trim().isEmpty || !mounted) return;
    await _save(key.trim(), 'Key saved');
  }

  Widget _desktopKey() {
    final empty = _keyField.text.trim().isEmpty;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SettingsField(
        controller: _keyField,
        hint: 'exa-…',
        width: 240,
        mono: true,
        obscure: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _saveKeyInline(),
      ),
      const SizedBox(width: 8),
      Btn('Save',
          small: true,
          disabled: empty || _busy,
          onTap: empty || _busy ? null : _saveKeyInline),
    ]);
  }

  List<Widget> _groups(bool keySet) {
    final sub = keySet ? 'On for new sessions' : 'Off until a key is saved';
    return [
      SettingsGroup(
        footer: 'Agents get web_search and web_read, powered by Exa, in '
            'sessions that start after the key is saved. The key stays on '
            'this machine.',
        children: [
          if (!kMobile) ...[
            SettingsRow(
              label: 'Exa search',
              sub: 'Web search and page reading for agents',
              trailing: Tag(keySet ? 'Active' : 'Not set',
                  tone: keySet ? Tone.ok : Tone.neutral, dot: true),
            ),
            SettingsRow(
              label: keySet ? 'Replace key' : 'API key',
              sub: 'From dashboard.exa.ai',
              trailing: _desktopKey(),
            ),
            if (keySet)
              SettingsRow(
                label: 'Remove key',
                sub: 'Turns web search off for new sessions',
                trailing: SettingsPill('Remove',
                    danger: true,
                    onTap: _busy ? null : () => _save('', 'Key removed')),
              ),
          ] else
            SettingsRow(
              label: 'Exa key',
              sub: sub,
              onTap: () => _editKey(keySet),
              trailing: Text(keySet ? 'Set' : 'Not set',
                  style: sans(15,
                      color: keySet ? AppColors.fg3 : AppColors.danger)),
              chevron: true,
            ),
          if (kMobile && keySet)
            SettingsRow(
              label: 'Remove key',
              danger: true,
              onTap: _busy ? null : () => _save('', 'Key removed'),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final keySet = _keySet;
    if (!kMobile && widget.embedded && widget.onBack == null) {
      if (keySet == null) {
        return SettingsGroup(children: [
          _error == null
              ? const SettingsRow(label: 'Loading web search settings…')
              : SettingsRow(
                  label: "Couldn't load web search settings",
                  sub: '$_error',
                  danger: true,
                  trailing: Btn('Retry',
                      small: true, variant: BtnVariant.secondary, onTap: _load),
                ),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _groups(keySet),
      );
    }
    final Widget body;
    if (keySet == null) {
      body = _error == null
          ? const ListSkeleton()
          : EmptyState(
              icon: 'alert-triangle',
              title: "Couldn't load web search settings",
              body: '$_error',
              action: Btn('Retry', small: true, onTap: _load),
            );
    } else {
      body = ListView(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(16, 8, 16, 40)
            : const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s40),
        children: _groups(keySet),
      );
    }
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Web search', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return body;
  }
}
