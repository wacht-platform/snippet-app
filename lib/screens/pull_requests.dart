import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../components.dart';
import '../dialog_widgets.dart';
import '../github_models.dart';
import '../menu_widgets.dart';
import '../panel.dart';
import '../platform.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../widgets.dart';

/// Open a session repository's pull requests: a side-pane tab on desktop, a
/// full screen on a phone.
Future<void> openPullRequests(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required GithubStatus status,
}) {
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 1100,
    purpose: ShellPanelPurpose.pullRequests,
    originClient: client,
    originSessionId: session,
    builder: (_, close) => PullRequestsScreen(
        client: client, session: session, status: status, onClose: close),
  );
}

String _ago(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  return relativeTime(t.millisecondsSinceEpoch ~/ 1000);
}

Widget _screenHeader(
  BuildContext context, {
  required String title,
  String subtitle = '',
  VoidCallback? onBack,
  VoidCallback? onClose,
  List<Widget> actions = const [],
}) {
  return Container(
    padding: EdgeInsets.fromLTRB(onBack == null ? 16 : 6, kMobile ? 8 : 10, 6, 10),
    decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border))),
    child: Row(children: [
      if (onBack != null)
        IconBtn('chevron-left',
            size: kMobile ? M.minTarget : 32,
            iconSize: 18,
            tooltip: 'Back',
            onTap: onBack),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 17 : 15,
                    weight: W.strong, color: AppColors.fg1)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.meta(AppColors.fg3)),
          ],
        ),
      ),
      ...actions,
      if (onClose != null)
        IconBtn('x',
            size: kMobile ? M.minTarget : 32,
            iconSize: 16,
            tooltip: 'Close',
            onTap: onClose),
    ]),
  );
}

Widget _checksTag(List<PrCheck> checks) {
  final passed = checks.where((c) => c.state == ChecksState.passing).length;
  return switch (rollup(checks)) {
    ChecksState.none => const SizedBox.shrink(),
    ChecksState.passing =>
      Tag('Checks $passed/${checks.length}', tone: Tone.ok, icon: 'check'),
    ChecksState.failing => Tag(
        '${checks.where((c) => c.state == ChecksState.failing).length} failing',
        tone: Tone.danger,
        icon: 'x-circle'),
    ChecksState.pending => const Tag('Checks running', tone: Tone.run, dot: true),
  };
}

Widget? _decisionTag(String decision) => switch (decision) {
      'APPROVED' => const Tag('Approved', tone: Tone.ok),
      'CHANGES_REQUESTED' => const Tag('Changes requested', tone: Tone.danger),
      'REVIEW_REQUIRED' => const Tag('Review required', tone: Tone.accent),
      _ => null,
    };

Widget _stateTag(PrSummary pr) => switch (pr.state) {
      'MERGED' => const Tag('Merged', tone: Tone.accent),
      'CLOSED' => const Tag('Closed', tone: Tone.neutral),
      _ => pr.draft
          ? const Tag('Draft', tone: Tone.neutral)
          : const Tag('Open', tone: Tone.ok),
    };

Widget _size(int add, int del) => Text.rich(TextSpan(children: [
      TextSpan(text: '+$add', style: TS.meta(AppColors.ok)),
      TextSpan(text: ' −$del', style: TS.meta(AppColors.danger)),
    ]));

