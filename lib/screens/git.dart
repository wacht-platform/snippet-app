import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
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

  /// When true, render embedded in a sidebar (no Scaffold / SnAppBar).
  final bool embedded;

  const GitScreen({
    super.key,
    required this.client,
    this.sessionId = '',
    this.folder,
    this.onClose,
    this.embedded = false,
  });

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
  bool _refreshing = false;
  bool _busy = false;
  final Set<String> _optStaged = {};
  final Set<String> _optUnstaged = {};
  String? _error;

  final TextEditingController _commitController = TextEditingController();
  final FocusNode _commitFocus = FocusNode();
  final Set<String> _expandedSections = {};
  static const _collapsedLimit = 8;

  @override
  void initState() {
    super.initState();
    _commitController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _commitController.dispose();
    _commitFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      if (_st == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final st = await widget.client.gitStatus(_repo);
      if (!mounted) return;
      setState(() {
        _st = st;
        _loading = false;
        _refreshing = false;
        if (!st.ok) _error = st.error ?? 'not a git repository';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _toggleStage(GitFile f, {required bool staged}) async {
    HapticFeedback.selectionClick();
    setState(() => (staged ? _optUnstaged : _optStaged).add(f.path));
    try {
      final r = staged
          ? await widget.client.gitUnstage(_repo, paths: [f.path])
          : await widget.client.gitStage(_repo, paths: [f.path]);
      if (r['ok'] != true) {
        final err = (r['stderr'] as String?)?.trim();
        _toast(err == null || err.isEmpty ? 'git failed' : err);
      }
    } catch (e) {
      _toast('$e');
    }
    await _load();
    if (mounted) {
      setState(() => (staged ? _optUnstaged : _optStaged).remove(f.path));
    }
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  /// Run a write op, surface git's stderr on failure, then reload.
  Future<bool> _op(Future<Map<String, dynamic>> Function() f,
      {String? okMsg}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    var ok = false;
    try {
      final r = await f();
      ok = r['ok'] == true;
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
    return ok;
  }

  Future<void> _commit() async {
    final msg = _commitController.text.trim();
    if (msg.isEmpty) {
      _commitFocus.requestFocus();
      _toast('Enter a commit message');
      return;
    }
    if (await _op(() => widget.client.gitCommit(_repo, msg),
        okMsg: 'Committed')) {
      _commitController.clear();
    }
  }

  Future<void> _stageAllAndCommit() async {
    final msg = _commitController.text.trim();
    if (msg.isEmpty) {
      _commitFocus.requestFocus();
      _toast('Enter a commit message');
      return;
    }
    final ok = await _op(() async {
      final s = await widget.client.gitStage(_repo, all: true);
      if (s['ok'] != true) return s;
      return await widget.client.gitCommit(_repo, msg);
    }, okMsg: 'Staged and committed');
    if (ok) _commitController.clear();
  }

  void _openDiff(GitFile f) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GitFileDiffView(
          client: widget.client,
          sessionId: _repo,
          file: f.path,
          staged: f.staged && !f.unstaged, // staged-only files show index diff
          untracked: f.untracked,
        ),
      ),
    );
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
      child: GitBranchPicker(
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
    final content = Column(children: [
      if (widget.embedded)
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            AppIcon('git-branch', size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                st != null && st.ok && st.branch.isNotEmpty
                    ? 'Git · ${st.branch}'
                    : 'Source Control',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, weight: W.label, color: AppColors.fg1),
              ),
            ),
            IconBtn('refresh',
                size: 26,
                iconSize: 13,
                tooltip: 'Refresh',
                onTap: _busy ? null : _load),
            if (widget.onClose != null) ...[
              const SizedBox(width: 2),
              IconBtn('x',
                  size: 26,
                  iconSize: 13,
                  tooltip: 'Close to sessions',
                  onTap: widget.onClose),
            ],
          ]),
        )
      else
        SnAppBar(
          title: 'Git',
          subtitle: st != null && st.ok ? st.branch : null,
          onBack: widget.onClose ?? () => Navigator.pop(context),
          actions: [IconBtn('refresh', onTap: _busy ? null : _load)],
        ),
      if (_busy || _refreshing)
        LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: AppColors.surface2,
          color: AppColors.accent,
        ),
      if (_loading)
        Expanded(
          child: Center(child: DelayedSpinner(size: 22)),
        )
      else if (_error != null && (st == null || !st.ok))
        Expanded(
          child: EmptyState(
            icon: 'git-branch',
            title: 'No git here',
            body: _error!,
          ),
        )
      else
        Expanded(child: _body(st!)),
    ]);

    if (widget.embedded) return content;
    return Scaffold(
      body: SafeArea(bottom: false, child: content),
    );
  }

  Widget _body(GitStatus st) {
    final moving = {..._optStaged, ..._optUnstaged};
    final staged = [
      ...st.staged.where((f) => !_optUnstaged.contains(f.path)),
      ...[...st.changed, ...st.untracked]
          .where((f) => _optStaged.contains(f.path) && !f.staged),
    ];
    final changed = [
      ...st.changed.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where(
          (f) => _optUnstaged.contains(f.path) && f.x != 'A' && !f.unstaged),
    ];
    final untracked = [
      ...st.untracked.where((f) => !_optStaged.contains(f.path)),
      ...st.staged.where((f) => _optUnstaged.contains(f.path) && f.x == 'A'),
    ];
    final empty = st.files.isEmpty && moving.isEmpty;
    return Column(children: [
      _header(st),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          children: [
            _commitComposer(st),
            if (empty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: 'check-check',
                  title: 'Working tree clean',
                  body: 'No changes to commit.',
                ),
              )
            else ...[
              if (staged.isNotEmpty) ...[
                _sectionCard(
                  title: 'Staged',
                  count: staged.length,
                  actionLabel: 'Unstage all',
                  onAction: () => _op(() => widget.client.gitUnstage(_repo)),
                  files: staged,
                  staged: true,
                ),
                const SizedBox(height: S.s16),
              ],
              if (changed.isNotEmpty) ...[
                _sectionCard(
                  title: 'Changes',
                  count: changed.length,
                  actionLabel: 'Stage all',
                  onAction: () =>
                      _op(() => widget.client.gitStage(_repo, all: true)),
                  files: changed,
                  staged: false,
                ),
                const SizedBox(height: S.s16),
              ],
              if (untracked.isNotEmpty) ...[
                _sectionCard(
                  title: 'Untracked',
                  count: untracked.length,
                  actionLabel: 'Stage all',
                  onAction: () =>
                      _op(() => widget.client.gitStage(_repo, all: true)),
                  files: untracked,
                  staged: false,
                ),
              ],
            ],
          ],
        ),
      ),
    ]);
  }

  Widget _header(GitStatus st) {
    final hasUp = st.upstream != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s4),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: AppColors.overlay,
              borderRadius: BorderRadius.circular(R.sm),
              child: InkWell(
                onTap: _busy ? null : _branchSheet,
                borderRadius: BorderRadius.circular(R.sm),
                child: Container(
                  height: kMobile ? 36 : 28,
                  padding: const EdgeInsets.symmetric(horizontal: S.s8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('git-branch', size: 16, color: AppColors.accent),
                    const SizedBox(width: S.s6),
                    Flexible(
                      child: Text(
                        st.branch.isEmpty ? '(no branch)' : st.branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.label(AppColors.fg1),
                      ),
                    ),
                    const SizedBox(width: S.s4),
                    AppIcon('chevron-down', size: 14, color: AppColors.fg3),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: S.s8),
        if (hasUp) ...[
          Btn(
            st.behind > 0 ? 'Pull ${st.behind}' : 'Pull',
            small: true,
            icon: 'download',
            variant: BtnVariant.secondary,
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPull(_repo), okMsg: 'Pulled'),
          ),
          const SizedBox(width: S.s6),
          Btn(
            st.ahead > 0 ? 'Push ${st.ahead}' : 'Push',
            small: true,
            icon: 'upload',
            variant: st.ahead > 0 ? BtnVariant.primary : BtnVariant.secondary,
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPush(_repo), okMsg: 'Pushed'),
          ),
        ] else
          Btn(
            'Publish',
            small: true,
            icon: 'upload',
            variant: BtnVariant.secondary,
            disabled: _busy,
            onTap: () =>
                _op(() => widget.client.gitPush(_repo), okMsg: 'Published'),
          ),
      ]),
    );
  }

  Widget _commitComposer(GitStatus st) {
    final hasStaged = st.staged.isNotEmpty;
    final hasAny = st.files.isNotEmpty;
    final hasMsg = _commitController.text.trim().isNotEmpty;
    final canCommit = !_busy && hasMsg && hasAny;
    void submit() {
      if (canCommit) hasStaged ? _commit() : _stageAllAndCommit();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: S.s16),
      padding: const EdgeInsets.fromLTRB(S.s12, S.s8, S.s8, S.s8),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  submit,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  submit,
            },
            child: TextField(
              controller: _commitController,
              focusNode: _commitFocus,
              minLines: 2,
              maxLines: 4,
              style: TS.ui(AppColors.fg1),
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    'Commit message (${kMacOS ? 'Cmd' : 'Ctrl'}+Enter to commit)',
                hintStyle: TS.ui(AppColors.fg4),
                contentPadding: const EdgeInsets.symmetric(vertical: S.s4),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: S.s8),
          Row(children: [
            Text(
              hasStaged
                  ? '${st.staged.length} staged'
                  : hasAny
                      ? 'Nothing staged · ${st.changed.length + st.untracked.length} changed'
                      : 'Clean',
              style: TS.meta(),
            ),
            const Spacer(),
            if (hasStaged)
              Btn('Commit ${st.staged.length}',
                  icon: 'check',
                  small: true,
                  disabled: !canCommit,
                  onTap: _commit)
            else if (hasAny)
              Btn('Commit all',
                  icon: 'check',
                  small: true,
                  variant: BtnVariant.secondary,
                  disabled: !canCommit,
                  onTap: _stageAllAndCommit)
            else
              const Btn('Commit', icon: 'check', small: true, disabled: true),
          ]),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required int count,
    required String actionLabel,
    required VoidCallback onAction,
    required List<GitFile> files,
    required bool staged,
  }) {
    final expanded = files.length <= _collapsedLimit + 2 ||
        _expandedSections.contains(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title,
          count: count,
          action: actionLabel,
          onAction: _busy ? null : onAction,
          padding: const EdgeInsets.fromLTRB(S.s4, 0, 0, S.s4),
        ),
        ListGroup(children: [
          for (final f in expanded ? files : files.take(_collapsedLimit))
            _fileItem(f, staged: staged),
          if (!expanded)
            ListRow(
              title: 'Show ${files.length - _collapsedLimit} more',
              titleWidget: Text('Show ${files.length - _collapsedLimit} more',
                  style: TS.label(AppColors.accent)),
              onTap: () => setState(() => _expandedSections.add(title)),
            ),
        ]),
      ],
    );
  }

  Widget _fileItem(GitFile f, {required bool staged}) {
    final code = staged
        ? (f.x.trim().isNotEmpty ? f.x : (f.untracked ? 'A' : f.y))
        : (f.untracked ? '?' : (f.y.trim().isNotEmpty ? f.y : f.x));
    final tone = _statusTone(code);
    final (fg, bg) = toneColors(tone);
    final slash = f.path.lastIndexOf('/');
    final dir = slash != -1 ? f.path.substring(0, slash + 1) : '';
    final fileName = slash != -1 ? f.path.substring(slash + 1) : f.path;

    return InkWell(
      onTap: () => _openDiff(f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.s12, S.s4, S.s4, S.s4),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(R.xs),
            ),
            child: Text(code == '?' ? 'U' : code,
                style: TS.codeSmall(fg).copyWith(fontWeight: W.label)),
          ),
          const SizedBox(width: S.s8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (dir.isNotEmpty)
                  TextSpan(text: dir, style: TS.codeSmall(AppColors.fg3)),
                TextSpan(text: fileName, style: TS.codeSmall(AppColors.fg1)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconBtn(
            staged ? 'minus' : 'plus',
            size: 30,
            iconSize: 14,
            tooltip: staged ? 'Unstage' : 'Stage',
            onTap: _busy ? null : () => _toggleStage(f, staged: staged),
          ),
        ]),
      ),
    );
  }

  Tone _statusTone(String code) => switch (code) {
        'M' => Tone.run,
        'A' => Tone.ok,
        'D' => Tone.danger,
        'R' => Tone.accent,
        _ => Tone.neutral,
      };
}

