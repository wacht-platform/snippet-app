import 'package:flutter/material.dart';

import '../api.dart';
import '../github_models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pull_request_detail.dart';

/// Open a session repository's pull requests: a side-pane tab on desktop, a
/// full screen on a phone.
Future<void> openPullRequests(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required GithubStatus status,
  int? number,
}) {
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 1100,
    purpose: ShellPanelPurpose.pullRequests,
    originClient: client,
    originSessionId: session,
    builder: (_, close) => PullRequestsScreen(
        client: client,
        session: session,
        status: status,
        openNumber: number,
        onClose: close),
  );
}

Future<void> openPullRequest(
  BuildContext context, {
  required DaemonClient client,
  required String session,
  required GithubStatus status,
  required int number,
}) {
  if (kMobile) {
    return openPullRequests(context,
        client: client, session: session, status: status, number: number);
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    maxWidth: 1100,
    purpose: ShellPanelPurpose.pullRequests,
    panelId: '$number',
    originClient: client,
    originSessionId: session,
    builder: (_, close) => DesktopPrDetailScreen(
        client: client, session: session, number: number, status: status),
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
    this.openNumber,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final VoidCallback? onClose;
  final int? openNumber;

  @override
  State<PullRequestsScreen> createState() => _PullRequestsScreenState();
}

class _PullRequestsScreenState extends State<PullRequestsScreen> {
  static const _filters = [
    ('open', 'Open'),
    ('review', 'Needs review'),
    ('mine', 'Mine'),
    ('closed', 'Closed'),
  ];
  String _filter = 'open';
  List<PrSummary>? _prs;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kMobile) return;
    _load();
    final n = widget.openNumber;
    if (n != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNumber(n);
      });
    }
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

  void _pick(String key) {
    if (key == _filter) return;
    setState(() {
      _filter = key;
      _prs = null;
    });
    _load();
  }

  Future<void> _open(PrSummary pr) => _openNumber(pr.number);

  Future<void> _openNumber(int number) async {
    await Navigator.of(context).push(PrRoute<void>(
      builder: (_) => PullRequestScreen(
        client: widget.client,
        session: widget.session,
        number: number,
        status: widget.status,
      ),
    ));
    if (mounted) _load();
  }

  Widget _tabs() => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (key, label) in _filters)
            InkWell(
              onTap: () => _pick(key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: _filter == key ? AppColors.accent : Colors.transparent,
                        width: 2),
                  ),
                ),
                child: Text(label,
                    style: sans(13,
                        weight: W.label,
                        color: _filter == key ? AppColors.fg1 : AppColors.fg3)),
              ),
            ),
        ]),
      );

  (String, Color) _stateIcon(PrSummary pr) => switch (pr.state) {
        'MERGED' => ('git-commit', AppColors.accent),
        'CLOSED' => ('x-circle', AppColors.fg4),
        _ => pr.draft ? ('git-branch', AppColors.fg4) : ('git-branch', AppColors.ok),
      };

  Widget _avatar(String login) {
    const tints = [0xFF7C8CF8, 0xFF5BC0A0, 0xFFE0A050, 0xFFD27AA8, 0xFF62A8E0, 0xFFB59A6A];
    final tint = Color(tints[login.codeUnits.fold<int>(0, (a, b) => a + b) % tints.length]);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(login.isEmpty ? '?' : login[0].toUpperCase(),
          style: sans(11, weight: W.strong, color: tint)),
    );
  }

  Widget? _checksIcon(PrSummary pr) => switch (rollup(pr.checks)) {
        ChecksState.passing => Tooltip(
            message: 'Checks passed',
            child: AppIcon('check', size: 13, color: AppColors.ok)),
        ChecksState.failing => Tooltip(
            message: 'Checks failing',
            child: AppIcon('x-circle', size: 13, color: AppColors.danger)),
        ChecksState.pending => Tooltip(
            message: 'Checks running',
            child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: AppColors.run, shape: BoxShape.circle))),
        ChecksState.none => null,
      };

  Widget? _reviewIcon(PrSummary pr) => switch (pr.reviewDecision) {
        'APPROVED' => Tooltip(
            message: 'Approved',
            child: AppIcon('check-check', size: 14, color: AppColors.ok)),
        'CHANGES_REQUESTED' => Tooltip(
            message: 'Changes requested',
            child: AppIcon('alert-circle', size: 13, color: AppColors.danger)),
        _ => null,
      };

  Widget _row(PrSummary pr) {
    final (icon, ink) = _stateIcon(pr);
    final indicators = [
      for (final w in [_checksIcon(pr), _reviewIcon(pr)])
        if (w != null) w,
    ];
    return InkWell(
      onTap: () => _open(pr),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, kMobile ? 12 : 9, 14, kMobile ? 12 : 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(icon, size: 15, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pr.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 14,
                        weight: W.label, height: 1.35, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Row(children: [
                  Flexible(
                    child: Text(
                        '#${pr.number} · ${pr.author} · ${_ago(pr.updatedAt)}${pr.draft ? ' · draft' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.meta(AppColors.fg3)),
                  ),
                  for (final w in indicators) ...[const SizedBox(width: 8), w],
                  const SizedBox(width: 8),
                  _size(pr.additions, pr.deletions),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _avatar(pr.author),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String label, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Row(children: [
          Text(label, style: sans(12.5, weight: W.label, color: AppColors.fg2)),
          const SizedBox(width: 6),
          Text('$count', style: TS.meta(AppColors.fg4)),
        ]),
      );

  List<Widget> _body(List<PrSummary> prs) {
    if (_filter != 'open') return [for (final p in prs) _row(p)];
    final me = widget.status.viewer;
    final review = prs.where((p) => p.author != me && p.reviewers.contains(me)).toList();
    final mine = prs.where((p) => p.author == me).toList();
    final others = prs.where((p) => !review.contains(p) && !mine.contains(p)).toList();
    return [
      for (final (label, list) in [
        ('Needs your review', review),
        ('Yours', mine),
        ('Others', others),
      ])
        if (list.isNotEmpty) ...[
          _sectionHeader(label, list.length),
          for (final p in list) _row(p),
        ],
    ];
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('git-branch', size: 22, color: AppColors.fg4),
            const SizedBox(height: 10),
            Text(
                switch (_filter) {
                  'review' => 'Nothing waiting on your review.',
                  'mine' => 'You have no open pull requests.',
                  'closed' => 'No closed pull requests.',
                  _ => 'No open pull requests.',
                },
                style: sans(13, color: AppColors.fg3)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return DesktopPullRequests(
        client: widget.client,
        session: widget.session,
        status: widget.status,
        openNumber: widget.openNumber,
      );
    }
    final prs = _prs;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _screenHeader(context,
              title: 'Pull requests'),
          _tabs(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null || prs == null || prs.isEmpty
                  ? LayoutBuilder(
                      builder: (context, box) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: box.maxHeight,
                            child: _error != null
                                ? _message(_error!)
                                : prs == null
                                    ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                                    : _empty(),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: _body(prs),
                    ),
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