class PullRequestsScreen extends StatefulWidget {
  const PullRequestsScreen({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    this.onClose,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final VoidCallback? onClose;

  @override
  State<PullRequestsScreen> createState() => _PullRequestsScreenState();
}

class _PullRequestsScreenState extends State<PullRequestsScreen> {
  static const _filters = [
    ('open', 'Open'),
    ('review', 'Needs my review'),
    ('mine', 'Mine'),
    ('closed', 'Closed'),
  ];
  String _filter = 'open';
  List<PrSummary>? _prs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final filter = _filter;
    try {
      final prs = await widget.client.githubPrs(widget.session, filter);
      if (mounted && filter == _filter) setState(() => _prs = prs);
    } catch (e) {
      if (mounted && filter == _filter) setState(() => _error = '$e');
    }
  }

  void _open(PrSummary pr) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PullRequestScreen(
        client: widget.client,
        session: widget.session,
        number: pr.number,
        status: widget.status,
      ),
    ));
  }

  Widget _row(PrSummary pr) {
    final decision = _decisionTag(pr.reviewDecision);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(pr),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: kMobile ? 14 : 11),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(pr.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 15 : 14,
                          weight: W.label, height: 1.35, color: AppColors.fg1)),
                ),
                const SizedBox(width: 10),
                _size(pr.additions, pr.deletions),
              ]),
              const SizedBox(height: 4),
              Text(
                  '#${pr.number} · ${pr.author} · ${pr.head} → ${pr.base} · ${_ago(pr.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.meta(AppColors.fg3)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _stateTag(pr),
                if (pr.checks.isNotEmpty) _checksTag(pr.checks),
                if (decision != null) decision,
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prs = _prs;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _screenHeader(context,
              title: 'Pull requests',
              subtitle: widget.status.repo,
              onClose: widget.onClose,
              actions: [
                IconBtn('refresh',
                    size: kMobile ? M.minTarget : 32,
                    iconSize: 15,
                    tooltip: 'Refresh',
                    onTap: _load),
              ]),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              children: [
                for (final (key, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label,
                          style: sans(12.5,
                              weight: W.label,
                              color: _filter == key
                                  ? AppColors.accentFg
                                  : AppColors.fg2)),
                      selected: _filter == key,
                      showCheckmark: false,
                      selectedColor: AppColors.accentFill,
                      backgroundColor: AppColors.surface1,
                      side: BorderSide(color: AppColors.border2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.pill)),
                      onSelected: (_) {
                        setState(() {
                          _filter = key;
                          _prs = null;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: _error != null
                ? _message(_error!)
                : prs == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : prs.isEmpty
                        ? _message('No pull requests here.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(children: [for (final p in prs) _row(p)]),
                          ),
          ),
        ]),
      ),
    );
  }
}

Widget _message(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: sans(13, height: 1.5, color: AppColors.fg3)),
      ),
    );

class PullRequestScreen extends StatefulWidget {
  const PullRequestScreen({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.status,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final GithubStatus status;

  @override
  State<PullRequestScreen> createState() => _PullRequestScreenState();
}

class _PullRequestScreenState extends State<PullRequestScreen> {
  PrDetail? _pr;
  Map<String, List<DiffLine>> _diff = const {};
  String? _error;
  int _tab = 0;
  String? _selectedFile;
  final List<PendingComment> _pending = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.client.githubPr(widget.session, widget.number),
        widget.client.githubPrDiff(widget.session, widget.number),
      ]);
      if (!mounted) return;
      setState(() {
        _pr = results[0] as PrDetail;
        _diff = parseUnifiedDiff(results[1] as String);
        _error = null;
        _selectedFile ??= _pr!.files.isEmpty ? null : _pr!.files.first.path;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _open => _pr?.summary.state == 'OPEN';
  bool get _isAuthor => _pr?.summary.author == widget.status.viewer;

  Future<void> _addComment(String path, DiffLine line) async {
    final anchor = line.anchor;
    if (anchor == null || !_open) return;
    final text = await promptText(context,
        title: 'Comment on line ${anchor.$2}',
        hint: 'Leave a comment',
        saveLabel: 'Add to review',
        minLines: 3,
        maxLines: 8);
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _pending.add(PendingComment(
        path: path, line: anchor.$2, side: anchor.$1, body: text.trim())));
  }

  Future<void> _review() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
      builder: (_) => _ReviewSheet(
          pendingCount: _pending.length, canApprove: !_isAuthor),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.submitPrReview(widget.session, widget.number,
          event: result.$1, body: result.$2, comments: List.of(_pending));
      if (!mounted) return;
      toast(context, 'Review submitted');
      setState(() => _pending.clear());
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge(BuildContext anchor) async {
    final method = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 240,
      items: [
        appMenuHeading<String>('Merge'),
        appMenuRow<String>(
            value: 'merge', icon: 'git-commit', label: 'Create a merge commit'),
        appMenuRow<String>(
            value: 'squash', icon: 'minimize', label: 'Squash and merge'),
        appMenuRow<String>(
            value: 'rebase', icon: 'git-branch', label: 'Rebase and merge'),
      ],
    );
    if (method == null || !mounted) return;
    final pr = _pr!.summary;
    final ok = await confirmAction(context,
        title: 'Merge #${pr.number}?',
        body: '${pr.title}\n\n${pr.head} → ${pr.base}',
        confirmLabel: 'Merge',
        danger: false);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.mergePr(widget.session, widget.number, method: method);
      if (!mounted) return;
      toast(context, 'Merged #${pr.number}');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comment() async {
    final text = await promptText(context,
        title: 'Comment on #${widget.number}',
        hint: 'Write a comment',
        saveLabel: 'Comment',
        minLines: 3,
        maxLines: 10);
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.commentOnPr(widget.session, widget.number, text.trim());
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tabs(PrDetail pr) {
    final labels = [
      'Overview',
      'Files ${pr.files.length}',
      'Commits ${pr.commits.length}',
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          InkWell(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: _tab == i ? AppColors.accent : Colors.transparent,
                      width: 2),
                ),
              ),
              child: Text(labels[i],
                  style: sans(13,
                      weight: W.label,
                      color: _tab == i ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
      ]),
    );
  }

