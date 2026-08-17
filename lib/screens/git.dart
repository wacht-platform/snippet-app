import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Git for one session's workspace: status (staged / changed / untracked),
/// per-file diff, stage/unstage/commit, branch switch, push/pull. All operations
/// go through the daemon's /git/* endpoints (server-side `git`).
class GitScreen extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;

  /// When set, git runs against this folder directly (no session needed) — used
  /// from the file explorer. Takes precedence over [sessionId].
  final String? folder;

  /// When hosted in a desktop panel, dismisses the panel from the root bar.
  final VoidCallback? onClose;
  const GitScreen(
      {super.key,
      required this.client,
      this.sessionId = '',
      this.folder,
      this.onClose});
  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen> {
  // The git endpoints accept either a session id or a folder path.
  String get _repo => (widget.folder != null && widget.folder!.isNotEmpty)
      ? widget.folder!
      : widget.sessionId;
  GitStatus? _st;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return; // _op's finally can land after the panel closed
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await widget.client.gitStatus(_repo);
      if (!mounted) return;
      setState(() {
        _st = st;
        _loading = false;
        if (!st.ok) _error = st.error ?? 'not a git repository';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  /// Run a write op, surface git's stderr on failure, then reload.
  Future<void> _op(Future<Map<String, dynamic>> Function() f,
      {String? okMsg}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await f();
      final ok = r['ok'] == true;
      if (!ok) {
        final err = (r['stderr'] as String?)?.trim();
        _toast(err == null || err.isEmpty ? 'git failed' : err);
      } else if (okMsg != null) {
        _toast(okMsg);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  Future<void> _commit() async {
    final msg = await promptText(context,
        title: 'Commit', hint: 'Commit message', saveLabel: 'Commit');
    if (msg == null || msg.trim().isEmpty) return;
    await _op(() => widget.client.gitCommit(_repo, msg.trim()),
        okMsg: 'Committed');
  }

  void _openDiff(GitFile f) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _DiffView(
            client: widget.client,
            sessionId: _repo,
            file: f.path,
            staged: f.staged &&
                !f.unstaged, // staged-only files show the index diff
            untracked: f.untracked,
          ),
        ));
  }

  Future<void> _branchSheet() async {
    late final ({
      String current,
      List<String> local,
      List<String> remotes
    }) data;
    try {
      data = await widget.client.gitBranches(_repo);
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: 'Branches',
      child: _BranchPicker(
        current: data.current,
        local: data.local,
        remotes: data.remotes,
        onSelect: (name, {required bool create}) {
          Navigator.pop(context);
          _op(
            () => widget.client.gitCheckout(_repo, name, create: create),
            okMsg: create ? 'Created $name' : 'Switched to $name',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final st = _st;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Git',
            subtitle: st != null && st.ok ? st.branch : null,
            onBack: widget.onClose ?? () => Navigator.pop(context),
            actions: [IconBtn('refresh', onTap: _busy ? null : _load)],
          ),
          if (_busy)
            LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppColors.surface2,
                color: AppColors.accent),
          if (_loading)
            Expanded(
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fg3))))
          else if (_error != null && (st == null || !st.ok))
            Expanded(
                child: EmptyState(
                    icon: 'git-branch', title: 'No git here', body: _error!))
          else
            Expanded(child: _body(st!)),
        ]),
      ),
    );
  }

  Widget _body(GitStatus st) {
    return Column(children: [
      _header(st),
      Expanded(
        child: st.files.isEmpty
            ? const EmptyState(
                icon: 'check-check',
                title: 'Working tree clean',
                body: 'No changes to commit.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                children: [
                  if (st.staged.isNotEmpty) ...[
                    _sectionHeader('Staged (${st.staged.length})',
                        trailing: 'Unstage all',
                        onTrailing: () =>
                            _op(() => widget.client.gitUnstage(_repo))),
                    ...st.staged.map((f) => _fileRow(f, staged: true)),
                    const SizedBox(height: 8),
                  ],
                  if (st.changed.isNotEmpty) ...[
                    _sectionHeader('Changed (${st.changed.length})',
                        trailing: 'Stage all',
                        onTrailing: () => _op(
                            () => widget.client.gitStage(_repo, all: true))),
                    ...st.changed.map((f) => _fileRow(f, staged: false)),
                    const SizedBox(height: 8),
                  ],
                  if (st.untracked.isNotEmpty) ...[
                    _sectionHeader('Untracked (${st.untracked.length})',
                        trailing: 'Stage all',
                        onTrailing: () => _op(
                            () => widget.client.gitStage(_repo, all: true))),
                    ...st.untracked.map((f) => _fileRow(f, staged: false)),
                  ],
                ],
              ),
      ),
      if (st.staged.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(
              14, 6, 14, 10 + MediaQuery.of(context).padding.bottom),
          child: Btn(
              'Commit ${st.staged.length} file${st.staged.length == 1 ? '' : 's'}',
              icon: 'check',
              full: true,
              disabled: _busy,
              onTap: _commit),
        ),
    ]);
  }

  Widget _header(GitStatus st) {
    final hasUp = st.upstream != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _busy ? null : _branchSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(st.branch.isEmpty ? '(no branch)' : st.branch,
                      style: sans(15.5,
                          weight: FontWeight.w600, color: AppColors.fg1)),
                  if (hasUp)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          st.upstream!,
                          if (st.ahead > 0) '↑${st.ahead}',
                          if (st.behind > 0) '↓${st.behind}',
                        ].join('  '),
                        style: mono(11.5, color: AppColors.fg3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Btn('Branches',
              small: true,
              variant: BtnVariant.ghost,
              onTap: _busy ? null : _branchSheet),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: Btn('Pull',
                  small: true,
                  variant: BtnVariant.secondary,
                  disabled: _busy,
                  onTap: () => _op(() => widget.client.gitPull(_repo),
                      okMsg: 'Pulled'))),
          const SizedBox(width: 8),
          Expanded(
              child: Btn('Push',
                  small: true,
                  variant: BtnVariant.secondary,
                  disabled: _busy,
                  onTap: () => _op(() => widget.client.gitPush(_repo),
                      okMsg: 'Pushed'))),
        ]),
      ]),
    );
  }

  Widget _sectionHeader(String title,
          {String? trailing, VoidCallback? onTrailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: sans(11.5,
                      weight: FontWeight.w600,
                      color: AppColors.fg3,
                      spacing: 0.3))),
          if (trailing != null)
            GestureDetector(
              onTap: _busy ? null : onTrailing,
              child: Text(trailing,
                  style: sans(11.5,
                      weight: FontWeight.w500, color: AppColors.accent)),
            ),
        ]),
      );

  Widget _fileRow(GitFile f, {required bool staged}) {
    final code = staged ? f.x : (f.untracked ? '?' : f.y);
    final (Color c, _) = _statusColor(code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        onTap: () => _openDiff(f),
        child: Row(children: [
          SizedBox(
              width: 16,
              child: Text(code,
                  style: mono(13, weight: FontWeight.w700, color: c))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(f.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(12.5, color: AppColors.fg1))),
          IconBtn(staged ? 'rotate' : 'plus',
              size: 34,
              iconSize: 16,
              tooltip: staged ? 'Unstage' : 'Stage',
              onTap: _busy
                  ? null
                  : () => _op(() => staged
                      ? widget.client.gitUnstage(_repo, paths: [f.path])
                      : widget.client.gitStage(_repo, paths: [f.path]))),
        ]),
      ),
    );
  }

  (Color, String) _statusColor(String code) => switch (code) {
        'M' => (AppColors.run, 'modified'),
        'A' => (AppColors.ok, 'added'),
        'D' => (AppColors.danger, 'deleted'),
        'R' => (AppColors.accent, 'renamed'),
        '?' => (AppColors.fg3, 'untracked'),
        _ => (AppColors.fg3, code),
      };
}

