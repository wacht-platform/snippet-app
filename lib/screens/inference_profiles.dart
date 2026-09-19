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
  final ValueChanged<bool>? onEditingChanged;

  const InferenceProfilesScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
    this.onBack,
    this.onEditingChanged,
  });
  @override
  State<InferenceProfilesScreen> createState() =>
      InferenceProfilesScreenState();
}

class InferenceProfilesScreenState extends State<InferenceProfilesScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<ServerConfig> _future;
  bool _inEditor = false;
  InferenceProfile? _editProfile;
  String? _delegate;

  void addProfile() => _edit(null);
  bool get inEditor => _inEditor;

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
    widget.onEditingChanged?.call(true);
  }

  void _closeEditor({bool saved = false}) {
    if (!mounted) return;
    setState(() {
      _inEditor = false;
      _editProfile = null;
    });
    widget.onEditingChanged?.call(false);
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
          Padding(
            padding: EdgeInsets.fromLTRB(widget.embedded ? 18 : 4, 6, 24, 6),
            child: NavBackRow(
              title: _editProfile == null ? 'Add profile' : 'Edit profile',
              onBack: _closeEditor,
            ),
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
          physics: (widget.embedded && kMobile)
              ? const NeverScrollableScrollPhysics()
              : null,
          shrinkWrap: (widget.embedded && kMobile),
          padding: EdgeInsets.fromLTRB(
              (widget.embedded && kMobile) ? 0 : 24,
              (widget.embedded && kMobile) ? 0 : (widget.embedded ? 4 : 20),
              (widget.embedded && kMobile) ? 0 : 24,
              28),
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
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon('ai-chip', size: 30, color: AppColors.fg4),
                      const SizedBox(height: 12),
                      Text('No inference profiles configured',
                          style: sans(14, weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 6),
                      Text(
                        'Add an API key or local model provider to start sessions.',
                        textAlign: TextAlign.center,
                        style: sans(12, color: AppColors.fg3),
                      ),
                      const SizedBox(height: 16),
                      Btn('Add profile',
                          icon: 'plus',
                          small: true,
                          onTap: () => _edit(null)),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < profiles.length; i++) ...[
                    _profileCard(profiles[i], cfg?.delegate),
                    if (i < profiles.length - 1)
                      Divider(
                          height: 1,
                          color: AppColors.border.withValues(alpha: 0.4)),
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
    final compact = kMobile && widget.embedded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _edit(p),
        borderRadius: BorderRadius.circular(compact ? R.sm : R.md),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 8,
              vertical: compact ? 6 : 11),
          child: Row(children: [
            AppIcon('ai-chip',
                size: compact ? 18 : 20,
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
                          style: sans(compact ? 13.5 : 13.5,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                    if (p.active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('active',
                            style: sans(10,
                                weight: W.label, color: AppColors.accent)),
                      ),
                    ],
                    if (isDelegate) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('delegate',
                            style: sans(10,
                                weight: W.label, color: AppColors.fg2)),
                      ),
                    ],
                    if (!p.usable) ...[
                      const SizedBox(width: 6),
                      const WarnChip(),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text('${p.provider} · ${p.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11.5, color: AppColors.fg3)),
                ],
              ),
            ),
            _deleteProfileButton(p),
            const SizedBox(width: 4),
            AppIcon('chevron-right', size: 14, color: AppColors.fg4),
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
