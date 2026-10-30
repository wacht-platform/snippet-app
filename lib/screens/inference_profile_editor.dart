import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../settings_form.dart';

import '../widgets.dart';

// (value sent to the daemon, label shown in the pill)
const _providers = [
  ('anthropic', 'Anthropic'),
  ('openai', 'OpenAI'),
  ('gemini', 'Google'),
  ('openai-compatible', 'OpenAI-compatible'),
  ('anthropic-compatible', 'Anthropic-compatible'),
  ('openrouter', 'OpenRouter'),
  ('opencode-zen', 'OpenCode Zen'),
  ('opencode-go', 'OpenCode Go'),
  ('xai', 'xAI (Grok)'),
  ('chatgpt', 'ChatGPT'),
  ('claude-code', 'Claude Code'),
  ('antigravity', 'Antigravity'),
];

String _providerLabel(String p) =>
    _providers.where((e) => e.$1 == p).map((e) => e.$2).firstOrNull ?? p;

bool _needsBaseUrl(String p) =>
    p == 'openai-compatible' || p == 'anthropic-compatible';
bool _defaultImages(String p) =>
    p == 'anthropic' ||
    p == 'gemini' ||
    p == 'openai' ||
    p == 'chatgpt' ||
    p == 'claude-code' ||
    p == 'antigravity';
// Providers that go through the OpenAI-compatible adapter, where `stream` applies.
bool _usesOpenAiAdapter(String p) =>
    p == 'openai' ||
    p == 'openai-compatible' ||
    p == 'openrouter' ||
    p == 'opencode-zen' ||
    p == 'opencode-go';

class InferenceProfileEditor extends StatefulWidget {
  final DaemonClient client;
  final InferenceProfile? existing;

  /// Skip Scaffold / app bar and fill the parent (settings Models pane).
  final bool embedded;

  /// Dismiss when hosted in a responsive panel (desktop drawer / phone full-screen).
  final VoidCallback? onClose;

  /// Called after a successful save, before [onClose].
  final VoidCallback? onSaved;

  final void Function(InferenceProfile draft, Future<void> save)? onSubmit;
  final VoidCallback? onDelete;
  final bool detail;
  const InferenceProfileEditor(
      {super.key,
      this.onDelete,
      this.detail = false,
      required this.client,
      this.existing,
      this.embedded = false,
      this.onClose,
      this.onSaved,
      this.onSubmit});
  @override
  State<InferenceProfileEditor> createState() => InferenceProfileEditorState();
}

class InferenceProfileEditorState extends State<InferenceProfileEditor> {
  String _baseline = '';

  String _snapshot() => [
        _provider,
        _name.text,
        _baseUrl.text,
        _model.text,
        _ctx.text,
        _compact.text,
        _key.text,
        _images,
        _active,
        _stream,
        _xSearch,
        _effort,
      ].join('\u0001');

  bool get dirty => _snapshot() != _baseline;

  late String _provider;
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _ctx;
  late final TextEditingController _compact;
  final _key = TextEditingController();
  bool _showKey = false;
  late bool _images;
  bool _active = false;
  bool _stream = false;
  bool _xSearch = false;
  String _effort = ''; // '' = provider default
  Map<String, dynamic>? _reasoning;
  Timer? _reasoningDebounce;
  int _reasoningSeq = 0;
  bool _busy = false;
  String? _error;

  /// Capability line under the Model field, from the provider's live catalog
  /// (effort tiers on Anthropic, reasoning yes/no on OpenRouter, context size).
  String? _modelHint;

  bool _showModelBrowser = false;
  bool _loadingModels = false;
  List<CatalogModel>? _catalogModels;
  final TextEditingController _modelSearch = TextEditingController();

  bool get _isEdit => widget.existing != null;
  bool get _isChatgpt => _provider == 'chatgpt';
  bool get _isXai => _provider == 'xai';
  bool get _isClaudeCode => _provider == 'claude-code';
  bool get _isAntigravity => _provider == 'antigravity';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _provider = e?.provider ?? 'anthropic';
    _name = TextEditingController(text: e?.name ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _ctx = TextEditingController(
        text: (e?.contextWindow ?? 0) > 0 ? '${e!.contextWindow}' : '');
    _compact = TextEditingController(text: '${e?.compactAtPct ?? 90}');
    // Editing keeps the profile's actual flag — falling back to the provider
    // default silently reset it on every unrelated edit.
    _images = e?.supportsImages ?? _defaultImages(_provider);
    _active = e?.active ?? !_isEdit;
    _stream = e?.stream ?? false;
    _xSearch = e?.xSearch ?? false;
    _effort = e?.reasoningEffort ?? '';
    // The Save button's enabled state depends on this field; without a listener
    // typing never rebuilt, leaving Save stuck disabled on desktop.
    _model.addListener(() => setState(() {}));
    _model.addListener(_scheduleReasoning);
    _modelSearch.addListener(() => setState(() {}));
    _loadReasoning();
    _baseline = _snapshot();
  }