class _BranchPicker extends StatefulWidget {
  final String current;
  final List<String> local;
  final List<String> remotes;
  final void Function(String name, {required bool create}) onSelect;
  const _BranchPicker({
    required this.current,
    required this.local,
    required this.remotes,
    required this.onSelect,
  });
  @override
  State<_BranchPicker> createState() => _BranchPickerState();
}

class _BranchPickerState extends State<_BranchPicker> {
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _hit(String name) {
    final q = _q.text.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  String _localNameForRemote(String remote) {
    final i = remote.indexOf('/');
    return i < 0 ? remote : remote.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final local = widget.local.where(_hit).toList();
    final remotes = widget.remotes.where(_hit).toList();
    final q = _q.text.trim();
    final canCreate = q.isNotEmpty &&
        !widget.local.contains(q) &&
        !q.contains(' ') &&
        !q.startsWith('-');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          controller: _q,
          hint: 'Search local or remote branches',
          icon: 'search',
        ),
        const SizedBox(height: 10),
        if (local.isNotEmpty) ...[
          Text('Local',
              style: sans(11.5, weight: FontWeight.w600, color: AppColors.fg3)),
          const SizedBox(height: 6),
          ...local.map((b) => _row(
                name: b,
                current: b == widget.current,
                onTap: b == widget.current
                    ? null
                    : () => widget.onSelect(b, create: false),
              )),
          const SizedBox(height: 10),
        ],
        if (remotes.isNotEmpty) ...[
          Text('Remote',
              style: sans(11.5, weight: FontWeight.w600, color: AppColors.fg3)),
          const SizedBox(height: 6),
          ...remotes.map((b) => _row(
                name: b,
                remote: true,
                onTap: () => widget.onSelect(b, create: false),
              )),
          const SizedBox(height: 10),
        ],
        if (local.isEmpty && remotes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              q.isEmpty ? 'No branches.' : 'No matches for “$q”.',
              style: sans(13, color: AppColors.fg3),
            ),
          ),
        Btn(
          canCreate ? 'Create “$q”' : 'New branch',
          icon: 'plus',
          variant: BtnVariant.secondary,
          full: true,
          onTap: () async {
            if (canCreate) {
              widget.onSelect(q, create: true);
              return;
            }
            final name = await promptText(context,
                title: 'New branch', hint: 'branch name', saveLabel: 'Create');
            if (name == null || name.trim().isEmpty) return;
            widget.onSelect(name.trim(), create: true);
          },
        ),
      ],
    );
  }

  Widget _row({
    required String name,
    required VoidCallback? onTap,
    bool current = false,
    bool remote = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        onTap: onTap,
        child: Row(children: [
          AppIcon('git-branch',
              size: 15, color: current ? AppColors.accent : AppColors.fg3),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: mono(13, color: AppColors.fg1))),
          if (current)
            Text('current', style: sans(11, color: AppColors.accent))
          else if (remote)
            Text(_localNameForRemote(name),
                style: sans(11, color: AppColors.fg4)),
        ]),
      ),
    );
  }
}

