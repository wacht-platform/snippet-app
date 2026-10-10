import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../swr.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'git.dart';
import 'shell_nav.dart';
import '../pull_refresh.dart';

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
  });

  final DaemonClient client;
  final String workspacePath;
  final String? sessionId;

  /// Called when a changed file is tapped. The host opens it as a tab in the
  /// main pane, so a diff reads in the same tab system as everything else.
  final void Function(GitFile file)? onOpenDiff;

  @override
  State<GitDiffSidebarPanel> createState() => _GitDiffSidebarPanelState();
}

class _GitDiffSidebarPanelState extends State<GitDiffSidebarPanel> {
  GitStatus? _status;
  bool _loading = true;
  String? _error;
  DateTime _lastUpdated = DateTime.now();
  Swr<GitStatus>? _git;
  bool _branchBusy = false;

  String get _repo =>
      widget.sessionId != null && widget.sessionId!.trim().isNotEmpty
          ? widget.sessionId!
          : widget.workspacePath;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _git?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GitDiffSidebarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.client != widget.client) {
      _watch();
    }
  }

  void _watch() {
    _git?.dispose();
    final git = Swr<GitStatus>(
      client: widget.client,
      key: 'git:$_repo',
      fetch: () => widget.client.gitStatus(_repo),
      revalidateOn: _touchesRepo,
      onChange: _sync,
    );
    _git = git;
    _status = git.data;
    _loading = git.data == null;
    _error = null;
  }

  bool _touchesRepo(DeviceEventFrame e) =>
      const {DeviceEventHub.attachedToolResult, 'idle', 'done', 'error'}
          .contains(e['kind']) &&
      ((widget.sessionId != null && e['session'] == widget.sessionId) ||
          e['workspace'] == widget.workspacePath);

  void _sync() {
    final git = _git;
    if (!mounted || git == null) return;
    setState(() {
      final data = git.data;
      if (data != null && !identical(data, _status)) {
        _status = data;
        _lastUpdated = DateTime.now();
      }
      _loading = git.loading;
      _error = data == null && git.error != null ? '${git.error}' : null;
    });
  }

  Future<void> refresh({bool background = false}) async {
    await _git?.refresh();
  }

  Future<void> _branchSheet([BuildContext? anchor]) async {
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
    final picker = GitBranchPicker(
      current: data.current,
      local: data.local,
      remotes: data.remotes,
      onSelect: (name, {required bool create}) {
        Navigator.pop(context);
        unawaited(_checkoutBranch(name, create: create));
      },
    );
    if (!kMobile && anchor != null) {
      await showAnchoredPanel<void>(anchor, width: 380, child: picker);
    } else {
      await showAppSheet<void>(context,
          title: 'Branches', maxWidth: 420, child: picker);
    }
  }

  Future<void> _checkoutBranch(String name, {required bool create}) async {
    if (_branchBusy) return;
    setState(() => _branchBusy = true);
    try {
      final result =
          await widget.client.gitCheckout(_repo, name, create: create);
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

    return PullToRefresh(
      onRefresh: refresh,
      child: Container(
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: kMobile ? 8 : 0, bottom: 16),
          children: [
            ShellSectionHeader(
              label: 'Git Diff',
            ),
            _branchRow(repoName, branch, files.length),
            if (_loading && _status == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Spinner(size: 18),
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
      ),
    );
  }

  /// Branch + change count on one flat row. Tapping the row opens the same
  /// local/remote branch picker used by the full Git screen.
  Widget _branchRow(String repoName, String branch, int changes) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Builder(
          builder: (anchor) => Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _branchBusy ? null : () => _branchSheet(anchor),
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
                      style: TS.label(AppColors.fg1),
                    ),
                  ),
                  if (changes > 0) ...[
                    const SizedBox(width: 6),
                    Text('$changes changed', style: TS.meta()),
                  ],
                  const SizedBox(width: 6),
                  AppIcon('chevron-down', size: 13, color: AppColors.fg3),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _fileRow(GitFile f) {
    final name = lastPathSegment(f.path, ifEmpty: f.path);
    final slash = f.path.lastIndexOf('/');
    final dir = slash > 0 ? f.path.substring(0, slash) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: f.path,
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          label: f.path,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onOpenDiff == null
                  ? null
                  : () => widget.onOpenDiff!(f),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                child: Row(children: [
                  _statusLetter(f),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: name),
                        if (dir.isNotEmpty)
                          TextSpan(
                              text: '  $dir',
                              style: sans(12, color: AppColors.fg4)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13.5, color: AppColors.fg1),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(letter, style: mono(11, color: color)),
      ),
    );
  }

  Widget _cleanState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppIcon('check', size: 14, color: AppColors.ok),
            const SizedBox(width: 8),
            Text('No changes', style: sans(13, color: AppColors.fg2)),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text('Working tree clean · ${_timeAgo(_lastUpdated)}',
                style: sans(12, color: AppColors.fg4)),
          ),
        ]),
      );

  Widget _errorState() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child:
                  AppIcon('alert-triangle', size: 14, color: AppColors.danger),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, height: 1.4, color: AppColors.fg2)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 4),
            child: TextButton(
              onPressed: refresh,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child:
                  Text('Try again', style: sans(13, color: AppColors.accent)),
            ),
          ),
        ]),
      );

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
