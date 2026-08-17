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
  const ModelsScreen({super.key, required this.client, this.onClose});
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
    final saved = await presentScreen<bool>(
      context,
      builder: (_, close) =>
          ModelEditorScreen(client: widget.client, existing: p, onClose: close),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Models',
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(
            child: FutureBuilder<ServerConfig>(
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    if (profiles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                        child: Text(
                            'No model configured. Add a profile with an API key before starting a session.',
                            style: sans(13, height: 1.4, color: AppColors.fg3)),
                      ),
                    ...profiles
                        .map((p) => _profileCard(p, snap.data?.delegate)),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _edit(null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          AppIcon('plus', size: 16, color: AppColors.fg3),
                          const SizedBox(width: 12),
                          Text('Add model',
                              style: sans(14, color: AppColors.fg2)),
                        ]),
                      ),
                    ),
                    if (profiles.length > 1) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          snap.data?.delegate == null ||
                                  snap.data!.delegate!.isEmpty
                              ? 'Delegated lanes use the active model. Tap ⋮ on a profile to run them on a different one.'
                              : 'Delegated lanes run on “${snap.data!.delegate}”.',
                          style: mono(11, height: 1.4, color: AppColors.fg3),
                        ),
                      ),
                    ],
                  ],
                );
                // Don't stretch full-width on desktop — keep a readable column.
                return kMobile
                    ? list
                    : Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: list));
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _profileCard(ModelProfile p, String? delegate) {
    final isDelegate =
        delegate != null && delegate.isNotEmpty && delegate == p.name;
    return InkWell(
      onTap: p.usable
          ? () => _run(() => widget.client.setActiveProfile(p.name), 'activate')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          AppIcon('cpu',
              size: 16, color: p.active ? AppColors.accent : AppColors.fg3),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, color: AppColors.fg1))),
                if (p.active) ...[
                  const SizedBox(width: 8),
                  Text('active', style: sans(11, color: AppColors.accent))
                ],
                if (isDelegate) ...[
                  const SizedBox(width: 8),
                  Text('delegate', style: sans(11, color: AppColors.run))
                ],
                if (!p.usable) ...[const SizedBox(width: 8), const WarnChip()],
              ]),
              const SizedBox(height: 2),
              Text('${p.provider} · ${p.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(11.5, color: AppColors.fg4)),
            ]),
          ),
          IconBtn('edit', size: 32, iconSize: 16, onTap: () => _edit(p)),
          _overflowMenu(p, isDelegate),
        ]),
      ),
    );
  }

  Widget _overflowMenu(ModelProfile p, bool isDelegate) =>
      PopupMenuButton<String>(
        tooltip: '',
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border2),
        ),
        icon: AppIcon('more-vertical', size: 16, color: AppColors.fg3),
        onSelected: (v) {
          switch (v) {
            case 'delegate':
              _run(() => widget.client.setDelegateProfile(p.name),
                  'set delegate');
              break;
            case 'undelegate':
              _run(() => widget.client.setDelegateProfile(null),
                  'clear delegate');
              break;
            case 'delete':
              _run(() => widget.client.deleteProfile(p.name), 'delete');
              break;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: isDelegate ? 'undelegate' : 'delegate',
            child: Text(
              isDelegate
                  ? 'Stop delegating to this'
                  : 'Use for delegated lanes',
              style: sans(13, color: AppColors.fg1),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete profile',
                style: sans(13, color: AppColors.danger)),
          ),
        ],
      );
}
