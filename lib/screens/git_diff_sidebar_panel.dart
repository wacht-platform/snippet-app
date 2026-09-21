import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'git.dart';
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
    this.onOpenDiff,
    this.autoRefreshPeriod = const Duration(seconds: 4),
  });

  final DaemonClient client;
  final String workspacePath;
  final String? sessionId;

  /// Called when a changed file is tapped. The host opens it as a tab in the
  /// main pane, so a diff reads in the same tab system as everything else.
  final void Function(GitFile file)? onOpenDiff;
  final Duration autoRefreshPeriod;

  @override
  State<GitDiffSidebarPanel> createState() => _GitDiffSidebarPanelState();
}

class _GitDiffSidebarPanelState extends State<GitDiffSidebarPanel> {
  GitStatus? _status;
  bool _loading = true;
  String? _error;
  DateTime _lastUpdated = DateTime.now();
  Timer? _autoRefreshTimer;
  bool _refreshing = false;
  bool _branchBusy = false;

  String get _repo =>
      widget.sessionId != null && widget.sessionId!.trim().isNotEmpty
          ? widget.sessionId!
          : widget.workspacePath;

  @override
  void initState() {
    super.initState();
    refresh();
    if (widget.autoRefreshPeriod > Duration.zero) {
      _autoRefreshTimer = Timer.periodic(
        widget.autoRefreshPeriod,
        (_) {
          if (!mounted || _refreshing) return;
          refresh(background: true);
        },
      );
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GitDiffSidebarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.client != widget.client) {
      refresh();
    }
  }

  Future<void> refresh({bool background = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!background && mounted) {
      setState(() {
        if (_status == null) _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.client.gitStatus(_repo);
      if (!mounted) return;
      setState(() {
        _status = res;
        _lastUpdated = DateTime.now();
        if (background) _error = null;
      });
    } catch (e) {
      if (!background && mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      _refreshing = false;
      if (!background && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _branchSheet() async {
    if (_branchBusy) return;
    late final ({
      String current,
      List<String> local,
      List<String> remotes
    }) data;
    try {
      data = await widget.client.gitBranches(_repo);
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: 'Branches',
      child: GitBranchPicker(
        current: data.current,
        local: data.local,
        remotes: data.remotes,
        onSelect: (name, {required bool create}) {
          Navigator.pop(context);
          unawaited(_checkoutBranch(name, create: create));
        },
      ),
    );
  }

  Future<void> _checkoutBranch(String name, {required bool create}) async {
    if (_branchBusy) return;
    setState(() => _branchBusy = true);
    try {
      final result = await widget.client
          .gitCheckout(_repo, name, create: create);
      if (!mounted) return;
      if (result['ok'] != true) {
        final error = (result['stderr'] as String?)?.trim();
        toast(context, error == null || error.isEmpty ? 'git failed' : error);
      } else {
        toast(context, create ? 'Created $name' : 'Switched to $name');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) {
        setState(() => _branchBusy = false);
        await refresh();
      }
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

  /// Branch + change count on one flat row. Tapping the row opens the same
  /// local/remote branch picker used by the full Git screen.
  Widget _branchRow(String repoName, String branch, int changes) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: _branchBusy ? null : _branchSheet,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
              child: Row(children: [
                AppIcon('git-branch', size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
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
                  style: sans(12, color: AppColors.fg3),
                ),
                const SizedBox(width: 6),
                AppIcon('chevron-down', size: 13, color: AppColors.fg3),
              ]),
            ),
          ),
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
        onTap: widget.onOpenDiff == null ? null : () => widget.onOpenDiff!(f),
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
        padding: const EdgeInsets.fromLTRB(kSidebarContentInset, 10,
            kSidebarContentInset, 8),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.okBg,
                borderRadius: BorderRadius.circular(R.xs),
              ),
              child: AppIcon('check-check', size: 15, color: AppColors.ok),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Working tree clean',
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                  const SizedBox(height: 3),
                  Text('No local changes · ${_timeAgo(_lastUpdated)}',
                      style: sans(11, color: AppColors.fg3)),
                  const SizedBox(height: 8),
                  Btn('Switch branch',
                      small: true,
                      icon: 'git-branch',
                      variant: BtnVariant.ghost,
                      onTap: _branchBusy ? null : _branchSheet),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _errorState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_error!,
              style: sans(12, color: AppColors.danger, height: 1.4)),
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
