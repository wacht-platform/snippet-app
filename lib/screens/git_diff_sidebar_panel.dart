import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// Git Diff sidebar panel:
/// - Header: `⌄ 🗐 GIT DIFF` with branch and refresh icons
/// - Project card: `Workspace • 0 changed ⌄`
/// - When clean: `No changes`, `Last updated just now`, `Refresh` button
/// - When dirty: list of modified/added files
class GitDiffSidebarPanel extends StatefulWidget {
  const GitDiffSidebarPanel({
    super.key,
    required this.client,
    required this.workspacePath,
    this.sessionId,
  });

  final DaemonClient client;
  final String workspacePath;
  final String? sessionId;

  @override
  State<GitDiffSidebarPanel> createState() => _GitDiffSidebarPanelState();
}

class _GitDiffSidebarPanelState extends State<GitDiffSidebarPanel> {
  GitStatus? _status;
  bool _loading = true;
  String? _error;
  DateTime _lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.client.gitStatus(widget.sessionId ?? '');
      if (!mounted) return;
      setState(() {
        _status = res;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final repoName = widget.workspacePath.isEmpty
        ? 'Workspace'
        : lastPathSegment(widget.workspacePath, ifEmpty: 'Workspace');
    final files = _status?.files ?? const [];
    final changeCount = files.length;
    final isClean = files.isEmpty;

    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
        children: [
          ShellSectionHeader(
            label: 'Git Diff',
            expanded: true,
            onToggle: () {},
            actions: [
              ShellSectionAction(
                icon: 'git-branch',
                tooltip: _status?.branch ?? 'Branch',
                onTap: () {},
              ),
              ShellSectionAction(
                icon: 'refresh',
                tooltip: 'Refresh diff',
                onTap: refresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Project card with change count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                AppIcon('folder', size: 14, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$repoName • $changeCount changed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, weight: W.label, color: AppColors.fg1),
                  ),
                ),
                AppIcon('chevron-down', size: 12, color: AppColors.fg4),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_loading && _status == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!,
                      style: sans(12, color: AppColors.danger),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Btn('Retry', small: true, onTap: refresh),
                ],
              ),
            )
          else if (isClean)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon('git-branch', size: 36, color: AppColors.fg4),
                  const SizedBox(height: 12),
                  Text(
                    'No changes',
                    style: sans(14, weight: W.label, color: AppColors.fg2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated ${_timeAgo(_lastUpdated)}',
                    style: sans(11.5, color: AppColors.fg4),
                  ),
                  const SizedBox(height: 16),
                  Btn('Refresh', small: true, icon: 'refresh', onTap: refresh),
                ],
              ),
            )
          else
            for (final f in files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: ShellNavRow(
                  id: f.path,
                  label: f.path,
                  icon: f.staged ? 'check' : 'edit',
                  tone: f.staged ? ShellTone.review : ShellTone.chat,
                  onTap: () {},
                ),
              ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
