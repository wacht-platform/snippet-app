import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

// (value sent to the daemon, label shown in the pill)
const _providers = [
  ('anthropic', 'Anthropic'),
  ('openai', 'OpenAI'),
  ('gemini', 'Google'),
  ('openai-compatible', 'OpenAI-compatible'),
  ('anthropic-compatible', 'Anthropic-compatible'),
  ('openrouter', 'OpenRouter'),
  ('xai', 'xAI (Grok)'),
];

bool _needsBaseUrl(String p) =>
    p == 'openai-compatible' || p == 'anthropic-compatible';
bool _defaultImages(String p) =>
    p == 'anthropic' || p == 'gemini' || p == 'openai' || p == 'chatgpt';
// Providers that go through the OpenAI-compatible adapter, where `stream` applies.
bool _usesOpenAiAdapter(String p) =>
    p == 'openai' || p == 'openai-compatible' || p == 'openrouter';

class ModelEditorScreen extends StatefulWidget {
  final DaemonClient client;
  final ModelProfile? existing;
  final String? delegateName;

  /// Dismiss when hosted in a responsive panel (desktop drawer / phone full-screen).
  final VoidCallback? onClose;
  const ModelEditorScreen(
      {super.key,
      required this.client,
      this.existing,
      this.delegateName,
      this.onClose});
  @override
  State<ModelEditorScreen> createState() => _ModelEditorScreenState();
}

class _ModelEditorScreenState extends State<ModelEditorScreen> {
  late String _provider;
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _ctx;
  final _key = TextEditingController();
  bool _showKey = false;
  late bool _images;
  bool _active = false;
  bool _delegate = false;
  bool _stream = false;
  String _effort = ''; // '' = provider default
  bool _busy = false;
  String? _error;

  /// Capability line under the Model field, from the provider's live catalog
  /// (effort tiers on Anthropic, reasoning yes/no on OpenRouter, context size).
  String? _modelHint;