  String _reasoningKey = '';

  void _scheduleReasoning() {
    if ('$_provider|${_model.text.trim()}' == _reasoningKey) return;
    _reasoningDebounce?.cancel();
    _reasoningDebounce =
        Timer(const Duration(milliseconds: 350), _loadReasoning);
  }

  Future<void> _loadReasoning() async {
    final key = '$_provider|${_model.text.trim()}';
    _reasoningKey = key;
    final seq = ++_reasoningSeq;
    try {
      final spec =
          await widget.client.reasoningSpec(_provider, _model.text.trim());
      if (!mounted || seq != _reasoningSeq) return;
      setState(() => _reasoning = spec);
    } catch (_) {
      if (mounted && seq == _reasoningSeq) setState(() => _reasoning = null);
    }
  }

  List<(String, String)> get _effortItems {
    const labels = {
      'off': 'Off',
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
      'xhigh': 'X-High',
      'max': 'Max',
    };
    final spec = _reasoning;
    if (spec == null) {
      return [('', 'Default'), ...labels.entries.map((e) => (e.key, e.value))];
    }
    final options = (spec['options'] as List? ?? const []).cast<String>();
    return [
      ('', 'Default'),
      if (spec['can_disable'] == true) ('off', 'Off'),
      for (final o in options) (o, labels[o] ?? o),
    ];
  }

  String get _effortToSave =>
      _effortAdjustable && _effortItems.any((i) => i.$1 == _effort)
          ? _effort
          : '';

