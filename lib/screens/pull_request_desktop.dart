part of 'pull_request_detail.dart';

const _prFilters = [
  ('open', 'Open'),
  ('review', 'Needs review'),
  ('mine', 'Mine'),
  ('closed', 'Closed'),
];

(String, Color) _prStateIcon(PrSummary pr) => switch (pr.state) {
      'MERGED' => ('git-commit', AppColors.accent),
      'CLOSED' => ('x-circle', AppColors.danger),
      _ => pr.draft ? ('git-branch', AppColors.fg4) : ('git-branch', AppColors.ok),
    };

Widget _prDot(Color c, {double size = 7}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

class PrListPanel extends StatefulWidget {
  const PrListPanel({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    required this.selected,
    required this.onSelect,
    this.showTitle = true,
    this.onLoaded,
    this.refreshTick,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool showTitle;
  final ValueChanged<List<PrSummary>>? onLoaded;
  final int? refreshTick;

  @override
  State<PrListPanel> createState() => _PrListPanelState();
}

class _PrListPanelState extends State<PrListPanel> {
  String _filter = 'open';
  List<PrSummary>? _prs;
  String? _error;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PrListPanel old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick || old.session != widget.session) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final filter = _filter;
    try {
      final prs = await widget.client.githubPrs(widget.session, filter);
      if (!mounted || filter != _filter) return;
      setState(() => _prs = prs);
      widget.onLoaded?.call(prs);
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

  List<PrSummary> get _visible {
    final q = _query.trim().toLowerCase();
    final prs = _prs ?? const <PrSummary>[];
    if (q.isEmpty) return prs;
    return prs
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            '#${p.number}'.contains(q) ||
            p.author.toLowerCase().contains(q) ||
            p.head.toLowerCase().contains(q))
        .toList();
  }

  Widget _filterChip(String key, String label) {
    final on = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: on ? AppColors.surface3 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          onTap: () => _pick(key),
          borderRadius: BorderRadius.circular(R.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(label,
                style: sans(12.5,
                    weight: W.label, color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  Widget _row(PrSummary pr) {
    final selected = pr.number == widget.selected;
    final (icon, ink) = _prStateIcon(pr);
    final checks = rollup(pr.checks);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: () => widget.onSelect(pr.number),
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: widget.showTitle
                ? const EdgeInsets.fromLTRB(10, 9, 10, 9)
                : const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppIcon(icon, size: 14, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pr.title,
                      maxLines: widget.showTitle ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13,
                          weight: W.label, height: 1.35, color: AppColors.fg1)),
                  SizedBox(height: widget.showTitle ? 4 : 2),
                  Row(children: [
                    Flexible(
                      child: Text(
                          '#${pr.number} · ${pr.author} · ${prAgo(pr.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.meta(AppColors.fg3)),
                    ),
                    if (checks != ChecksState.none) ...[
                      const SizedBox(width: 8),
                      _prDot(switch (checks) {
                        ChecksState.failing => AppColors.danger,
                        ChecksState.pending => AppColors.run,
                        _ => AppColors.ok,
                      }, size: 6),
                    ],
                    if (pr.reviewDecision == 'APPROVED') ...[
                      const SizedBox(width: 6),
                      AppIcon('check-check', size: 13, color: AppColors.ok),
                    ],
                    if (pr.reviewDecision == 'CHANGES_REQUESTED') ...[
                      const SizedBox(width: 6),
                      AppIcon('alert-circle', size: 12, color: AppColors.danger),
                    ],
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text('$text  $count', style: sans(11.5, weight: W.label, color: AppColors.fg4)),
      );

  List<Widget> _rows(List<PrSummary> prs) {
    if (_filter != 'open' || _query.trim().isNotEmpty) return [for (final p in prs) _row(p)];
    final me = widget.status.viewer;
    final review = prs.where((p) => p.author != me && p.reviewers.contains(me)).toList();
    final mine = prs.where((p) => p.author == me).toList();
    final others = prs.where((p) => !review.contains(p) && !mine.contains(p)).toList();
    final groups = [
      ('Needs your review', review),
      ('Yours', mine),
      ('Others', others),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.length == 1) return [for (final p in prs) _row(p)];
    return [
      for (final (label, list) in groups) ...[
        _label(label, list.length),
        for (final p in list) _row(p),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final prs = _prs;
    final visible = _visible;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showTitle)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
          child: Row(children: [
            Expanded(
              child: Text('Pull requests',
                  style: sans(15, weight: W.strong, color: AppColors.fg1)),
            ),
            IconBtn('refresh', size: 28, iconSize: 14, tooltip: 'Refresh', onTap: _load),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            AppIcon('search', size: 13, color: AppColors.fg4),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: sans(12.5, color: AppColors.fg1),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Filter by title, number, author',
                  hintStyle: sans(12.5, color: AppColors.fg4),
                ),
              ),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (key, label) in _prFilters) _filterChip(key, label),
          ]),
        ),
      ),
      Expanded(
        child: _error != null
            ? prMessage(_error!)
            : prs == null
                ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                : visible.isEmpty
                    ? prMessage(_query.trim().isNotEmpty
                        ? 'Nothing matches.'
                        : switch (_filter) {
                            'review' => 'Nothing waiting on your review.',
                            'mine' => 'You have no open pull requests.',
                            'closed' => 'No closed pull requests.',
                            _ => 'No open pull requests.',
                          })
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: _rows(visible),
                        ),
                      ),
      ),
    ]);
  }
}