  Widget _overview(PrDetail pr) {
    final s = pr.summary;
    final decision = _decisionTag(s.reviewDecision);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(s.title,
            style: sans(kMobile ? 20 : 18,
                weight: W.strong, height: 1.3, color: AppColors.fg1)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _stateTag(s),
          if (decision != null) decision,
          _size(s.additions, s.deletions),
        ]),
        const SizedBox(height: 8),
        Text('${s.author} wants to merge ${s.head} into ${s.base} · ${_ago(s.updatedAt)}',
            style: TS.meta(AppColors.fg3)),
        const SizedBox(height: 16),
        if (pr.body.trim().isEmpty)
          Text('No description.', style: TS.meta(AppColors.fg4))
        else
          MarkdownBody(
            data: pr.body,
            styleSheet: markdownStyle(context),
            onTapLink: (_, href, __) => openMarkdownLink(href),
          ),
        if (s.checks.isNotEmpty) ...[
          _section('Checks'),
          for (final c in s.checks)
            InkWell(
              onTap: c.url.isEmpty
                  ? null
                  : () => launchUrl(Uri.parse(c.url),
                      mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  AppIcon(
                      switch (c.state) {
                        ChecksState.failing => 'x-circle',
                        ChecksState.pending => 'clock',
                        _ => 'check-circle',
                      },
                      size: 14,
                      color: switch (c.state) {
                        ChecksState.failing => AppColors.danger,
                        ChecksState.pending => AppColors.run,
                        _ => AppColors.ok,
                      }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        c.workflow.isEmpty ? c.name : '${c.workflow} / ${c.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.ui(AppColors.fg2)),
                  ),
                ]),
              ),
            ),
        ],
        _section('Conversation'),
        if (pr.timeline.isEmpty)
          Text('No reviews or comments yet.', style: TS.meta(AppColors.fg4)),
        for (final e in pr.timeline) _event(e),
        if (_open) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _comment,
              icon: AppIcon('message', size: 14, color: AppColors.accent),
              label: Text('Comment', style: sans(13, weight: W.label, color: AppColors.accent)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
        child: Text(label, style: sans(13, weight: W.label, color: AppColors.fg2)),
      );

  Widget _event(PrEvent e) {
    final (label, tone) = switch (e.reviewState) {
      'APPROVED' => ('approved', Tone.ok),
      'CHANGES_REQUESTED' => ('requested changes', Tone.danger),
      'COMMENTED' => ('reviewed', Tone.neutral),
      'DISMISSED' => ('review dismissed', Tone.neutral),
      _ => ('commented', Tone.neutral),
    };
    final (fg, _) = toneColors(tone);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: e.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
          TextSpan(text: ' $label', style: sans(13, color: fg)),
          TextSpan(text: ' · ${_ago(e.at)}', style: TS.meta(AppColors.fg4)),
        ])),
        if (e.body.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          MarkdownBody(
            data: e.body,
            styleSheet: markdownStyle(context),
            onTapLink: (_, href, __) => openMarkdownLink(href),
          ),
        ],
      ]),
    );
  }

  Widget _fileList(PrDetail pr, {required bool selectable}) {
    return ListView(children: [
      for (final f in pr.files)
        Material(
          color: selectable && _selectedFile == f.path
              ? AppColors.surface2
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              if (selectable) {
                setState(() => _selectedFile = f.path);
              } else {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => StatefulBuilder(
                    builder: (ctx, setInner) => Material(
                      color: AppColors.bg,
                      child: SafeArea(
                        bottom: false,
                        child: Column(children: [
                          _screenHeader(ctx,
                              title: f.path.split('/').last,
                              subtitle: f.path,
                              onBack: () => Navigator.of(ctx).pop()),
                          Expanded(
                            child: _FileDiff(
                              path: f.path,
                              lines: _diff[f.path] ?? const [],
                              inline: pr.inline,
                              pending: _pending,
                              canComment: _open,
                              onTapLine: (line) async {
                                await _addComment(f.path, line);
                                setInner(() {});
                                setState(() {});
                              },
                              onRemovePending: (c) {
                                setInner(() => _pending.remove(c));
                                setState(() {});
                              },
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ));
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                AppIcon(
                    switch (f.changeType) {
                      'ADDED' => 'file-plus',
                      'DELETED' => 'trash',
                      'RENAMED' => 'transfer',
                      _ => 'file-code',
                    },
                    size: 14,
                    color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.path.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(12, color: AppColors.fg1)),
                      if (f.path.contains('/'))
                        Text(f.path.substring(0, f.path.lastIndexOf('/')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta(AppColors.fg4)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_pending.any((c) => c.path == f.path)) ...[
                  AppIcon('message', size: 12, color: AppColors.accent),
                  const SizedBox(width: 6),
                ],
                _size(f.additions, f.deletions),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _files(PrDetail pr) {
    if (kMobile) return _fileList(pr, selectable: false);
    final path = _selectedFile;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 280, child: _fileList(pr, selectable: true)),
      Container(width: 1, color: AppColors.border),
      Expanded(
        child: path == null
            ? _message('Pick a file.')
            : _FileDiff(
                key: ValueKey(path),
                path: path,
                lines: _diff[path] ?? const [],
                inline: pr.inline,
                pending: _pending,
                canComment: _open,
                onTapLine: (line) => _addComment(path, line),
                onRemovePending: (c) => setState(() => _pending.remove(c)),
              ),
      ),
    ]);
  }

  Widget _commits(PrDetail pr) => ListView(children: [
        for (final c in pr.commits.reversed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.headline, style: TS.ui(AppColors.fg1)),
              const SizedBox(height: 3),
              Text(
                  '${c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid} · ${c.author} · ${_ago(c.date)}',
                  style: TS.meta(AppColors.fg3)),
            ]),
          ),
      ]);

  Widget _actionBar() {
    final pending = _pending.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
              pending == 0
                  ? (kMobile ? 'Tap a diff line to comment' : 'Click a diff line to comment')
                  : '$pending pending comment${pending == 1 ? '' : 's'}',
              style: TS.meta(pending == 0 ? AppColors.fg4 : AppColors.accent)),
        ),
        Builder(
          builder: (anchor) => TextButton(
            onPressed: _busy ? null : () => _merge(anchor),
            child: Text('Merge', style: sans(13, weight: W.label, color: AppColors.fg2)),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: _busy ? null : _review,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentFill,
            foregroundColor: AppColors.accentFg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
          ),
          child: Text(pending == 0 ? 'Review' : 'Review ($pending)',
              style: sans(13, weight: W.label, color: AppColors.accentFg)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pr = _pr;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _screenHeader(context,
              title: '#${widget.number}',
              subtitle: pr?.summary.title ?? '',
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                if (pr != null)
                  IconBtn('globe',
                      size: kMobile ? M.minTarget : 32,
                      iconSize: 15,
                      tooltip: 'Open on GitHub',
                      onTap: () => launchUrl(Uri.parse(pr.summary.url),
                          mode: LaunchMode.externalApplication)),
                IconBtn('refresh',
                    size: kMobile ? M.minTarget : 32,
                    iconSize: 15,
                    tooltip: 'Refresh',
                    onTap: _load),
              ]),
          if (pr != null) _tabs(pr),
          Expanded(
            child: _error != null
                ? _message(_error!)
                : pr == null
                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                    : switch (_tab) {
                        1 => _files(pr),
                        2 => _commits(pr),
                        _ => _overview(pr),
                      },
          ),
          if (pr != null && _open) _actionBar(),
        ]),
      ),
    );
  }
}