class GitBranchPicker extends StatefulWidget {
  final String current;
  final List<String> local;
  final List<String> remotes;
  final void Function(String name, {required bool create}) onSelect;
  const GitBranchPicker({
    super.key,
    required this.current,
    required this.local,
    required this.remotes,
    required this.onSelect,
  });
  @override
  State<GitBranchPicker> createState() => _GitBranchPickerState();
}

class _GitBranchPickerState extends State<GitBranchPicker> {
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
          const SectionHeader('Local',
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
          ListGroup(children: [
            for (final b in local)
              _branchRow(
                name: b,
                current: b == widget.current,
                onTap: b == widget.current
                    ? null
                    : () => widget.onSelect(b, create: false),
              ),
          ]),
          const SizedBox(height: S.s16),
        ],
        if (remotes.isNotEmpty) ...[
          const SectionHeader('Remote',
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
          ListGroup(children: [
            for (final b in remotes)
              _branchRow(
                name: b,
                remote: true,
                onTap: () => widget.onSelect(b, create: false),
              ),
          ]),
          const SizedBox(height: S.s16),
        ],
        if (local.isEmpty && remotes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                q.isEmpty ? 'No branches.' : 'No matches for “$q”.',
                style: TS.ui(AppColors.fg3),
              ),
            ),
          ),
        Btn(
          canCreate ? 'Create branch “$q”' : 'New branch',
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

  Widget _branchRow({
    required String name,
    required VoidCallback? onTap,
    bool current = false,
    bool remote = false,
  }) {
    return ListRow(
      title: name,
      onTap: onTap,
      leading: AppIcon('git-branch',
          size: 16, color: current ? AppColors.accent : AppColors.fg3),
      titleWidget: Text(remote ? _localNameForRemote(name) : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TS.code(current ? AppColors.accent : AppColors.fg1)),
      subtitle: remote ? name : null,
      trailing: current ? const Tag('Current', tone: Tone.accent) : null,
    );
  }
}

