import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// Git Diff sidebar panel.
///
/// Layout follows the measured reference: a 32px branch row directly under the
/// section header, then 26px file rows. The previous version put a bordered
/// card at the top followed by a hard 20px gap and then over-padded rows, which
/// is what made the spacing read as broken — every vertical rhythm in the panel
/// was a different number.
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
    final files = _status?.files ?? const <GitFile>[];
    final branch = _status?.branch ?? '';
    final isClean = files.isEmpty;

    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          ShellSectionHeader(
            label: 'Git Diff',
            expanded: true,
            onToggle: () {},
            actions: [
              ShellSectionAction(
                icon: 'refresh',
                tooltip: 'Refresh diff',
                onTap: refresh,
              ),
            ],
          ),
          _branchRow(repoName, branch, files.length),
          if (_loading && _status == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            _errorState()
          else if (isClean)
            _cleanState()
          else ...[
            const SizedBox(height: 6),
            for (final f in files) _fileRow(f),
          ],
        ],
      ),
    );
  }

  /// Branch + change count on one flat row, matching the file tree's workspace
  /// selector. No card, no border: the surface step alone separates it.
  Widget _branchRow(String repoName, String branch, int changes) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
          child: Row(children: [
            AppIcon('git-branch', size: 14, color: AppColors.fg3),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                branch.isEmpty ? repoName : branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: AppColors.fg1),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              changes == 0 ? 'clean' : '$changes changed',
              style: sans(12, color: AppColors.fg4),
            ),
          ]),
        ),
      );

  Widget _fileRow(GitFile f) => ShellNavRow(
        id: f.path,
        // Just the file name: the row is 26px and a full path ellipsizes to
        // nothing useful. The directory is in the tooltip instead.
        label: lastPathSegment(f.path, ifEmpty: f.path),
        icon: 'file',
        // Monochrome icon; the single-letter status carries the state colour,
        // so colour stays rationed to information.
        tone: ShellTone.neutral,
        onTap: () {},
        trailing: _statusLetter(f),
      );

  /// The git status character, matching how the full Git screen derives it:
  /// the index char for a staged file, `?` for untracked, else the worktree
  /// char. Colour is the only state signal in the panel.
  Widget _statusLetter(GitFile f) {
    final raw = f.staged ? f.x : (f.untracked ? '?' : f.y);
    final letter = raw.trim().isEmpty ? 'M' : raw.trim();
    final color =
        f.staged ? AppColors.ok : (f.untracked ? AppColors.fg3 : AppColors.run);
    return Tooltip(
      message: f.staged ? 'staged' : (f.untracked ? 'untracked' : 'unstaged'),
      child: Text(letter, style: mono(11, weight: W.label, color: color)),
    );
  }

  Widget _cleanState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No changes',
              style: sans(13, weight: W.label, color: AppColors.fg2)),
          const SizedBox(height: 3),
          Text('Last updated ${_timeAgo(_lastUpdated)}',
              style: sans(12, color: AppColors.fg4)),
        ]),
      );

  Widget _errorState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_error!,
              style: sans(12.5, color: AppColors.danger, height: 1.4)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: refresh),
        ]),
      );

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