  bool get _effortAdjustable =>
      _reasoning == null || _reasoning!['control'] == 'effort';

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _ctx.dispose();
    _compact.dispose();
    _key.dispose();
    _modelSearch.dispose();
    _reasoningDebounce?.cancel();
    super.dispose();
  }

  static String _fmtCtx(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M ctx'
      : '${(n / 1000).round()}k ctx';

  void _applyPick(CatalogModel m) {
    _model.text = m.id;
    // A reported context window beats whatever was there — it's authoritative.
    if (m.contextWindow != null && m.contextWindow! > 0)
      _ctx.text = '${m.contextWindow}';
    final bits = <String>[];
    if (m.efforts != null) {
      bits.add(m.efforts!.isEmpty
          ? 'no effort control'
          : 'effort: ${m.efforts!.join(' · ')}');
    } else if (m.reasoning != null) {
      bits.add(m.reasoning! ? 'supports reasoning' : 'no reasoning');
    }
    if (m.contextWindow != null && m.contextWindow! > 0)
      bits.add(_fmtCtx(m.contextWindow!));
    setState(() => _modelHint = bits.isEmpty ? null : bits.join(' · '));
  }

  Future<void> _browseModels() async {
    if (_showModelBrowser) {
      setState(() => _showModelBrowser = false);
      return;
    }
    if (_catalogModels != null && _catalogModels!.isNotEmpty) {
      setState(() => _showModelBrowser = true);
      return;
    }
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    final List<CatalogModel> models;
    try {
      models = await widget.client.providerModels(
        name: widget.existing?.name,
        provider: _provider,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _key.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingModels = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingModels = false);
    if (models.isEmpty) {
      setState(() => _error =
          'The provider returned no models (this provider may not have a catalog).');
      return;
    }
    if (!kMobile || widget.embedded) {
      setState(() {
        _catalogModels = models;
        _showModelBrowser = true;
      });
      return;
    }
    final picked = await showModalBottomSheet<CatalogModel>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      backgroundColor: AppColors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
      builder: (ctx) => _ModelPickerSheet(models: models),
    );
    if (picked != null) _applyPick(picked);
  }

  Widget _inlineModelBrowser() {
    final q = _modelSearch.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _catalogModels!
        : _catalogModels!
            .where((m) =>
                m.id.toLowerCase().contains(q) ||
                (m.displayName?.toLowerCase().contains(q) ?? false))
            .toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              children: [
                AppIcon('search', size: 14, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _modelSearch,
                    autofocus: true,
                    style: sans(12, color: AppColors.fg1),
                    decoration: InputDecoration(
                      hintText: 'Search ${_catalogModels!.length} models…',
                      hintStyle: TS.meta(AppColors.fg4),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Text('${filtered.length}',
                    style: mono(11, color: AppColors.fg4)),
                const SizedBox(width: 4),
                IconBtn('x',
                    size: 22,
                    iconSize: 12,
                    tooltip: 'Close catalog',
                    onTap: () => setState(() => _showModelBrowser = false)),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No matching models', style: TS.meta()),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppColors.border.withValues(alpha: 0.25)),
                    itemBuilder: (ctx, i) {
                      final m = filtered[i];
                      final isSelected = m.id == _model.text.trim();
                      return InkWell(
                        onTap: () {
                          _applyPick(m);
                          setState(() => _showModelBrowser = false);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(m.id,
                                        style: mono(12,
                                            weight: isSelected
                                                ? W.label
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? AppColors.accent
                                                : AppColors.fg1)),
                                    if (m.displayName != null &&
                                        m.displayName!.isNotEmpty &&
                                        m.displayName != m.id) ...[
                                      const SizedBox(height: 1),
                                      Text(m.displayName!,
                                          style:
                                              sans(11, color: AppColors.fg3)),
                                    ],
                                  ],
                                ),
                              ),
                              if (m.contextWindow != null &&
                                  m.contextWindow! > 0)
                                Text(_fmtCtx(m.contextWindow!),
                                    style: mono(10, color: AppColors.fg4)),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                AppIcon('check',
                                    size: 14, color: AppColors.accent),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _dismiss({bool saved = false}) {
    if (saved) {
      widget.onSaved?.call();
      if (widget.onSaved != null) return;
    }
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    Navigator.pop(context, saved);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_model.text.trim().isEmpty) {
      setState(() {
        _error = 'Model is required.';
        _busy = false;
      });
      return;
    }
    final submit = widget.onSubmit;
    if (submit != null) {
      final savedName = _isEdit
          ? widget.existing!.name
          : (_name.text.trim().isEmpty
              ? _model.text.trim()
              : _name.text.trim());
      final draft = InferenceProfile.fromJson({
        'name': savedName,
        'provider': _provider,
        'base_url': _needsBaseUrl(_provider) ? _baseUrl.text.trim() : '',
        'model': _model.text.trim(),
        'has_key':
            _key.text.trim().isNotEmpty || (widget.existing?.hasKey ?? false),
        'active': _active || (widget.existing?.active ?? false),
        'context_window': int.tryParse(_ctx.text.trim()) ?? 0,
        'compact_at_pct': int.tryParse(_compact.text.trim()) ?? 90,
        'reasoning_effort': _effortToSave,
        'stream': _stream,
        'supports_images': _images,
        'x_search': _isXai && _xSearch,
      });
      submit(draft, _persist());
      if (widget.detail) {
        setState(() {
          _busy = false;
          _baseline = _snapshot();
        });
        return;
      }
      _dismiss();
      return;
    }
    try {
      await _persist();
      if (mounted) _dismiss(saved: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _persist() async {
    await widget.client.putProfile(
      name: _isEdit
          ? widget.existing!.name
          : (_name.text.trim().isEmpty ? null : _name.text.trim()),
      provider: _provider,
      baseUrl: _needsBaseUrl(_provider) ? _baseUrl.text.trim() : null,
      model: _model.text.trim(),
      apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
      // Always send it: '' explicitly clears back to provider default (an
      // omitted field means "keep", so Default could never un-set an effort).
      reasoningEffort: _effortToSave,
      supportsImages: _images,
      contextWindow: int.tryParse(_ctx.text.trim()),
      compactAtPct: int.tryParse(_compact.text.trim()),
      stream: _stream,
      xSearch: _isXai ? _xSearch : null,
      setActive: _active,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // include the current provider as a pill even if it's outside the standard list (e.g. chatgpt)
    final pills = [..._providers];
    if (!pills.any((p) => p.$1 == _provider))
      pills.insert(0, (_provider, _provider));
    if (!kMobile && widget.embedded) return _deskDialogBuild(pills);
    final title = _isEdit ? 'Edit profile' : 'Add profile';
    final footer = kMobile
        ? Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Btn(_busy ? 'Saving…' : 'Save profile',
                full: true,
                disabled: _busy || _model.text.trim().isEmpty,
                onTap: _save),
          )
        : Container(
            padding: EdgeInsets.fromLTRB(
                16,
                6,
                16,
                widget.embedded
                    ? 8
                    : 8 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Btn('Cancel',
                    variant: BtnVariant.ghost, small: true, onTap: _dismiss),
                const SizedBox(width: 8),
                Btn(_busy ? 'Saving…' : 'Save',
                    small: true,
                    disabled: _busy || _model.text.trim().isEmpty,
                    onTap: _save),
              ],
            ),
          );
    final body = Column(children: [
      // No embedded header. When embedded, the HOST level owns the header
      // (inference_profiles.dart draws "Edit profile" / "Add profile"), so
      // drawing one here stacked a second back row under it — two rows, two
      // exits, same screen.
      if (!widget.embedded && !kMobile)
        SnAppBar(title: title, onBack: _dismiss),
      Expanded(child: _nativeForm(pills)),
      footer,
    ]);
    if (widget.embedded) return body;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget? _subscriptionSignIn() {
    if (_isChatgpt) {
      return _SubSignIn(
        key: const ValueKey('chatgpt'),
        client: widget.client,
        signedInLabel: 'Signed in to ChatGPT',
        blurb: 'ChatGPT uses your Plus / Pro / Team subscription — no API key.',
        buttonLabel: 'Sign in with ChatGPT',
        signedIn: (c) => c.chatgptSignedIn(),
        begin: (c) => c.chatgptLoginBegin(),
        signOut: (c) => c.chatgptLogout(),
      );
    }
    if (_isXai) {
      return _SubSignIn(
        key: const ValueKey('xai'),
        client: widget.client,
        signedInLabel: 'Signed in to xAI',
        blurb:
            'Grok uses your SuperGrok / X Premium subscription — no API key.',
        buttonLabel: 'Sign in with SuperGrok / X Premium',
        signedIn: (c) => c.xaiSignedIn(),
        begin: (c) => c.xaiLoginBegin(),
        signOut: (c) => c.xaiLogout(),
      );
    }
    if (_isClaudeCode || _isAntigravity) {
      return _CliAgentStatus(
          key: ValueKey(_provider), client: widget.client, provider: _provider);
    }
    return null;
  }

  Widget _deskDialogBuild(List<(String, String)> pills) {
    final modelName = _model.text.trim();
    final title = _isEdit
        ? widget.existing!.name
        : (_name.text.trim().isNotEmpty ? _name.text.trim() : 'New profile');
    final effortLabel =
        '${(_reasoning?['label'] as String?) ?? 'Reasoning'} effort';
    final compact = (int.tryParse(_compact.text.trim()) ?? 90).clamp(10, 100);
    final signIn = _subscriptionSignIn();
    final canSave = !_busy && modelName.isNotEmpty;
    Widget providerPicker() => SettingsPopup<String>(
          label: _providerLabel(_provider),
          leading: ProviderLogo(_provider, size: 12),
          items: pills,
          selected: _provider,
          onSelected: (val) => setState(() {
            _provider = val;
            _images = _defaultImages(val);
            _catalogModels = null;
            _showModelBrowser = false;
            _modelSearch.clear();
            _scheduleReasoning();
          }),
        );
    final connection = <Widget>[
      if (signIn != null)
        Padding(padding: const EdgeInsets.all(12), child: signIn)
      else
        SettingsRow(
          label: 'API key',
          trailing: SettingsField(
            controller: _key,
            width: 240,
            mono: true,
            obscure: !_showKey,
            hint: _isEdit && widget.existing!.hasKey ? 'Saved' : 'sk-…',
            onChanged: (_) => setState(() {}),
            suffix: GestureDetector(
              onTap: () => setState(() => _showKey = !_showKey),
              child: Text(_showKey ? 'Hide' : 'Show',
                  style: sans(11.5, color: AppColors.fg3)),
            ),
          ),
        ),
      if (_needsBaseUrl(_provider))
        SettingsRow(
          label: 'Base URL',
          trailing: SettingsField(
              controller: _baseUrl,
              width: 240,
              mono: true,
              onChanged: (_) => setState(() {}),
              hint: 'https://api.example.com/v1'),
        ),
    ];
    return SettingsColumn(children: [
      SettingsHeader(
        back: SettingsBack('Profiles', onTap: _dismiss),
        title: title,
        subtitle: [
          _providerLabel(_provider),
          if (modelName.isNotEmpty) modelName,
          if (_active) 'used for new sessions',
        ].join(' · '),
        actions: [
          Btn(_busy ? 'Saving…' : (_isEdit ? 'Save' : 'Add profile'),
              small: true, disabled: !canSave, onTap: _save),
        ],
      ),
      const SizedBox(height: S.s8),
      SettingsGroup(
        header: 'Model',
        footer: _modelHint,
        children: [
          if (!_isEdit)
            SettingsRow(
              label: 'Name',
              trailing: SettingsField(
                  controller: _name,
                  width: 240,
                  hint: 'Defaults to the provider',
                  onChanged: (_) => setState(() {})),
            ),
          SettingsRow(
            label: 'Provider',
            trailing: _isEdit
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    ProviderLogo(_provider, size: 12),
                    const SizedBox(width: 6),
                    Text(_providerLabel(_provider),
                        style: sans(12.5, color: AppColors.fg3)),
                  ])
                : providerPicker(),
          ),
          SettingsRow(
            label: 'Model',
            trailing: SettingsField(
              controller: _model,
              width: 240,
              mono: true,
              onChanged: (_) {
                setState(() {});
                _scheduleReasoning();
              },
              hint: _isChatgpt
                  ? 'gpt-5.1-codex'
                  : _isClaudeCode
                      ? 'sonnet'
                      : _isAntigravity
                          ? 'gemini-3.8-flash-high'
                          : 'claude-sonnet-4.5',
              suffix: _loadingModels
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(child: Spinner(size: 12)))
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busy ? null : _browseModels,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: AppIcon(
                          _showModelBrowser ? 'x' : 'chevrons-up-down',
                          size: 13,
                          color: AppColors.fg4,
                        ),
                      ),
                    ),
            ),
          ),
          if (_showModelBrowser && _catalogModels != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _inlineModelBrowser(),
            ),
          SettingsRow(
            label: effortLabel,
            trailing: _effortAdjustable
                ? SettingsPopup<String>(
                    label: _effortItems
                            .where((i) => i.$1 == _effort)
                            .firstOrNull
                            ?.$2 ??
                        'Default',
                    items: _effortItems,
                    selected: _effort,
                    onSelected: (v) => setState(() => _effort = v),
                  )
                : Text(
                    _reasoning?['control'] == 'model'
                        ? 'Set by the model'
                        : 'Not adjustable',
                    style: sans(12.5, color: AppColors.fg3)),
          ),
        ],
      ),
      SettingsGroup(header: 'Context', children: [
        SettingsRow(
          label: 'Context window',
          sub: 'Tokens. Blank keeps the default.',
          trailing: SettingsField(
              controller: _ctx,
              width: 150,
              mono: true,
              number: true,
              hint: '200000'),
        ),
        SettingsRow(
          label: 'Compact at',
          sub: 'History is summarised when the window is this full.',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 160,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.surface3,
                  thumbColor: AppColors.fg1,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: compact.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  onChanged: (v) =>
                      setState(() => _compact.text = '${v.round()}'),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('$compact%',
                  textAlign: TextAlign.right,
                  style: sans(12.5, color: AppColors.fg2)),
            ),
          ]),
        ),
        if (_usesOpenAiAdapter(_provider))
          SettingsRow(
            label: 'Stream responses',
            sub: 'For models that return nothing otherwise.',
            trailing: SettingsSwitch(
                value: _stream, onChanged: (v) => setState(() => _stream = v)),
          ),
      ]),
      SettingsGroup(
        header: 'Connection',
        footer: 'Keys stay on the machine running snippet.',
        children: connection,
      ),
      SettingsGroup(header: 'Options', children: [
        SettingsRow(
          label: 'Supports images',
          sub: 'Send screenshots and diagrams to this model.',
          trailing: SettingsSwitch(
              value: _images, onChanged: (v) => setState(() => _images = v)),
        ),
        if (_isXai)
          SettingsRow(
            label: 'X search',
            sub: 'Let Grok search X with xAI’s server-side tool.',
            trailing: SettingsSwitch(
                value: _xSearch,
                onChanged: (v) => setState(() => _xSearch = v)),
          ),
        SettingsRow(
          label: 'Use for new sessions',
          sub: 'Make this the active profile.',
          trailing: SettingsSwitch(
              value: _active, onChanged: (v) => setState(() => _active = v)),
        ),
      ]),
      if (_isEdit && widget.onDelete != null)
        SettingsGroup(children: [
          SettingsRow(
              label: 'Delete profile', danger: true, onTap: widget.onDelete),
        ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(_error!, style: sans(12, color: AppColors.danger)),
        ),
    ]);
  }

  Widget _nativeForm(List<(String, String)> pills) {
    final modelName = _model.text.trim();
    final title = _isEdit
        ? widget.existing!.name
        : (_name.text.trim().isNotEmpty ? _name.text.trim() : 'New profile');
    final effortLabel =
        '${(_reasoning?['label'] as String?) ?? 'Reasoning'} effort';
    final compact = (int.tryParse(_compact.text.trim()) ?? 90).clamp(10, 100);
    Widget providerPicker() => SettingsPopup<String>(
          label: _providerLabel(_provider),
          leading: ProviderLogo(_provider, size: kMobile ? 14 : 12),
          items: pills,
          selected: _provider,
          onSelected: (val) => setState(() {
            _provider = val;
            _images = _defaultImages(val);
            _catalogModels = null;
            _showModelBrowser = false;
            _modelSearch.clear();
            _scheduleReasoning();
          }),
        );
    final header = kMobile
        ? Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(22,
                    weight: FontWeight.w500,
                    height: 1.15,
                    spacing: -0.4,
                    color: AppColors.fg1)),
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Center(child: ProviderLogo(_provider, size: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(17,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Text(
                          [
                            _providerLabel(_provider),
                            if (modelName.isNotEmpty) modelName,
                            if (_active) 'used for new sessions',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12.5, color: AppColors.fg4)),
                    ]),
              ),
              if (_isEdit && widget.onDelete != null)
                SettingsPill('Delete', danger: true, onTap: widget.onDelete),
            ]),
          );
    final signIn = _subscriptionSignIn();
    final connection = <Widget>[
      if (signIn != null)
        Padding(padding: const EdgeInsets.all(12), child: signIn)
      else
        SettingsRow(
          label: 'API key',
          trailing: SettingsField(
            controller: _key,
            width: 220,
            mono: true,
            obscure: !_showKey,
            hint: _isEdit && widget.existing!.hasKey ? 'Saved' : 'sk-…',
            suffix: GestureDetector(
              onTap: () => setState(() => _showKey = !_showKey),
              child: Text(_showKey ? 'Hide' : 'Show',
                  style: sans(11.5, color: AppColors.fg3)),
            ),
          ),
        ),
      if (_needsBaseUrl(_provider))
        SettingsRow(
          label: 'Base URL',
          trailing: SettingsField(
              controller: _baseUrl,
              width: 220,
              mono: true,
              hint: 'https://api.example.com/v1'),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseH = kMobile ? 16.0 : (widget.embedded ? 24.0 : 20.0);
        final extra = kMobile
            ? 0.0
            : ((constraints.maxWidth - 768) / 2).clamp(0.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(
              baseH + extra, kMobile ? 4 : 8, baseH + extra, 24),
          children: [
            header,
            SettingsGroup(header: 'Model', children: [
              if (!_isEdit)
                SettingsRow(
                  label: 'Name',
                  trailing: SettingsField(
                      controller: _name,
                      width: 220,
                      hint: 'Defaults to the provider',
                      onChanged: (_) => setState(() {})),
                ),
              SettingsRow(
                label: 'Provider',
                trailing: _isEdit
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        ProviderLogo(_provider, size: 12),
                        const SizedBox(width: 6),
                        Text(_providerLabel(_provider),
                            style: sans(kMobile ? 15 : 12.5,
                                color: AppColors.fg3)),
                      ])
                    : providerPicker(),
              ),
              SettingsRow(
                label: 'Model',
                trailing: SettingsField(
                  controller: _model,
                  width: kMobile ? 210 : 240,
                  mono: !kMobile,
                  onChanged: (_) {
                    setState(() {});
                    _scheduleReasoning();
                  },
                  hint: _isChatgpt
                      ? 'gpt-5.1-codex'
                      : _isClaudeCode
                          ? 'sonnet'
                          : _isAntigravity
                              ? 'gemini-3.8-flash-high'
                              : 'claude-sonnet-4.5',
                  suffix: _loadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: Center(child: Spinner(size: 12)))
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _busy ? null : _browseModels,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: AppIcon(
                              _showModelBrowser ? 'x' : 'chevrons-up-down',
                              size: kMobile ? 14 : 13,
                              color: AppColors.fg4,
                            ),
                          ),
                        ),
                ),
              ),
              if (_showModelBrowser && _catalogModels != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _inlineModelBrowser(),
                ),
              SettingsRow(
                label: effortLabel,
                trailing: _effortAdjustable
                    ? SettingsPopup<String>(
                        label: _effortItems
                                .where((i) => i.$1 == _effort)
                                .firstOrNull
                                ?.$2 ??
                            'Default',
                        items: _effortItems,
                        selected: _effort,
                        onSelected: (v) => setState(() => _effort = v),
                      )
                    : Text(
                        _reasoning?['control'] == 'model'
                            ? 'Set by the model'
                            : 'Not adjustable',
                        style: sans(kMobile ? 15 : 12.5, color: AppColors.fg3)),
              ),
            ]),
            if (_modelHint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
                child: Text(_modelHint!,
                    style: sans(12, height: 1.4, color: AppColors.fg4)),
              ),
            SettingsGroup(header: 'Context', children: [
              SettingsRow(
                label: 'Context window',
                sub: 'Tokens. Blank keeps the default.',
                trailing: SettingsField(
                    controller: _ctx,
                    width: 150,
                    mono: true,
                    number: true,
                    hint: '200000'),
              ),
              SettingsRow(
                label: 'Compact at',
                sub: 'History is summarised when the window is this full.',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: kMobile ? 110 : 160,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.surface3,
                        thumbColor: AppColors.fg1,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: compact.toDouble(),
                        min: 10,
                        max: 100,
                        divisions: 18,
                        onChanged: (v) =>
                            setState(() => _compact.text = '${v.round()}'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('$compact%',
                        textAlign: TextAlign.right,
                        style: sans(kMobile ? 15 : 12.5, color: AppColors.fg2)),
                  ),
                ]),
              ),
              if (_usesOpenAiAdapter(_provider))
                SettingsRow(
                  label: 'Stream responses',
                  sub: 'For models that return nothing otherwise.',
                  trailing: SettingsSwitch(
                      value: _stream,
                      onChanged: (v) => setState(() => _stream = v)),
                ),
            ]),
            SettingsGroup(
              header: 'Connection',
              footer: 'Keys stay on the machine running snippet.',
              children: connection,
            ),
            SettingsGroup(header: 'Options', children: [
              SettingsRow(
                label: 'Supports images',
                sub: 'Send screenshots and diagrams to this model.',
                trailing: SettingsSwitch(
                    value: _images,
                    onChanged: (v) => setState(() => _images = v)),
              ),
              if (_isXai)
                SettingsRow(
                  label: 'X search',
                  sub: 'Let Grok search X with xAI’s server-side tool.',
                  trailing: SettingsSwitch(
                      value: _xSearch,
                      onChanged: (v) => setState(() => _xSearch = v)),
                ),
              SettingsRow(
                label: 'Use for new sessions',
                sub: 'Make this the active profile.',
                trailing: SettingsSwitch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v)),
              ),
            ]),
            if (_isEdit && widget.onDelete != null && kMobile)
              SettingsGroup(children: [
                SettingsRow(
                    label: 'Delete profile',
                    danger: true,
                    onTap: widget.onDelete),
              ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(_error!, style: sans(12, color: AppColors.danger)),
              ),
          ],
        );
      },
    );
  }
}