enum _DiffLineType { meta, hunk, add, del, context }

class _DiffLineData {
  final int? oldLine;
  final int? newLine;
  final String text;
  final _DiffLineType type;

  const _DiffLineData({
    this.oldLine,
    this.newLine,
    required this.text,
    required this.type,
  });
}

/// Read-only unified-diff viewer with +/- line tints and dual line number gutters.
///
/// Public so a single change can open as a shell tab: the git sidebar panel
/// inspects a diff beside the chat, and that is the same widget the full Git
/// screen pushes. [embedded] drops the app bar when a shell tab already
/// provides chrome.
class GitFileDiffView extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final String file;
  final bool staged;
  final bool untracked;
  final bool embedded;

  const GitFileDiffView({
    super.key,
    required this.client,
    required this.sessionId,
    required this.file,
    required this.staged,
    required this.untracked,
    this.embedded = false,
  });

  @override
  State<GitFileDiffView> createState() => _GitFileDiffViewState();
}

class _GitFileDiffViewState extends State<GitFileDiffView> {
  String? _patch;
  String? _error;
  bool _loading = true;
  List<_DiffLineData> _parsedLines = const [];
  int _additions = 0;
  int _deletions = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.client.gitDiff(
        widget.sessionId,
        file: widget.file,
        staged: widget.staged,
        untracked: widget.untracked,
      );
      if (!mounted) return;
      final parsed = _parseDiff(p);
      setState(() {
        _patch = p;
        _parsedLines = parsed.lines;
        _additions = parsed.additions;
        _deletions = parsed.deletions;
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

  ({List<_DiffLineData> lines, int additions, int deletions}) _parseDiff(
      String patch) {
    if (patch.trim().isEmpty) {
      return (lines: const <_DiffLineData>[], additions: 0, deletions: 0);
    }
    final rawLines = patch.split('\n');
    final result = <_DiffLineData>[];
    int oldLine = 0;
    int newLine = 0;
    int adds = 0;
    int dels = 0;
    var inHunk = false;
    final hunkRe = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)');

    for (final raw in rawLines) {
      if (raw.isEmpty) continue;
      final match = hunkRe.firstMatch(raw);
      if (match != null) {
        inHunk = true;
        oldLine = int.parse(match.group(1)!);
        newLine = int.parse(match.group(2)!);
        result.add(_DiffLineData(
          oldLine: null,
          newLine: null,
          text: raw,
          type: _DiffLineType.hunk,
        ));
      } else if (raw.startsWith('diff ') ||
          (!inHunk &&
              (raw.startsWith('+++') ||
                  raw.startsWith('---') ||
                  raw.startsWith('index ')))) {
        if (raw.startsWith('diff ')) inHunk = false;
        result.add(_DiffLineData(
          oldLine: null,
          newLine: null,
          text: raw,
          type: _DiffLineType.meta,
        ));
      } else if (raw.startsWith('+')) {
        adds++;
        result.add(_DiffLineData(
          oldLine: null,
          newLine: newLine++,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.add,
        ));
      } else if (raw.startsWith('-')) {
        dels++;
        result.add(_DiffLineData(
          oldLine: oldLine++,
          newLine: null,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.del,
        ));
      } else if (raw.startsWith(' ')) {
        result.add(_DiffLineData(
          oldLine: oldLine++,
          newLine: newLine++,
          text: raw.length > 1 ? raw.substring(1) : '',
          type: _DiffLineType.context,
        ));
      } else {
        result.add(_DiffLineData(
          oldLine: null,
          newLine: null,
          text: raw,
          type: _DiffLineType.context,
        ));
      }
    }
    return (lines: result, additions: adds, deletions: dels);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final name = widget.file.split('/').last;
    final slash = widget.file.lastIndexOf('/');
    final parentDir = slash > 0 ? widget.file.substring(0, slash) : null;

    final bar = SnAppBar(
      title: name,
      subtitle: parentDir,
      onBack: () => Navigator.pop(context),
      actions: [
        if (_additions > 0 || _deletions > 0)
          Padding(
            padding: const EdgeInsets.only(right: S.s8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_additions > 0)
                Tag('+$_additions', tone: Tone.ok, mono: true),
              if (_additions > 0 && _deletions > 0) const SizedBox(width: S.s4),
              if (_deletions > 0)
                Tag('-$_deletions', tone: Tone.danger, mono: true),
            ]),
          ),
        if (_patch != null && _patch!.isNotEmpty)
          IconBtn('clipboard', tooltip: 'Copy diff', onTap: () {
            Clipboard.setData(ClipboardData(text: _patch!));
            toast(context, 'Diff copied');
          }),
      ],
    );