  bool get _isEdit => widget.existing != null;
  bool get _isChatgpt => _provider == 'chatgpt';
  bool get _isXai => _provider == 'xai';

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
    // Editing keeps the profile's actual flag — falling back to the provider
    // default silently reset it on every unrelated edit.
    _images = e?.supportsImages ?? _defaultImages(_provider);
    _active = e?.active ?? !_isEdit;
    _delegate = e != null &&
        (widget.delegateName ?? '').isNotEmpty &&
        widget.delegateName == e.name;
    _stream = e?.stream ?? false;
    _effort = e?.reasoningEffort ?? '';
    // The Save button's enabled state depends on this field; without a listener
    // typing never rebuilt, leaving Save stuck disabled on desktop.
    _model.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _ctx.dispose();
    _key.dispose();
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
    setState(() => _error = null);
    final List<CatalogModel> models;
    try {
      models = await widget.client.providerModels(
        name: widget.existing?.name,
        provider: _provider,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _key.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    if (!mounted) return;
    if (models.isEmpty) {
      setState(() => _error =
          'The provider returned no models (this provider may not have a catalog).');
      return;
    }
    final picked = await showModalBottomSheet<CatalogModel>(
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

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_model.text.trim().isEmpty) throw 'Model is required.';
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
        reasoningEffort: _effort,
        supportsImages: _images,
        contextWindow: int.tryParse(_ctx.text.trim()),
        stream: _stream,
        setActive: _active,
      );
      final savedName = _isEdit
          ? widget.existing!.name
          : (_name.text.trim().isEmpty
              ? _model.text.trim()
              : _name.text.trim());
      if (_delegate) {
        await widget.client.setDelegateProfile(savedName);
      } else if (widget.delegateName == savedName) {
        await widget.client.setDelegateProfile(null);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // include the current provider as a pill even if it's outside the standard list (e.g. chatgpt)
    final pills = [..._providers];
    if (!pills.any((p) => p.$1 == _provider))
      pills.insert(0, (_provider, _provider));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: _isEdit ? 'Edit model' : 'Add model',
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Provider',
                    style: sans(12,
                        weight: FontWeight.w500, color: AppColors.fg2)),
                const SizedBox(height: 7),
                Pills<String>(
                  items: pills,
                  selected: _provider,
                  onSelect: _isEdit
                      ? null
                      : (val) => setState(() {
                            _provider = val;
                            _images = _defaultImages(val);
                          }),
                ),
                const SizedBox(height: 16),
                if (!_isEdit) ...[
                  AppField(
                      label: 'Profile name',
                      controller: _name,
                      hint: 'optional — defaults to the provider'),
                  const SizedBox(height: 16),
                ],
                if (_needsBaseUrl(_provider)) ...[
                  AppField(
                      label: 'Base URL',
                      controller: _baseUrl,
                      mono: true,
                      hint: 'https://api.example.com/v1'),
                  const SizedBox(height: 16),
                ],
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: AppField(
                          label: 'Model',
                          controller: _model,
                          mono: true,
                          hint: 'claude-sonnet-4.5')),
                  if (!_isChatgpt) ...[
                    const SizedBox(width: 8),
                    IconBtn('list',
                        size: 44,
                        iconSize: 18,
                        onTap: _busy ? null : _browseModels),
                  ],
                ]),
                if (_modelHint != null) ...[
                  const SizedBox(height: 6),
                  Text(_modelHint!,
                      style: mono(11, height: 1.4, color: AppColors.fg3)),
                ],
                const SizedBox(height: 16),
                AppField(
                  label: 'Context window (tokens)',
                  controller: _ctx,
                  mono: true,
                  keyboardType: TextInputType.number,
                  hint: 'e.g. 200000 — blank keeps the default',
                  helper:
                      'Sets the % context gauge and the point where the agent compacts history.',
                ),
                const SizedBox(height: 16),
                Text('Reasoning effort',
                    style: sans(12,
                        weight: FontWeight.w500, color: AppColors.fg2)),
                const SizedBox(height: 7),
                Pills<String>(
                  items: const [
                    ('', 'Default'),
                    ('off', 'Off'),
                    ('low', 'Low'),
                    ('medium', 'Medium'),
                    ('high', 'High'),
                    ('xhigh', 'X-High'),
                    ('max', 'Max')
                  ],
                  selected: _effort,
                  onSelect: (val) => setState(() => _effort = val),
                ),
                const SizedBox(height: 6),
                Text(
                    "Higher means more thinking — better on hard problems, more tokens. Default uses the provider's own; Off disables reasoning. X-High/Max are the top tiers (gpt-5.1-codex-max, gpt-5.6, Claude). If a model rejects a tier, snippet steps down automatically instead of failing.",
                    style: sans(11.5, height: 1.4, color: AppColors.fg4)),
                const SizedBox(height: 16),
                if (_isChatgpt)
                  Text(
                      'ChatGPT uses the subscription login set up in the TUI — no API key here.',
                      style: sans(12, height: 1.4, color: AppColors.fg3))
                else if (_isXai)
                  _XaiSignIn(client: widget.client)
                else
                  AppField(
                    label: 'API key',
                    controller: _key,
                    mono: true,
                    obscure: !_showKey,
                    icon: 'key',
                    hint: _isEdit && widget.existing!.hasKey
                        ? 'leave blank to keep current key'
                        : 'sk-…',
                    helper:
                        'Stored on the machine running snippet. Never sent to snippet servers.',
                    rightSlot: GestureDetector(
                      onTap: () => setState(() => _showKey = !_showKey),
                      child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Text(_showKey ? 'Hide' : 'Show',
                              style: sans(11, color: AppColors.fg3))),
                    ),
                  ),
                const SizedBox(height: 16),
                AppToggle(
                    on: _images,
                    onChanged: (v) => setState(() => _images = v),
                    label: 'Supports images',
                    sub: 'Send screenshots and diagrams to this model'),
                if (_usesOpenAiAdapter(_provider)) ...[
                  const SizedBox(height: 8),
                  AppToggle(
                      on: _stream,
                      onChanged: (v) => setState(() => _stream = v),
                      label: 'Stream responses',
                      sub:
                          'Turn on for models that return nothing otherwise (e.g. MiniMax on NVIDIA NIM)'),
                ],
                const SizedBox(height: 8),
                AppToggle(
                    on: _active,
                    onChanged: (v) => setState(() => _active = v),
                    label: 'Set as active',
                    sub: 'Use this model for new sessions'),
                const SizedBox(height: 8),
                AppToggle(
                    on: _delegate,
                    onChanged: (v) => setState(() => _delegate = v),
                    label: 'Use for delegated lanes',
                    sub:
                        'Lanes run on this profile instead of the active model'),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: sans(12, color: AppColors.danger)),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Btn('Cancel',
                  variant: BtnVariant.ghost,
                  onTap: widget.onClose ?? () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Expanded(
                  child: Btn(_busy ? 'Saving…' : 'Save',
                      full: true,
                      disabled: _busy || _model.text.trim().isEmpty,
                      onTap: _save)),
            ]),
          ),
        ]),
      ),
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
              maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppField(
                label: 'Models (${widget.models.length})',
                controller: _query,
                mono: true,
                hint: 'filter…',
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final m = filtered[i];
                  final meta = <String>[
                    if (m.efforts != null)
                      m.efforts!.isEmpty
                          ? 'no effort control'
                          : 'effort: ${m.efforts!.join('/')}'
                    else if (m.reasoning != null)
                      m.reasoning! ? 'reasoning' : 'no reasoning',
                    if ((m.contextWindow ?? 0) > 0)
                      _ModelEditorScreenState._fmtCtx(m.contextWindow!),
                  ];
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.id, style: mono(13, color: AppColors.fg1)),
                            if (m.displayName != null || meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (m.displayName != null) m.displayName!,
                                  ...meta
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(11.5, color: AppColors.fg3),
                              ),
                            ],
                          ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// xAI subscription (SuperGrok / X Premium) sign-in via the daemon's device-code
