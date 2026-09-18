import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'inference_profile_editor.dart';
import 'shell_nav.dart';

class InferenceProfilesScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;

  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;

  /// Host-supplied back action for [embedded] use. The screen draws its OWN
  /// `NavBackRow`, so exactly one header exists per level — the host drawing it
  /// instead is what produced two stacked back rows in the model editor.
  final VoidCallback? onBack;

  const InferenceProfilesScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
    this.onBack,
  });
  @override
  State<InferenceProfilesScreen> createState() =>
      _InferenceProfilesScreenState();
}

class _InferenceProfilesScreenState extends State<InferenceProfilesScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<ServerConfig> _future;
  bool _inEditor = false;
  InferenceProfile? _editProfile;
  String? _delegate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    modelsRevision.addListener(_onModelsChanged);
    _load();
  }

  void _load({bool force = false}) {
    _future = widget.client.getConfig(force: force);
  }

  void _onModelsChanged() {
    if (!mounted || _inEditor) return;
    setState(() {
      _load(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant InferenceProfilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _load();
    }
  }

  @override
  void dispose() {
    modelsRevision.removeListener(_onModelsChanged);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _load();
    });
  }

  Future<void> _run(Future<void> Function() op, String onError) async {
    try {
      await op();
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$onError: $e', danger: true);
    }
  }

  Future<void> _edit(InferenceProfile? p) async {
    String? delegate;
    try {
      delegate = (await widget.client.getConfig()).delegate;
    } catch (_) {}
    if (!mounted) return;
    if (kMobile && widget.embedded) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => InferenceProfileEditor(
            client: widget.client,
            existing: p,
            delegateName: delegate,
            onClose: () => Navigator.pop(context),
            onSaved: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (saved == true && mounted) _refresh();
      return;
    }
    setState(() {
      _inEditor = true;
      _editProfile = p;
      _delegate = delegate;
    });
  }

  void _closeEditor({bool saved = false}) {
    if (!mounted) return;
    setState(() {
      _inEditor = false;
      _editProfile = null;
    });
    if (saved) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(context); // Rebuild on theme change
    if (_inEditor) {
      final editor = InferenceProfileEditor(
        client: widget.client,
        existing: _editProfile,
        delegateName: _delegate,
        embedded: widget.embedded,
        onClose: () => _closeEditor(),
        onSaved: () => _closeEditor(saved: true),
      );
      if (!widget.embedded) return editor;
      // The editor brings NO header of its own when embedded — THIS level owns
      // it, on both platforms:
      //   phone   → the host draws no header, so this is the only row;
      //   desktop → the chip strip names the SECTION but offers no way back to
      //             the profiles list, so this row is what returns there.
      // Drawing a second row is what produced the stacked-header bug: the host
      // drew one for "Inference profiles" AND the editor drew its own for
      // "Edit profile".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(
            title: _editProfile == null ? 'Add profile' : 'Edit profile',
            onBack: _closeEditor,
          ),
          Expanded(child: editor),
        ],
      );
    }
    final body = FutureBuilder<ServerConfig>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return widget.embedded
              ? const SizedBox.shrink()
              : Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.fg3)));
        }
        final cfg = snap.data;
        final profiles = cfg?.profiles ?? const [];
        final list = ListView(
          physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
          shrinkWrap: widget.embedded,
          padding: EdgeInsets.fromLTRB(
              widget.embedded ? 0 : 16,
              widget.embedded ? 0 : 14,
              widget.embedded ? 0 : 16,
              widget.embedded ? 0 : 20),
          children: [
            if (!widget.embedded) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inference profiles',
                            style: sans(18,
                                weight: FontWeight.w500, color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Text(
                            'Choose the profile used for new sessions and delegated work.',
                            style: sans(12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconBtn('plus',
                      size: 36,
                      iconSize: 17,
                      tooltip: 'Add profile',
                      onTap: () => _edit(null)),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                child: Text(
                    'No inference profile configured. Add one with an API key before starting a session.',
                    style: sans(widget.embedded ? 12 : 13,
                        height: 1.4, color: AppColors.fg3)),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < profiles.length; i++) ...[
                    _profileCard(profiles[i], cfg?.delegate),
                    if (i < profiles.length - 1)
                      Divider(height: 1, color: AppColors.border),
                  ],
                ],
              ),
          ],
        );
        if (widget.embedded || kMobile) return list;
        return Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680), child: list));
      },
    );
    if (widget.embedded) {
      // Desktop dialog pane: host owns navigation (chip strip), so no back row.
      if (widget.onBack == null) return body;
      // Phone drill-down: this level owns the header (see the editor branch).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Inference profiles', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Inference profiles',
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(child: body),
        ]),
      ),
    );
  }

  Widget _profileCard(InferenceProfile p, String? delegate) {
    final isDelegate =
        delegate != null && delegate.isNotEmpty && delegate == p.name;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _edit(p),
        borderRadius: BorderRadius.circular(widget.embedded ? R.sm : R.md),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              0, widget.embedded ? 6 : 12, 0, widget.embedded ? 6 : 12),
          child: Row(children: [
            AppIcon('ai-chip',
                size: widget.embedded ? 18 : 20,
                color: p.active ? AppColors.accent : AppColors.fg3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(widget.embedded ? 14 : 14,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                    if (p.active) ...[
                      const SizedBox(width: 6),
                      Text('active', style: sans(10, color: AppColors.accent)),
                    ],
                    if (isDelegate) ...[
                      const SizedBox(width: 6),
                      Text('delegate', style: sans(10, color: AppColors.run)),
                    ],
                    if (!p.usable) ...[
                      const SizedBox(width: 6),
                      const WarnChip(),
                    ],
                  ]),
                  const SizedBox(height: 1),
                  Text('${p.provider} · ${p.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: AppColors.fg4)),
                ],
              ),
            ),
            _deleteProfileButton(p),
          ]),
        ),
      ),
    );
  }

  Widget _deleteProfileButton(InferenceProfile p) => IconBtn(
        'trash',
        size: 32,
        iconSize: 16,
        tooltip: 'Delete profile',
        onTap: () => _run(() => widget.client.deleteProfile(p.name), 'delete'),
      );
}