    final body = Column(children: [
      if (!widget.embedded) bar,
      if (_loading)
        Expanded(
          child: Center(child: DelayedSpinner(size: 22)),
        )
      else if (_error != null)
        Expanded(
          child: EmptyState(
            icon: 'alert-triangle',
            title: 'Diff failed',
            body: _error!,
          ),
        )
      else if (_parsedLines.isEmpty)
        Expanded(
          child: EmptyState(
            icon: 'file',
            title: widget.untracked ? 'Untracked file' : 'No diff',
            body: widget.untracked
                ? 'New file — stage it to include it in the next commit.'
                : 'No changes to show for this view.',
          ),
        )
      else
        Expanded(child: _diffBody()),
    ]);

    if (widget.embedded) {
      return ColoredBox(color: readingBg, child: body);
    }
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget _diffBody() {
    return LayoutBuilder(builder: (context, c) {
      final paneWidth = c.maxWidth.isFinite ? c.maxWidth : 0.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: paneWidth),
            child: IntrinsicWidth(
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _parsedLines.map(_renderDiffLine).toList(),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _renderDiffLine(_DiffLineData line) {
    if (line.type == _DiffLineType.hunk) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: S.s4),
        padding: const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s4),
        color: AppColors.raised,
        child: Text(line.text, style: TS.codeSmall(AppColors.accent)),
      );
    }

