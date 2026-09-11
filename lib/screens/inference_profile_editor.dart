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
  ('opencode-zen', 'OpenCode Zen'),
  ('opencode-go', 'OpenCode Go'),
  ('xai', 'xAI (Grok)'),
  ('chatgpt', 'ChatGPT'),
];

String _providerLabel(String p) =>
    _providers.where((e) => e.$1 == p).map((e) => e.$2).firstOrNull ?? p;

bool _needsBaseUrl(String p) =>
    p == 'openai-compatible' || p == 'anthropic-compatible';
bool _defaultImages(String p) =>
    p == 'anthropic' || p == 'gemini' || p == 'openai' || p == 'chatgpt';
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
  final String? delegateName;

  /// Skip Scaffold / app bar and fill the parent (settings Models pane).
  final bool embedded;

  /// Dismiss when hosted in a responsive panel (desktop drawer / phone full-screen).
  final VoidCallback? onClose;

  /// Called after a successful save, before [onClose].
  final VoidCallback? onSaved;
  const InferenceProfileEditor(
      {super.key,
      required this.client,
      this.existing,
      this.delegateName,
      this.embedded = false,
      this.onClose,
      this.onSaved});
  @override
  State<InferenceProfileEditor> createState() => _InferenceProfileEditorState();
}

class _InferenceProfileEditorState extends State<InferenceProfileEditor> {
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
  bool _xSearch = false;
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
    _xSearch = e?.xSearch ?? false;
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
        xSearch: _isXai ? _xSearch : null,
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // include the current provider as a pill even if it's outside the standard list (e.g. chatgpt)
    final pills = [..._providers];
    if (!pills.any((p) => p.$1 == _provider))
      pills.insert(0, (_provider, _provider));
    final title = _isEdit ? 'Edit profile' : 'Add profile';
    final form = Expanded(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            widget.embedded ? 20 : 16, widget.embedded ? 8 : 16, 20, 24),
        children: [
          Text('Provider',
              style: sans(12, weight: FontWeight.w500, color: AppColors.fg2)),
          const SizedBox(height: 7),
          if (_isEdit)
            Text(_providerLabel(_provider),
                style: sans(15, color: AppColors.fg1))
          else
            Pills<String>(
              items: pills,
              selected: _provider,
              onSelect: (val) => setState(() {
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
                    hint: _isChatgpt ? 'gpt-5.1-codex' : 'claude-sonnet-4.5')),
            const SizedBox(width: 8),
            IconBtn('list',
                size: 44, iconSize: 18, onTap: _busy ? null : _browseModels),
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
              style: sans(12, weight: FontWeight.w500, color: AppColors.fg2)),
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
            _SubSignIn(
              client: widget.client,
              signedInLabel: 'Signed in to ChatGPT',
              blurb:
                  'ChatGPT uses your Plus / Pro / Team subscription — no API key.',
              buttonLabel: 'Sign in with ChatGPT',
              signedIn: (c) => c.chatgptSignedIn(),
              begin: (c) => c.chatgptLoginBegin(),
              signOut: (c) => c.chatgptLogout(),
            )
          else if (_isXai)
            _SubSignIn(
              client: widget.client,
              signedInLabel: 'Signed in to xAI',
              blurb:
                  'Grok uses your SuperGrok / X Premium subscription — no API key.',
              buttonLabel: 'Sign in with SuperGrok / X Premium',
              signedIn: (c) => c.xaiSignedIn(),
              begin: (c) => c.xaiLoginBegin(),
              signOut: (c) => c.xaiLogout(),
            )
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
          if (_isXai) ...[
            const SizedBox(height: 8),
            AppToggle(
                on: _xSearch,
                onChanged: (v) => setState(() => _xSearch = v),
                label: 'X search',
                sub:
                    'Let Grok search X via xAI’s server-side tool (Responses API)'),
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
              sub: 'Lanes run on this profile instead of the active model'),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: sans(12, color: AppColors.danger)),
          ],
        ],
      ),
    );
    final footer = Container(
      padding: EdgeInsets.fromLTRB(
          widget.embedded ? 16 : 16,
          10,
          widget.embedded ? 16 : 16,
          widget.embedded ? 12 : 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border))),
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
      if (!widget.embedded) SnAppBar(title: title, onBack: _dismiss),
      form,
      footer,
    ]);
    if (widget.embedded) return body;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
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
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Header: title, count, close. The old sheet had no title at all --
            // just a grab handle and a labelled field, so nothing named the
            // surface or offered a visible way out.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                AppIcon('cpu', size: 16, color: AppColors.fg2),
                const SizedBox(width: 9),
                Text('Inference profiles',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('${widget.models.length}',
                      style: mono(10.5, color: AppColors.fg3)),
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
                            textAlign: TextAlign.center,
                            style: sans(12.5, color: AppColors.fg3)),
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
        _InferenceProfileEditorState._fmtCtx(m.contextWindow!),
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
                            style: sans(11.5, color: AppColors.fg4)),
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
              style: mono(18, weight: FontWeight.w500, color: AppColors.fg1)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: _code!)),
            child: Text('copy', style: sans(12, color: AppColors.fg3)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Waiting for approval…', style: sans(12, color: AppColors.fg3)),
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