/// Read-only unified-diff viewer with +/- line tints. Reused later by the editor.
class _DiffView extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final String file;
  final bool staged;
  final bool untracked;
  const _DiffView({
    required this.client,
    required this.sessionId,
    required this.file,
    required this.staged,
    required this.untracked,
  });
  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  String? _patch;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Untracked files aren't in the index; their full content shows as an add.
      final p = await widget.client.gitDiff(widget.sessionId,
          file: widget.file,
          staged: widget.staged,
          untracked: widget.untracked);
      if (!mounted) return;
      setState(() {
        _patch = p;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final name = widget.file.split('/').last;
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: name,
            subtitle: widget.file,
            onBack: () => Navigator.pop(context),
            actions: [
              if (_patch != null && _patch!.isNotEmpty)
                IconBtn('clipboard', tooltip: 'Copy', onTap: () {
                  Clipboard.setData(ClipboardData(text: _patch!));
                  toast(context, 'Diff copied');
                }),
            ],
          ),
          if (_loading)
            Expanded(
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fg3))))
          else if (_error != null)
            Expanded(
                child: EmptyState(
                    icon: 'alert-triangle',
                    title: 'Diff failed',
                    body: _error!))
          else if ((_patch ?? '').trim().isEmpty)
            Expanded(
                child: EmptyState(
                    icon: 'file',
                    title: widget.untracked ? 'Untracked file' : 'No diff',
                    body: widget.untracked
                        ? 'New file — stage it to include it in the next commit.'
                        : 'No changes to show for this view.'))
          else
            Expanded(child: _diffBody(_patch!)),
        ]),
      ),
    );
  }

  Widget _diffBody(String patch) {
    final lines = patch.split('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        // IntrinsicWidth bounds the horizontal scroll to the widest line so each
        // line's `width: double.infinity` background resolves (no infinite-width crash).
        child: IntrinsicWidth(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map(_diffLine).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _diffLine(String line) {
    Color? bg;
    Color fg = AppColors.fg2;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      bg = AppColors.diffAddBg;
      fg = AppColors.diffAddFg;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bg = AppColors.diffDelBg;
      fg = AppColors.diffDelFg;
    } else if (line.startsWith('@@')) {
      fg = AppColors.accent;
    } else if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('+++') ||
        line.startsWith('---')) {
      fg = AppColors.fg4;
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Text(line.isEmpty ? ' ' : line,
          style: mono(12, height: 1.4, color: fg)),
    );
  }
}