class PrSidebarList extends StatefulWidget {
  const PrSidebarList({
    super.key,
    required this.client,
    required this.session,
    required this.onOpen,
  });

  final DaemonClient client;
  final String session;
  final ValueChanged<int> onOpen;

  @override
  State<PrSidebarList> createState() => _PrSidebarListState();
}

class _PrSidebarListState extends State<PrSidebarList> {
  GithubStatus? _status;
  bool _checked = false;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(PrSidebarList old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      setState(() {
        _status = null;
        _checked = false;
        _selected = null;
      });
      _check();
    }
  }

  Future<void> _check() async {
    final session = widget.session;
    final status = await widget.client.githubStatus(session);
    if (!mounted || session != widget.session) return;
    setState(() {
      _status = status != null && status.available ? status : null;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!_checked) return Center(child: Spinner(size: 16, color: AppColors.fg3));
    if (status == null) {
      return prMessage('Pull requests need the GitHub CLI installed and signed in, in a GitHub repository.');
    }
    return PrListPanel(
      client: widget.client,
      session: widget.session,
      status: status,
      selected: _selected,
      showTitle: false,
      onSelect: (n) {
        setState(() => _selected = n);
        widget.onOpen(n);
      },
    );
  }
}

class DesktopPrDetailScreen extends StatelessWidget {
  const DesktopPrDetailScreen({
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
  Widget build(BuildContext context) => Material(
        color: AppColors.bg,
        child: _DesktopPrDetail(
          client: client,
          session: session,
          number: number,
          status: status,
          listHidden: false,
          onToggleList: null,
          onChanged: () async {},
        ),
      );
}

class DesktopPullRequests extends StatefulWidget {
  const DesktopPullRequests({
    super.key,
    required this.client,
    required this.session,
    required this.status,
    this.openNumber,
  });

  final DaemonClient client;
  final String session;
  final GithubStatus status;
  final int? openNumber;

  @override
  State<DesktopPullRequests> createState() => _DesktopPullRequestsState();
}

class _DesktopPullRequestsState extends State<DesktopPullRequests> {
  int? _selected;
  bool _listHidden = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.openNumber;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final list = Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: PrListPanel(
        client: widget.client,
        session: widget.session,
        status: widget.status,
        selected: selected,
        refreshTick: _tick,
        onSelect: (n) => setState(() => _selected = n),
        onLoaded: (prs) {
          if (_selected == null && prs.isNotEmpty) setState(() => _selected = prs.first.number);
        },
      ),
    );
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 760;
        final showList = !_listHidden && (!narrow || selected == null);
        final detail = selected == null
            ? const EmptyState(
                icon: 'git-branch',
                title: 'No pull request selected',
                body: 'Pick one from the list.',
              )
            : _DesktopPrDetail(
                key: ValueKey('pr-$selected'),
                client: widget.client,
                session: widget.session,
                number: selected,
                status: widget.status,
                listHidden: !showList,
                onToggleList: () => setState(() {
                  if (narrow) {
                    _selected = null;
                  } else {
                    _listHidden = !_listHidden;
                  }
                }),
                onChanged: () async => setState(() => _tick++),
              );
        if (narrow) return showList ? list : detail;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showList) SizedBox(width: box.maxWidth >= 1200 ? 340 : 300, child: list),
          Expanded(child: detail),
        ]);
      }),
    );
  }
}