/// Searchable list over the provider's live model catalog. Rows show the raw
/// model ID (that's what gets sent) with capability metadata as the subtitle.
class _ModelPickerSheet extends StatefulWidget {
  final List<CatalogModel> models;
  const _ModelPickerSheet({required this.models});
  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    // AppField has no onChanged — rebuild the filtered list as the user types.
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final q = _query.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.models
        : widget.models
            .where((m) =>
                m.id.toLowerCase().contains(q) ||
                (m.displayName?.toLowerCase().contains(q) ?? false))
            .toList();
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom) *
                  0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            // Grab handle: the only cue that this is a sheet rather than a
            // dialog, so it stays.
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(R.xs))),
            ),
            // Header: title, count, close. The old sheet had no title at all --
            // just a grab handle and a labelled field, so nothing named the
            // surface or offered a visible way out.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                AppIcon('cpu', size: 16, color: AppColors.fg2),
                const SizedBox(width: 9),
                Text('Inference profiles', style: TS.sectionTitle()),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text('${widget.models.length}',
                      style: mono(10, color: AppColors.fg3)),
                ),
                const Spacer(),
                IconBtn('x',
                    size: 32,
                    iconSize: 16,
                    tooltip: 'Close',
                    onTap: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppField(
                controller: _query,
                mono: true,
                hint: 'Search profiles…',
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  // An empty filter result used to render as a blank sheet --
                  // indistinguishable from "still loading".
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                      child: Column(children: [
                        AppIcon('search', size: 18, color: AppColors.fg4),
                        const SizedBox(height: 9),
                        Text('No profile matches “${_query.text.trim()}”',
                            textAlign: TextAlign.center, style: TS.meta()),
                      ]),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _modelRow(ctx, filtered[i]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  /// One model row: the ID is what actually gets sent, so it leads; everything
  /// else is supporting detail on the second line.
  Widget _modelRow(BuildContext ctx, CatalogModel m) {
    final meta = <String>[
      if (m.efforts != null)
        m.efforts!.isEmpty
            ? 'no effort control'
            : 'effort: ${m.efforts!.join('/')}'
      else if (m.reasoning != null)
        m.reasoning! ? 'reasoning' : 'no reasoning',
      if ((m.contextWindow ?? 0) > 0)
        InferenceProfileEditorState._fmtCtx(m.contextWindow!),
    ];
    final subtitle = [
      if (m.displayName != null) m.displayName!,
      ...meta,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          hoverColor: AppColors.surface2,
          onTap: () => Navigator.pop(ctx, m),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(13, color: AppColors.fg1)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.caption()),
                      ],
                    ]),
              ),
              const SizedBox(width: 8),
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Subscription sign-in (ChatGPT / xAI) via the daemon's device-code flow:
/// shows the code + verification URL, then polls until the token is stored.
class _CliAgentStatus extends StatefulWidget {
  final DaemonClient client;
  final String provider;
  const _CliAgentStatus(
      {super.key, required this.client, required this.provider});
  @override
  State<_CliAgentStatus> createState() => _CliAgentStatusState();
}

