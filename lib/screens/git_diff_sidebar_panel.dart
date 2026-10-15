import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../swr.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart' show fileTint;
import 'git.dart';
import 'pull_request_detail.dart' show PrSidebarList;
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
    this.tab = 'changes',
    this.onTab,
    this.onOpenPullRequest,
    this.header,
  });

  final String tab;
  final ValueChanged<String>? onTab;
  final ValueChanged<int>? onOpenPullRequest;
  final Widget? header;

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
  final _commitCtl = TextEditingController();
  bool _committing = false;
  bool _pushing = false;
  GitStatus? _status;
  bool _loading = true;
  String? _error;
  bool _initing = false;
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
    _commitCtl.dispose();
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
    final notRepo = _status != null &&
        !_status!.ok &&
        (_status!.error ?? '').trim().isNotEmpty;

    final tabbed = !kMobile &&
        widget.onTab != null &&
        widget.onOpenPullRequest != null &&
        (widget.sessionId ?? '').isNotEmpty;
    final showPrs = tabbed && widget.tab == 'prs';
    final changes = LayoutBuilder(builder: (context, box) => PullToRefresh(
      onRefresh: refresh,
      child: Container(
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: kMobile ? 8 : 0, bottom: 16),
          children: [
            if (!tabbed)
              ShellSectionHeader(
                label: 'Git Diff',
                leading: widget.header,
              ),
            if (notRepo)
              SizedBox(
                height: (box.maxHeight - 80).clamp(260.0, 640.0),
                child: _notRepoState(repoName),
              )
            else ...[
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
              SizedBox(
                height: (box.maxHeight - 120).clamp(240.0, 640.0),
                child: _cleanState(),
              )
            else ...[
              if (!kMobile && (widget.sessionId ?? '').isNotEmpty)
                _commitBox(files.length),
              const SizedBox(height: 6),
              for (final f in files) _fileRow(f),
            ],
            ],
          ],
        ),
      ),
    ));
    if (!tabbed) return changes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 38,
        padding: const EdgeInsets.fromLTRB(10, 2, 8, 2),
        child: Row(children: [
          _tabChip('changes', files.isEmpty ? 'Changes' : 'Changes  ${files.length}'),
          _tabChip('prs', 'Pull requests'),
        ]),
      ),
      Expanded(
        child: showPrs
            ? PrSidebarList(
                client: widget.client,
                session: widget.sessionId!,
                onOpen: widget.onOpenPullRequest!,
              )
            : changes,
      ),
    ]);
  }

  Future<void> _commit() async {
    final msg = _commitCtl.text.trim();
    final sid = widget.sessionId;
    if (msg.isEmpty || sid == null || _committing) return;
    setState(() => _committing = true);
    try {
      await widget.client.gitStage(sid, all: true);
      await widget.client.gitCommit(sid, msg);
      _commitCtl.clear();
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  Future<void> _push() async {
    final sid = widget.sessionId;
    if (sid == null || _pushing) return;
    setState(() => _pushing = true);
    try {
      await widget.client.gitPush(sid);
      if (mounted) toast(context, 'Pushed');
      await refresh(background: true);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Widget _commitBox(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter,
                          meta: true): _commit,
                      const SingleActivator(LogicalKeyboardKey.enter,
                          control: true): _commit,
                    },
                    child: TextField(
                      controller: _commitCtl,
                      minLines: 2,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      style: sans(13, color: AppColors.fg1),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Commit message',
                        hintStyle: sans(13, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('⌘↵ to commit', style: sans(11.5, color: AppColors.fg4)),
                ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Btn(
                _committing
                    ? 'Committing…'
                    : 'Commit $count file${count == 1 ? '' : 's'}',
                variant: BtnVariant.primary,
                full: true,
                disabled: _commitCtl.text.trim().isEmpty || _committing,
                onTap: _commit,
              ),
            ),
            const SizedBox(width: 8),
            Btn(_pushing ? 'Pushing…' : 'Push',
                variant: BtnVariant.secondary,
                icon: 'upload',
                disabled: _pushing,
                onTap: _push),
          ]),
        ]),
      );

  Widget _tabChip(String key, String label) {
    final on = widget.tab == key;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: on ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: () => widget.onTab?.call(key),
          borderRadius: BorderRadius.circular(7),
          hoverColor: AppColors.surface2.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(label,
                style: sans(13, color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  /// Branch + change count on one flat row. Tapping the row opens the same
  /// local/remote branch picker used by the full Git screen.
  Widget _branchRow(String repoName, String branch, int changes) => Padding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
            : const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: Builder(
          builder: (anchor) => Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(kMobile ? 10 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(kMobile ? 10 : 8),
              onTap: _branchBusy ? null : () => _branchSheet(anchor),
              child: Container(
                height: kMobile ? 36 : 30,
                padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
                child: Row(children: [
                  AppIcon('git-branch', size: kMobile ? 14 : 13, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      branch.isEmpty ? repoName : branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMobile ? TS.label(AppColors.fg1) : sans(13, color: AppColors.fg1),
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
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onOpenDiff == null
                  ? null
                  : () => widget.onOpenDiff!(f),
              child: Padding(
                padding: kMobile
                    ? const EdgeInsets.fromLTRB(10, 7, 10, 7)
                    : const EdgeInsets.fromLTRB(10, 5, 10, 5),
                child: Row(children: [
                  if (kMobile) ...[
                    _statusLetter(f),
                    const SizedBox(width: 10),
                  ] else ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: fileTint(name),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
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
                      style: sans(kMobile ? 13.5 : 13, color: AppColors.fg1),
                    ),
                  ),
                  if (!kMobile) ...[
                    const SizedBox(width: 8),
                    _statusMark(f),
                  ],
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
  Widget _statusMark(GitFile f) {
    final raw = f.staged ? f.x : (f.untracked ? '?' : f.y);
    final l = raw.trim().isEmpty ? 'M' : raw.trim();
    final letter = l == '?' ? 'A' : l;
    final color = switch (letter) {
      'A' => AppColors.ok,
      'D' => AppColors.danger,
      _ => AppColors.run,
    };
    return Text(letter, style: mono(11, color: color));
  }

  Widget _statusLetter(GitFile f) {
    final raw = f.staged ? f.x : (f.untracked ? '?' : f.y);
    final letter = raw.trim().isEmpty ? 'M' : raw.trim();
    final color =
        f.staged ? AppColors.ok : (f.untracked ? AppColors.fg3 : AppColors.run);
    return Tooltip(
      message: f.staged ? 'staged' : (f.untracked ? 'untracked' : 'unstaged'),
      child: Container(
        width: kMobile ? 20 : 16,
        height: kMobile ? 20 : 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(kMobile ? 6 : 4),
        ),
        child: Text(letter, style: mono(kMobile ? 11 : 10, color: color)),
      ),
    );
  }

  Future<void> _initRepo() async {
    if (_initing) return;
    setState(() => _initing = true);
    try {
      final r = await widget.client.gitInit(_repo);
      if (!mounted) return;
      if (r['ok'] != true) {
        final err = (r['stderr'] as String?)?.trim();
        toast(context, err == null || err.isEmpty ? 'git init failed' : err,
            danger: true);
      } else {
        toast(context, 'Git initialized');
      }
      await refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _initing = false);
    }
  }

  Widget _notRepoState(String repoName) => EmptyState(
        icon: 'git-branch',
        title: 'Not a Git repository',
        body:
            'Initialize Git in $repoName to track changes, branches and pull requests here.',
        action: Btn(_initing ? 'Initializing…' : 'Initialize Git',
            small: true,
            icon: 'git-branch',
            disabled: _initing,
            onTap: _initRepo),
      );

  Widget _cleanState() => EmptyState(
        icon: 'check-check',
        title: 'Working tree clean',
        body: 'No changes to commit · updated ${_timeAgo(_lastUpdated)}',
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