class _FileDiff extends StatelessWidget {
  const _FileDiff({
    super.key,
    required this.path,
    required this.lines,
    required this.inline,
    required this.pending,
    required this.canComment,
    required this.onTapLine,
    required this.onRemovePending,
  });

  final String path;
  final List<DiffLine> lines;
  final List<PrInlineComment> inline;
  final List<PendingComment> pending;
  final bool canComment;
  final void Function(DiffLine line) onTapLine;
  final void Function(PendingComment comment) onRemovePending;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return _message('No textual changes in this file.');
    final threads = inline.where((c) => c.path == path && !c.outdated).toList();
    final gutter = kMobile ? 34.0 : 40.0;
    final code = mono(kMobile ? 11.5 : 12, height: 1.5, color: AppColors.fg1);
    final rows = <Widget>[];
    for (final line in lines) {
      if (line.kind == DiffKind.hunk) {
        rows.add(Container(
          color: AppColors.surface1,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(line.text, style: mono(11, color: AppColors.fg3)),
        ));
        continue;
      }
      final bg = switch (line.kind) {
        DiffKind.add => AppColors.diffAddBg,
        DiffKind.del => AppColors.diffDelBg,
        _ => Colors.transparent,
      };
      final sign = switch (line.kind) {
        DiffKind.add => '+',
        DiffKind.del => '−',
        _ => ' ',
      };
      rows.add(Material(
        color: bg,
        child: InkWell(
          onTap: canComment && line.anchor != null ? () => onTapLine(line) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: gutter,
              child: Text('${line.oldLine ?? ''}',
                  textAlign: TextAlign.right,
                  style: mono(11, height: 1.65, color: AppColors.fg4)),
            ),
            SizedBox(
              width: gutter,
              child: Text('${line.newLine ?? ''}',
                  textAlign: TextAlign.right,
                  style: mono(11, height: 1.65, color: AppColors.fg4)),
            ),
            SizedBox(
              width: 18,
              child: Text(sign,
                  textAlign: TextAlign.center,
                  style: code.copyWith(color: AppColors.fg3)),
            ),
            Expanded(child: Text(line.text, style: code)),
          ]),
        ),
      ));
      final anchor = line.anchor;
      if (anchor == null) continue;
      for (final t in threads.where((t) => t.line == anchor.$2 && t.side == anchor.$1)) {
        rows.add(_bubble(context,
            author: t.author, body: t.body, meta: _ago(t.at), reply: t.inReplyTo != null));
      }
      for (final p in pending.where((p) => p.path == path && p.line == anchor.$2 && p.side == anchor.$1)) {
        rows.add(_bubble(context,
            author: 'You',
            body: p.body,
            meta: 'pending',
            pending: true,
            onRemove: () => onRemovePending(p)));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  Widget _bubble(BuildContext context,
      {required String author,
      required String body,
      required String meta,
      bool reply = false,
      bool pending = false,
      VoidCallback? onRemove}) {
    return Container(
      margin: EdgeInsets.fromLTRB(reply ? 56 : 40, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      decoration: BoxDecoration(
        color: pending ? AppColors.accentBg : AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pending ? AppColors.accent : AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: author, style: sans(12.5, weight: W.label, color: AppColors.fg1)),
              TextSpan(text: '  $meta', style: TS.meta(pending ? AppColors.accent : AppColors.fg4)),
            ])),
          ),
          if (onRemove != null)
            IconBtn('x', size: 24, iconSize: 12, tooltip: 'Remove', onTap: onRemove),
        ]),
        const SizedBox(height: 4),
        MarkdownBody(data: body, styleSheet: markdownStyle(context)),
      ]),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.pendingCount, required this.canApprove});
  final int pendingCount;
  final bool canApprove;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _body = TextEditingController();
  String _event = 'COMMENT';

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _event == 'APPROVE' || _body.text.trim().isNotEmpty || widget.pendingCount > 0;

  Widget _option(String event, String label, String detail, {bool enabled = true}) {
    final selected = _event == event;
    return InkWell(
      onTap: enabled ? () => setState(() => _event = event) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBg : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.accent : AppColors.border2),
        ),
        child: Row(children: [
          AppIcon(selected ? 'check-circle' : 'minus',
              size: 15, color: selected ? AppColors.accent : AppColors.fg4),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: sans(14,
                      weight: W.label,
                      color: enabled ? AppColors.fg1 : AppColors.fg4)),
              Text(detail, style: TS.meta(AppColors.fg3)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Submit review', style: sans(17, weight: W.strong, color: AppColors.fg1)),
          if (widget.pendingCount > 0) ...[
            const SizedBox(height: 4),
            Text('Includes ${widget.pendingCount} line comment${widget.pendingCount == 1 ? '' : 's'}',
                style: TS.meta(AppColors.accent)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            style: TS.body(AppColors.fg1),
            decoration: InputDecoration(
              hintText: 'Leave a summary',
              hintStyle: TS.body(AppColors.fg4),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _option('COMMENT', 'Comment', 'General feedback without approving'),
          _option('APPROVE', 'Approve',
              widget.canApprove ? 'Approve these changes' : "You can't approve your own pull request",
              enabled: widget.canApprove),
          _option('REQUEST_CHANGES', 'Request changes', 'Feedback that must be addressed'),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _canSubmit
                ? () => Navigator.of(context).pop((_event, _body.text.trim()))
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: AppColors.accentFill,
              foregroundColor: AppColors.accentFg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
            ),
            child: Text('Submit review',
                style: sans(14, weight: W.label, color: AppColors.accentFg)),
          ),
        ],
      ),
    );
  }
}
