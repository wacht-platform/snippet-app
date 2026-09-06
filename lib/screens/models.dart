import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
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
    final saved = await presentScreen<bool>(
      context,
      style: PanelStyle.drawer,
      builder: (_, close) => ModelEditorScreen(
          client: widget.client,
          existing: p,
          delegateName: delegate,
          onClose: close),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
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
              widget.embedded ? 18 : 16, widget.embedded ? 12 : 14, 16, 24),
          children: [
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                child: Text(
                    'No model configured. Add a profile with an API key before starting a session.',
                    style: sans(13, height: 1.4, color: AppColors.fg3)),
              ),
            ...profiles.map((p) => _profileCard(p, snap.data?.delegate)),
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _edit(null),
                borderRadius: BorderRadius.circular(R.md),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(children: [
                    AppIcon('plus', size: 16, color: AppColors.fg3),
                    const SizedBox(width: 12),
                    Text('Add model', style: sans(14, color: AppColors.fg2)),
                  ]),
                ),
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _edit(p),
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
            child: Row(children: [
              AppIcon('cpu',
                  size: 16, color: p.active ? AppColors.accent : AppColors.fg3),
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
                                style: sans(14, color: AppColors.fg1))),
                        if (p.active) ...[
                          const SizedBox(width: 8),
                          Text('active',
                              style: sans(11, color: AppColors.accent))
                        ],
                        if (isDelegate) ...[
                          const SizedBox(width: 8),
                          Text('delegate',
                              style: sans(11, color: AppColors.run))
                        ],
                        if (!p.usable) ...[
                          const SizedBox(width: 8),
                          const WarnChip()
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text('${p.provider} · ${p.model}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(11.5, color: AppColors.fg4)),
                    ]),
              ),
              _overflowMenu(p),
            ]),
          ),
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
