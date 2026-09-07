import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'model_editor.dart';

class ModelsScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;

  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;
  const ModelsScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
  });
  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  late Future<ServerConfig> _future;
  bool _inEditor = false;
  ModelProfile? _editProfile;
  String? _delegate;

  @override
  void initState() {
    super.initState();
    _future = widget.client.getConfig();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = widget.client.getConfig();
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

  Future<void> _edit(ModelProfile? p) async {
    String? delegate;
    try {
      delegate = (await widget.client.getConfig()).delegate;
    } catch (_) {}
    if (!mounted) return;
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
    Theme.of(context); // Rebuild on theme change
    if (_inEditor) {
      return ModelEditorScreen(
        client: widget.client,
        existing: _editProfile,
        delegateName: _delegate,
        embedded: widget.embedded,
        onClose: () => _closeEditor(),
        onSaved: () => _closeEditor(saved: true),
      );
    }
    final body = FutureBuilder<ServerConfig>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.fg3)));
        }
        final profiles = snap.data?.profiles ?? const [];
        final list = ListView(
          padding: EdgeInsets.fromLTRB(
              widget.embedded ? 16 : 16, widget.embedded ? 14 : 14, 16, 20),
          children: [
            Text('Models',
                style: sans(widget.embedded ? 14 : 18,
                    weight: FontWeight.w600, color: AppColors.fg1)),
            const SizedBox(height: 3),
            Text('Choose the model used for new sessions and delegated work.',
                style:
                    sans(widget.embedded ? 11.5 : 12.5, color: AppColors.fg3)),
            SizedBox(height: widget.embedded ? 12 : 16),
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                child: Text(
                    'No model configured. Add a profile with an API key before starting a session.',
                    style: sans(widget.embedded ? 12 : 13,
                        height: 1.4, color: AppColors.fg3)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                  borderRadius:
                      BorderRadius.circular(widget.embedded ? R.sm : R.md),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < profiles.length; i++) ...[
                      _profileCard(profiles[i], snap.data?.delegate),
                      if (i < profiles.length - 1)
                        Divider(height: 1, color: AppColors.border),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Btn('Add model',
                icon: 'plus', small: true, onTap: () => _edit(null)),
          ],
        );
        if (widget.embedded || kMobile) return list;
        return Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680), child: list));
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Models',
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(child: body),
        ]),
      ),
    );
  }

  Widget _profileCard(ModelProfile p, String? delegate) {
    final isDelegate =
        delegate != null && delegate.isNotEmpty && delegate == p.name;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _edit(p),
        borderRadius: BorderRadius.circular(widget.embedded ? R.sm : R.md),
        child: Padding(
          padding: EdgeInsets.fromLTRB(widget.embedded ? 10 : 14,
              widget.embedded ? 8 : 12, 6, widget.embedded ? 8 : 12),
          child: Row(children: [
            AppIcon('cpu',
                size: widget.embedded ? 14 : 16,
                color: p.active ? AppColors.accent : AppColors.fg3),
            SizedBox(width: widget.embedded ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(widget.embedded ? 12.5 : 14,
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
                      style: mono(widget.embedded ? 10.5 : 11.5,
                          color: AppColors.fg4)),
                ],
              ),
            ),
            _overflowMenu(p),
          ]),
        ),
      ),
    );
  }

  Widget _overflowMenu(ModelProfile p) => PopupMenuButton<String>(
        tooltip: '',
        color: AppColors.surface1,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        shape: appMenuShape,
        icon: AppIcon('more-vertical', size: 16, color: AppColors.fg3),
        onSelected: (v) {
          if (v == 'delete') {
            _run(() => widget.client.deleteProfile(p.name), 'delete');
          }
        },
        itemBuilder: (_) => [
          appMenuItem(value: 'delete', label: 'Delete profile', danger: true),
        ],
      );
}