class _CliAgentStatusState extends State<_CliAgentStatus> {
  Map<String, dynamic>? _status;
  String? _err;
  bool _loading = true;

  bool get _claude => widget.provider == 'claude-code';
  String get _label => _claude ? 'Claude Code' : 'Antigravity';
  String get _command => _claude ? 'claude' : 'agy';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final s = await widget.client.cliAgentStatus(widget.provider);
      if (mounted)
        setState(() {
          _status = s;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _err = '$e';
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final blurb = Text(
        'Runs the $_label CLI installed on the machine running snippet, signed in the way it already is — no API key. Snippet supplies the prompt, its tools and approvals.',
        style: sans(12, height: 1.4, color: AppColors.fg3));
    final recheck = GestureDetector(
        onTap: _loading ? null : _refresh,
        child: Text(_loading ? 'Checking…' : 'Recheck', style: TS.meta()));
    final s = _status;
    final installed = s?['installed'] == true;
    final signedIn = s?['signed_in'] == true;
    Widget state;
    if (s == null) {
      state = Row(children: [
        Expanded(
            child: Text(_err ?? 'Checking this machine…',
                style: sans(12,
                    color: _err == null ? AppColors.fg3 : AppColors.danger))),
        recheck,
      ]);
    } else {
      final version = s['version'] as String?;
      final account = s['account'] as String?;
      final (icon, color, title, hint) = !installed
          ? (
              'alert-triangle',
              AppColors.danger,
              '$_label isn\'t installed',
              'Install the $_label CLI (`$_command`) on the machine running snippet, then recheck.'
            )
          : !signedIn
              ? (
                  'alert-triangle',
                  AppColors.run,
                  '$_label isn\'t signed in',
                  'Run `$_command` once on that machine and sign in, then recheck.'
                )
              : (
                  'check',
                  AppColors.ok,
                  '$_label ${version ?? ''} · signed in${account == null ? '' : ' ($account)'}',
                  s['path'] as String? ?? ''
                );
      state = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIcon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title.trim(),
                  style: sans(13, color: AppColors.fg2),
                  overflow: TextOverflow.ellipsis)),
          recheck,
        ]),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(hint,
                  style: installed && signedIn
                      ? mono(11, color: AppColors.fg4)
                      : sans(12, height: 1.4, color: AppColors.fg3))),
        ],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      state,
      const SizedBox(height: 10),
      blurb,
    ]);
  }
}