class _DesktopPrDetail extends StatefulWidget {
  const _DesktopPrDetail({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.status,
    required this.listHidden,
    required this.onToggleList,
    required this.onChanged,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final GithubStatus status;
  final bool listHidden;
  final VoidCallback? onToggleList;
  final Future<void> Function() onChanged;

  @override
  State<_DesktopPrDetail> createState() => _DesktopPrDetailState();
}

class _DesktopPrDetailState extends State<_DesktopPrDetail> {
  PrDetail? _pr;
  String _diff = '';
  String? _error;
  bool _busy = false;
  int _tab = 0;
  String? _scrollTo;
  final _comment = TextEditingController();

  String get _key => '${widget.client.baseUrl}|${widget.session}|${widget.number}';
  List<PendingComment> get _pending => _pendingByPr.putIfAbsent(_key, () => []);
  Set<String> get _viewed => _viewedByPr.putIfAbsent(_key, () => {});
  bool get _open => _pr?.summary.state == 'OPEN';
  bool get _isAuthor => _pr?.summary.author == widget.status.viewer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
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
        _diff = results[1] as String;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _reload() async {
    await _load();
    await widget.onChanged();
  }

  Future<void> _postComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.client.commentOnPr(widget.session, widget.number, text);
      _comment.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final submitted = await submitPrReviewFlow(context,
        client: widget.client,
        session: widget.session,
        number: widget.number,
        pending: _pending,
        isAuthor: _isAuthor);
    if (submitted && mounted) {
      setState(() {});
      await _reload();
    }
  }

  Future<void> _menu(BuildContext anchor) async {
    final s = _pr!.summary;
    final open = s.state == 'OPEN';
    final action = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 230,
      items: [
        if (open && !s.draft)
          appMenuRow<String>(value: 'draft', icon: 'git-branch', label: 'Convert to draft'),
        if (open && s.draft)
          appMenuRow<String>(value: 'ready', icon: 'eye', label: 'Ready for review'),
        if (open) appMenuRow<String>(value: 'close', icon: 'x-circle', label: 'Close pull request'),
        if (s.state == 'CLOSED')
          appMenuRow<String>(value: 'reopen', icon: 'refresh', label: 'Reopen pull request'),
        appMenuRow<String>(value: 'copy', icon: 'copy', label: 'Copy link'),
        appMenuRow<String>(value: 'github', icon: 'globe', label: 'Open on GitHub'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'github') {
      launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
      return;
    }
    if (action == 'copy') {
      Clipboard.setData(ClipboardData(text: s.url));
      toast(context, 'Link copied');
      return;
    }
    if (action == 'close') {
      final ok = await confirmAction(context,
          title: 'Close #${s.number}?',
          body: 'It can be reopened later; the branch stays.',
          confirmLabel: 'Close pull request');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.prState(widget.session, widget.number, action);
      await _reload();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFiles(String? path) => setState(() {
        _tab = 2;
        _scrollTo = path;
      });

  Widget _stateBadge(PrSummary s) {
    final (label, icon, ink) = switch (s.state) {
      'MERGED' => ('Merged', 'git-commit', AppColors.accent),
      'CLOSED' => ('Closed', 'x-circle', AppColors.danger),
      _ => s.draft ? ('Draft', 'git-branch', AppColors.fg3) : ('Open', 'git-branch', AppColors.ok),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(icon, size: 12, color: ink),
        const SizedBox(width: 5),
        Text(label, style: sans(12, weight: W.label, color: ink)),
      ]),
    );
  }

  Widget _branch(String name) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(name, style: mono(11.5, color: AppColors.fg2)),
      );

  Widget _header(PrDetail pr) {
    final s = pr.summary;
    final pending = _pending.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.listHidden && widget.onToggleList != null) ...[
            IconBtn('sidebar', size: 30, iconSize: 15, tooltip: 'Show list', onTap: widget.onToggleList),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: s.title, style: sans(19, weight: W.strong, height: 1.3, color: AppColors.fg1)),
                  TextSpan(text: '  #${s.number}', style: sans(19, height: 1.3, color: AppColors.fg4)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_open)
            FilledButton(
              onPressed: _busy ? null : _review,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentFill,
                foregroundColor: AppColors.accentFg,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
              ),
              child: Text(pending == 0 ? 'Review' : 'Finish review ($pending)',
                  style: sans(13, weight: W.label, color: AppColors.accentFg)),
            ),
          const SizedBox(width: 4),
          Builder(
            builder: (anchor) => IconBtn('more-horizontal',
                size: 32, iconSize: 16, tooltip: 'More', onTap: _busy ? null : () => _menu(anchor)),
          ),
          if (!widget.listHidden && widget.onToggleList != null)
            IconBtn('sidebar', size: 32, iconSize: 15, tooltip: 'Hide list', onTap: widget.onToggleList),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _stateBadge(s),
            Text(s.author, style: sans(13, weight: W.label, color: AppColors.fg2)),
            Text(s.state == 'MERGED' ? 'merged' : 'wants to merge', style: TS.meta(AppColors.fg3)),
            _branch(s.head),
            AppIcon('arrow-right', size: 12, color: AppColors.fg4),
            _branch(s.base),
            Text('· opened ${prAgo(pr.createdAt)}', style: TS.meta(AppColors.fg4)),
          ],
        ),
        const SizedBox(height: 14),
        Row(children: [
          _tabButton(0, 'Conversation', count: pr.timeline.where((e) => e.kind != PrEventKind.commit).length),
          _tabButton(1, 'Commits', count: pr.commits.length),
          _tabButton(2, 'Files changed', count: pr.files.length),
          const Spacer(),
          prSize(s.additions, s.deletions, size: 12.5),
          const SizedBox(width: 6),
        ]),
      ]),
    );
  }

  Widget _tabButton(int index, String label, {int? count}) {
    final on = _tab == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _tab = index;
        _scrollTo = null;
      }),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        margin: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: on ? AppColors.accent : Colors.transparent, width: 2),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: sans(13, weight: W.label, color: on ? AppColors.fg1 : AppColors.fg3)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text('$count', style: sans(11, weight: W.label, color: AppColors.fg3)),
            ),
          ],
        ]),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pr = _pr;
    if (_error != null) return prMessage(_error!);
    if (pr == null) return Center(child: Spinner(size: 16, color: AppColors.fg3));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(pr),
      Expanded(
        child: switch (_tab) {
          1 => _DesktopCommits(client: widget.client, session: widget.session, commits: pr.commits),
          2 => _DesktopFiles(
              key: ValueKey('files-$_scrollTo'),
              client: widget.client,
              session: widget.session,
              number: widget.number,
              pr: pr,
              diff: _diff,
              pending: _pending,
              viewed: _viewed,
              canComment: _open,
              onChanged: () async {
                await _load();
              },
              onPendingChanged: () => setState(() {}),
              scrollTo: _scrollTo,
            ),
          _ => _conversation(pr),
        },
      ),
    ]);
  }

  Widget _conversation(PrDetail pr) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 980;
      final side = _sidebar(pr);
      final main = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _event(
          avatar: pr.summary.author,
          header: Text.rich(TextSpan(children: [
            TextSpan(text: pr.summary.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
            TextSpan(text: '  opened ${prAgo(pr.createdAt)}', style: TS.meta(AppColors.fg4)),
          ])),
          body: pr.body.trim().isEmpty
              ? Text('No description provided.', style: TS.meta(AppColors.fg4))
              : PrCommentBody(pr.body),
          card: true,
        ),
        ..._timeline(pr),
        if (!wide) ...[
          const SizedBox(height: 8),
          side,
        ],
        const SizedBox(height: 14),
        if (_open || pr.summary.state == 'CLOSED')
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: PrMarkdownComposer(
              controller: _comment,
              minLines: 3,
              hint: 'Add a comment',
              onChanged: () => setState(() {}),
              footer: Row(children: [
                Text('Markdown supported', style: TS.meta(AppColors.fg4)),
                const Spacer(),
                FilledButton(
                  onPressed: _busy || _comment.text.trim().isEmpty ? null : _postComment,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentFill,
                    foregroundColor: AppColors.accentFg,
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
                  ),
                  child: Text('Comment', style: sans(13, weight: W.label, color: AppColors.accentFg)),
                ),
              ]),
            ),
          ),
      ]);
      return RefreshIndicator(
        onRefresh: _reload,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: main),
                  const SizedBox(width: 28),
                  SizedBox(width: 280, child: side),
                ])
              : main,
        ),
      );
    });
  }

  Widget _event({
    String? avatar,
    String? icon,
    Color? ink,
    required Widget header,
    Widget? body,
    bool card = false,
    bool line = true,
  }) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Stack(alignment: Alignment.topCenter, children: [
            if (line)
              Positioned.fill(
                child: Center(child: Container(width: 1.5, color: AppColors.surface2)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: avatar != null
                  ? prAvatar(avatar, size: 28)
                  : Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
                      child: AppIcon(icon ?? 'git-commit', size: 12, color: ink ?? AppColors.fg3),
                    ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 6), child: header),
              if (body != null) ...[
                const SizedBox(height: 8),
                card
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface1,
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: body,
                      )
                    : body,
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _timeline(PrDetail pr) {
    final threadsByReview = <String, List<PrThread>>{};
    for (final t in pr.threads) {
      final id = t.comments.isEmpty ? '' : t.comments.first.reviewId;
      if (id.isNotEmpty) threadsByReview.putIfAbsent(id, () => []).add(t);
    }
    final out = <Widget>[];
    for (final e in pr.timeline) {
      switch (e.kind) {
        case PrEventKind.commit:
          out.add(_event(
            icon: 'git-commit',
            header: Row(children: [
              Expanded(
                child: Text(e.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13, color: AppColors.fg2)),
              ),
              const SizedBox(width: 10),
              Text(e.sha.length > 7 ? e.sha.substring(0, 7) : e.sha, style: mono(11.5, color: AppColors.fg4)),
            ]),
          ));
        case PrEventKind.review:
          final (verb, icon, ink) = switch (e.reviewState) {
            'APPROVED' => ('approved these changes', 'check-circle', AppColors.ok),
            'CHANGES_REQUESTED' => ('requested changes', 'alert-circle', AppColors.danger),
            'DISMISSED' => ('had a review dismissed', 'x-circle', AppColors.fg4),
            _ => ('reviewed', 'eye', AppColors.fg3),
          };
          final threads = threadsByReview[e.reviewId] ?? const [];
          out.add(_event(
            icon: icon,
            ink: ink,
            header: Text.rich(TextSpan(children: [
              TextSpan(text: e.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
              TextSpan(text: ' $verb', style: sans(13, color: AppColors.fg2)),
              TextSpan(text: '  ${prAgo(e.at)}', style: TS.meta(AppColors.fg4)),
            ])),
            body: e.body.trim().isEmpty && threads.isEmpty
                ? null
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (e.body.trim().isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        margin: EdgeInsets.only(bottom: threads.isEmpty ? 0 : 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface1,
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: PrCommentBody(e.body),
                      ),
                    if (threads.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _showFiles(threads.first.path),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 30),
                          backgroundColor: AppColors.surface1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
                        ),
                        icon: AppIcon('message', size: 13, color: AppColors.accent),
                        label: Text(
                            '${threads.length} comment${threads.length == 1 ? '' : 's'} on ${threads.map((t) => t.path.split('/').last).toSet().join(', ')}',
                            style: sans(12.5, weight: W.label, color: AppColors.accent)),
                      ),
                  ]),
          ));
        case PrEventKind.comment:
          out.add(_event(
            avatar: e.author,
            header: Text.rich(TextSpan(children: [
              TextSpan(text: e.author, style: sans(13, weight: W.label, color: AppColors.fg1)),
              TextSpan(text: '  commented ${prAgo(e.at)}', style: TS.meta(AppColors.fg4)),
            ])),
            body: PrCommentBody(e.body),
            card: true,
          ));
      }
    }
    return out;
  }

  Widget _sideTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: sans(11.5, weight: W.label, color: AppColors.fg4)),
      );

  Widget _sideRow(String icon, Color ink, String label, {String detail = '', VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: AppIcon(icon, size: 14, color: ink)),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: sans(13, color: AppColors.fg1)),
                if (detail.isNotEmpty) Text(detail, style: TS.meta(AppColors.fg4)),
              ]),
            ),
          ]),
        ),
      );

  Widget _sidebar(PrDetail pr) {
    final s = pr.summary;
    final reviews = <String, String>{
      for (final e in pr.timeline.where((e) => e.kind == PrEventKind.review)) e.author: e.reviewState,
    };
    final reviewers = {...s.reviewers, ...reviews.keys}.toList();
    final checks = s.checks;
    final merge = switch (pr.mergeState) {
      'CLEAN' || 'HAS_HOOKS' => ('check-circle', AppColors.ok, 'No conflicts', 'Ready to merge into ${s.base}'),
      'DIRTY' => ('alert-triangle', AppColors.danger, 'Conflicts', 'Resolve them before merging'),
      'BEHIND' => ('alert-triangle', AppColors.run, 'Out of date', 'Update it with ${s.base}'),
      'BLOCKED' => ('x-circle', AppColors.danger, 'Blocked', 'Required reviews or checks are missing'),
      'UNSTABLE' => ('alert-triangle', AppColors.run, 'Some checks failed', 'It can still be merged'),
      'DRAFT' => ('git-branch', AppColors.fg3, 'Draft', 'Mark it ready before merging'),
      _ => ('clock', AppColors.fg3, 'Checking mergeability', ''),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sideTitle('Reviewers'),
      if (reviewers.isEmpty)
        Text('No reviewers', style: TS.meta(AppColors.fg4))
      else
        for (final r in reviewers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              prAvatar(r, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(r, style: sans(13, color: AppColors.fg1))),
              switch (reviews[r]) {
                'APPROVED' => Tooltip(message: 'Approved', child: AppIcon('check', size: 14, color: AppColors.ok)),
                'CHANGES_REQUESTED' => Tooltip(
                    message: 'Changes requested', child: AppIcon('alert-circle', size: 13, color: AppColors.danger)),
                'COMMENTED' => Tooltip(message: 'Commented', child: AppIcon('message', size: 13, color: AppColors.fg3)),
                _ => Tooltip(message: 'Awaiting review', child: _prDot(AppColors.run, size: 6)),
              },
            ]),
          ),
      const SizedBox(height: 20),
      _sideTitle(checks.isEmpty ? 'Checks' : 'Checks  ${checks.length}'),
      if (checks.isEmpty)
        Text('No checks', style: TS.meta(AppColors.fg4))
      else
        for (final c in checks)
          _sideRow(
            switch (c.state) {
              ChecksState.failing => 'x-circle',
              ChecksState.pending => 'clock',
              _ => 'check-circle',
            },
            switch (c.state) {
              ChecksState.failing => AppColors.danger,
              ChecksState.pending => AppColors.run,
              _ => AppColors.ok,
            },
            c.name,
            detail: c.workflow,
            onTap: c.url.isEmpty ? null : () => launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication),
          ),
      if (_open) ...[
        const SizedBox(height: 20),
        _sideTitle('Merge'),
        if (pr.autoMergeMethod.isEmpty && !s.draft) _sideRow(merge.$1, merge.$2, merge.$3, detail: merge.$4),
        PrMergeBox(
          client: widget.client,
          session: widget.session,
          pr: pr,
          status: widget.status,
          onDone: _reload,
          padding: const EdgeInsets.only(top: 6),
        ),
      ],
    ]);
  }
}