    if (line.type == _DiffLineType.meta) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: Text(line.text, style: TS.codeSmall(AppColors.fg4)),
      );
    }

    final isAdd = line.type == _DiffLineType.add;
    final isDel = line.type == _DiffLineType.del;

    Color? bg;
    Color fg = AppColors.fg2;
    Color gutterFg = AppColors.fg4;
    String sign = ' ';

    if (isAdd) {
      bg = AppColors.diffAddBg;
      fg = AppColors.diffAddFg;
      gutterFg = AppColors.diffAddFg.withValues(alpha: 0.6);
      sign = '+';
    } else if (isDel) {
      bg = AppColors.diffDelBg;
      fg = AppColors.diffDelFg;
      gutterFg = AppColors.diffDelFg.withValues(alpha: 0.6);
      sign = '-';
    }

    final oldStr = line.oldLine?.toString() ?? '';
    final newStr = line.newLine?.toString() ?? '';

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old line number gutter
          SizedBox(
            width: 34,
            child: Text(
              oldStr,
              textAlign: TextAlign.right,
              style: mono(11, color: gutterFg),
            ),
          ),
          const SizedBox(width: 6),
          // New line number gutter
          SizedBox(
            width: 34,
            child: Text(
              newStr,
              textAlign: TextAlign.right,
              style: mono(11, color: gutterFg),
            ),
          ),
          // Sign (+ / - / space)
          SizedBox(
            width: 18,
            child: Text(
              sign,
              textAlign: TextAlign.center,
              style: mono(12, weight: W.label, color: fg),
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: mono(12, height: 1.4, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