class _SubSignIn extends StatefulWidget {
  final DaemonClient client;
  final String signedInLabel;
  final String blurb;
  final String buttonLabel;
  final Future<bool> Function(DaemonClient) signedIn;
  final Future<({String userCode, String verificationUri})> Function(
      DaemonClient) begin;
  final Future<void> Function(DaemonClient) signOut;
  const _SubSignIn({
    super.key,
    required this.client,
    required this.signedInLabel,
    required this.blurb,
    required this.buttonLabel,
    required this.signedIn,
    required this.begin,
    required this.signOut,
  });
  @override
  State<_SubSignIn> createState() => _SubSignInState();
}

class _SubSignInState extends State<_SubSignIn> {
  bool _loading = true;
  bool _signedIn = false;
  String? _code;
  String? _url;
  Timer? _poll;
  String? _err;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final on = await widget.signedIn(widget.client);
    if (mounted)
      setState(() {
        _signedIn = on;
        _loading = false;
      });
  }

  Future<void> _begin() async {
    setState(() {
      _err = null;
      _loading = true;
    });
    try {
      final d = await widget.begin(widget.client);
      if (!mounted) return;
      setState(() {
        _code = d.userCode;
        _url = d.verificationUri;
        _loading = false;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (await widget.signedIn(widget.client)) {
          _poll?.cancel();
          if (mounted)
            setState(() {
              _signedIn = true;
              _code = null;
              _url = null;
            });
        }
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _err = '$e';
          _loading = false;
        });
    }
  }

  Future<void> _signOut() async {
    await widget.signOut(widget.client);
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (_loading && _code == null) {
      return const SizedBox(height: 20);
    }
    if (_signedIn) {
      return Row(children: [
        AppIcon('check', size: 16, color: AppColors.ok),
        const SizedBox(width: 8),
        Text(widget.signedInLabel, style: sans(13, color: AppColors.fg2)),
        const Spacer(),
        GestureDetector(
            onTap: _signOut, child: Text('Sign out', style: TS.meta())),
      ]);
    }
    if (_code != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Open this URL and enter the code:',
            style: sans(12, height: 1.4, color: AppColors.fg2)),
        const SizedBox(height: 8),
        SelectableText(_url ?? '', style: mono(12, color: AppColors.accent)),
        const SizedBox(height: 8),
        Row(children: [
          Text(_code!, style: mono(18, weight: W.label, color: AppColors.fg1)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: _code!)),
            child: Text('copy', style: TS.meta()),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Waiting for approval…', style: TS.meta()),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.blurb, style: sans(12, height: 1.4, color: AppColors.fg3)),
      const SizedBox(height: 10),
      Btn(widget.buttonLabel, icon: 'key', small: true, onTap: _begin),
      if (_err != null) ...[
        SizedBox(height: 8),
        Text(_err!, style: sans(12, color: AppColors.danger))
      ],
    ]);
  }
}