class _DesktopCommits extends StatefulWidget {
  const _DesktopCommits({required this.client, required this.session, required this.commits});
  final DaemonClient client;
  final String session;
  final List<PrCommit> commits;

  @override
  State<_DesktopCommits> createState() => _DesktopCommitsState();
}

class _DesktopCommitsState extends State<_DesktopCommits> {
  PrCommit? _open;
  Map<String, List<DiffLine>>? _files;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.commits.isNotEmpty) {
      _open = widget.commits.last;
      _load(_open!);
    }
  }

  void _show(PrCommit c) {
    setState(() {
      _open = c;
      _files = null;
      _error = null;
    });
    _load(c);
  }

  Future<void> _load(PrCommit c) async {
    try {
      final d = await widget.client.githubCommitDiff(widget.session, c.oid);
      if (mounted && _open == c) setState(() => _files = parseUnifiedDiff(d));
    } catch (e) {
      if (mounted && _open == c) setState(() => _error = '$e');
    }
  }

  Widget _row(PrCommit c) {
    final short = c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid;
    final on = _open == c;
    return Material(
      color: on ? AppColors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: () => _show(c),
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13.5, weight: W.label, height: 1.35, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Text('${c.author} · ${prAgo(c.date)}', style: TS.meta(AppColors.fg4)),
              ]),
            ),
            const SizedBox(width: 10),
            Text(short, style: mono(11.5, color: AppColors.fg3)),
            IconBtn('copy', size: 26, iconSize: 12, tooltip: 'Copy SHA', onTap: () {
              Clipboard.setData(ClipboardData(text: c.oid));
              toast(context, 'Copied $short');
            }),
          ]),
        ),
      ),
    );
  }

  Widget _diff() {
    final c = _open!;
    final files = _files;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.headline, style: sans(15, weight: W.strong, color: AppColors.fg1)),
          if (c.body.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(c.body.trim(), style: sans(13, height: 1.5, color: AppColors.fg3)),
          ],
        ]),
      ),
      Expanded(
        child: _error != null
            ? prMessage(_error!)
            : files == null
                ? Center(child: Spinner(size: 16, color: AppColors.fg3))
                : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 32), children: [
                    for (final e in files.entries)
                      PrFileDiff(
                        file: PrFile(
                          path: e.key,
                          additions: e.value.where((l) => l.kind == DiffKind.add).length,
                          deletions: e.value.where((l) => l.kind == DiffKind.del).length,
                          changeType: '',
                        ),
                        lines: e.value,
                        threads: const [],
                        pending: const [],
                        viewed: false,
                        onViewed: null,
                        canComment: false,
                        client: widget.client,
                        session: widget.session,
                        number: 0,
                        onPendingChanged: () {},
                        onThreadsChanged: () async {},
                      ),
                  ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.commits.isEmpty) return prMessage('No commits.');
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [for (final c in widget.commits.reversed) _row(c)],
    );
    if (_open == null) return list;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 320, child: list),
      Container(width: 1, color: AppColors.border),
      Expanded(child: _diff()),
    ]);
  }
}