/// flow: shows the code + verification URL, then polls until the token is stored.
class _XaiSignIn extends StatefulWidget {
  final DaemonClient client;
  const _XaiSignIn({required this.client});
  @override
  State<_XaiSignIn> createState() => _XaiSignInState();
}

class _XaiSignInState extends State<_XaiSignIn> {
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
    final on = await widget.client.xaiSignedIn();
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
      final d = await widget.client.xaiLoginBegin();
      if (!mounted) return;
      setState(() {
        _code = d.userCode;
        _url = d.verificationUri;
        _loading = false;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (await widget.client.xaiSignedIn()) {
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
    await widget.client.xaiLogout();
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_loading && _code == null) {
      return SizedBox(
          height: 20,
          width: 20,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: AppColors.fg3));
    }
    if (_signedIn) {
      return Row(children: [
        AppIcon('check', size: 16, color: AppColors.ok),
        const SizedBox(width: 8),
        Text('Signed in to xAI', style: sans(13, color: AppColors.fg2)),
        const Spacer(),
        GestureDetector(
            onTap: _signOut,
            child: Text('Sign out', style: sans(12, color: AppColors.fg3))),
      ]);
    }
    if (_code != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Open this URL and enter the code:',
            style: sans(12.5, height: 1.4, color: AppColors.fg2)),
        const SizedBox(height: 8),
        SelectableText(_url ?? '', style: mono(12.5, color: AppColors.accent)),
        const SizedBox(height: 8),
        Row(children: [
          Text(_code!,
              style: mono(18, weight: FontWeight.w600, color: AppColors.fg1)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: _code!)),
            child: Text('copy', style: sans(12, color: AppColors.fg3)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.fg3)),
          const SizedBox(width: 8),
          Text('Waiting for approval…', style: sans(12, color: AppColors.fg3)),
        ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Grok uses your SuperGrok / X Premium subscription — no API key.',
          style: sans(12, height: 1.4, color: AppColors.fg3)),
      const SizedBox(height: 10),
      Btn('Sign in with SuperGrok / X Premium',
          icon: 'key', small: true, onTap: _begin),
      if (_err != null) ...[
        SizedBox(height: 8),
        Text(_err!, style: sans(12, color: AppColors.danger))
      ],
    ]);
  }
}