class _DesktopFiles extends StatefulWidget {
  const _DesktopFiles({
    super.key,
    required this.client,
    required this.session,
    required this.number,
    required this.pr,
    required this.diff,
    required this.pending,
    required this.viewed,
    required this.canComment,
    required this.onChanged,
    required this.onPendingChanged,
    this.scrollTo,
  });

  final DaemonClient client;
  final String session;
  final int number;
  final PrDetail pr;
  final String diff;
  final List<PendingComment> pending;
  final Set<String> viewed;
  final bool canComment;
  final Future<void> Function() onChanged;
  final VoidCallback onPendingChanged;
  final String? scrollTo;

  @override
  State<_DesktopFiles> createState() => _DesktopFilesState();
}

class _DesktopFilesState extends State<_DesktopFiles> {
  late final Map<String, List<DiffLine>> _parsed = parseUnifiedDiff(widget.diff);
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    final to = widget.scrollTo;
    if (to != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(to));
    }
  }

  void _jump(String path) {
    final ctx = _keys[path]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 220));
  }

  Future<void> _jumpMenu(BuildContext anchor) async {
    final path = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 300,
      items: [
        for (final f in widget.pr.files)
          appMenuRow<String>(
            value: f.path,
            icon: widget.viewed.contains(f.path) ? 'check-circle' : 'file-code',
            label: f.path.split('/').last,
            description: f.path.contains('/') ? f.path.substring(0, f.path.lastIndexOf('/')) : null,
            trailing: '+${f.additions} −${f.deletions}',
          ),
      ],
    );
    if (path != null) _jump(path);
  }

  Widget _bar() {
    final files = widget.pr.files;
    final viewed = files.where((f) => widget.viewed.contains(f.path)).length;
    final pending = widget.pending.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 14, 6),
      child: Row(children: [
        SizedBox(
          width: 14,
          height: 14,
          child: viewed == files.length && files.isNotEmpty
              ? AppIcon('check-circle', size: 14, color: AppColors.ok)
              : CircularProgressIndicator(
                  value: files.isEmpty ? 0 : viewed / files.length,
                  strokeWidth: 2,
                  color: AppColors.accent,
                  backgroundColor: AppColors.fg4.withValues(alpha: 0.3),
                ),
        ),
        const SizedBox(width: 8),
        Text('$viewed of ${files.length} viewed', style: sans(12.5, color: AppColors.fg3)),
        if (pending > 0) ...[
          const SizedBox(width: 12),
          AppIcon('message', size: 12, color: AppColors.accent),
          const SizedBox(width: 5),
          Text('$pending pending', style: sans(12.5, color: AppColors.accent)),
        ],
        const Spacer(),
        Builder(
          builder: (anchor) => TextButton.icon(
            onPressed: () => _jumpMenu(anchor),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
            ),
            icon: AppIcon('folder-open', size: 13, color: AppColors.fg3),
            label: Text('Jump to file', style: sans(12.5, color: AppColors.fg2)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.pr.files;
    if (files.isEmpty) return prMessage('No files changed.');
    final diffs = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final f in files)
          KeyedSubtree(
            key: _keys.putIfAbsent(f.path, () => GlobalKey()),
            child: PrFileDiff(
              file: f,
              lines: _parsed[f.path] ?? const [],
              threads: widget.pr.threads.where((t) => t.path == f.path).toList(),
              pending: widget.pending,
              viewed: widget.viewed.contains(f.path),
              onViewed: (v) => setState(() => v ? widget.viewed.add(f.path) : widget.viewed.remove(f.path)),
              canComment: widget.canComment,
              client: widget.client,
              session: widget.session,
              number: widget.number,
              onPendingChanged: () {
                setState(() {});
                widget.onPendingChanged();
              },
              onThreadsChanged: widget.onChanged,
            ),
          ),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bar(),
      Expanded(child: diffs),
    ]);
  }
}
