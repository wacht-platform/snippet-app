import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../crew_widgets.dart';
import '../mochi.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../theme.dart';
import '../widgets.dart';
import 'action_list.dart';
import 'list_search_field.dart';
import 'memory_screen.dart';
import 'mobile_chrome.dart';
import 'session.dart';
import 'session_coordination_cards.dart';
import 'tasks/task_common.dart';

const _pageSize = 50;

double get _title => kMobile ? 15 : 13;
double get _body => kMobile ? 14 : 12.5;
double get _meta => kMobile ? 12 : 11;
double get _gutter => kMobile ? M.gutter : 12;

DateTime? _time(String raw) => DateTime.tryParse(raw)?.toLocal();

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  final date =
      '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? date : '$date ${t.year}';
}

final _uuid = RegExp(
    r'\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b');

String _plain(String text) => text
    .replaceAll(RegExp(r'^\s*[#>]+\s*', multiLine: true), '')
    .replaceAll(RegExp(r'[*`]+'), '')
    .replaceAllMapped(_uuid, (m) => m[1]!)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _folder(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return parts.length <= 2 ? parts.join('/') : parts.sublist(parts.length - 2).join('/');
}

/// An agent's Actions: a full page on a phone and a sheet on desktop, the way a
/// session's are.
Future<void> openAgentActions(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
  VoidCallback? onDeleted,
}) {
  if (kMobile) {
    return Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (page) => Material(
        color: AppColors.bg,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileBackBar(
                title: agentName,
                subtitle: 'Actions',
                leading: AgentMochi(agentId, size: 24),
                onBack: () => Navigator.of(page).pop(),
                onTitleTap: () {},
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 28),
                  child: _AgentActions(
                    client: client,
                    agentId: agentId,
                    agentName: agentName,
                    host: page,
                    onDeleted: () {
                      Navigator.of(page).pop();
                      onDeleted?.call();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
  return showAppSheet<void>(
    context,
    title: 'Actions',
    maxWidth: 420,
    maxHeight: 680,
    child: _AgentActions(
      client: client,
      agentId: agentId,
      agentName: agentName,
      host: context,
      dismiss: () => Navigator.of(context).pop(),
      onDeleted: onDeleted,
    ),
  );
}

class _AgentActions extends StatefulWidget {
  const _AgentActions({
    required this.client,
    required this.agentId,
    required this.agentName,
    required this.host,
    this.dismiss,
    this.onDeleted,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Where the chosen action opens. On desktop [dismiss] closes the sheet first.
  final BuildContext host;
  final VoidCallback? dismiss;
  final VoidCallback? onDeleted;

  @override
  State<_AgentActions> createState() => _AgentActionsState();
}

class _AgentActionsState extends State<_AgentActions> {
  CoordinationAgent? _agent;

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((all) {
      if (!mounted) return;
      setState(() =>
          _agent = all.where((a) => a.id == widget.agentId).firstOrNull);
    }).catchError((_) {});
  }

  void _run(void Function(BuildContext) action) {
    widget.dismiss?.call();
    action(widget.host);
  }

  void _openRecords(String title, Widget Function() view) => _run((host) {
        presentScreen(host,
            style: PanelStyle.drawer,
            maxWidth: 720,
            maxHeight: 820,
            builder: (_, close) => _RecordsPage(
                title: title,
                subtitle: widget.agentName,
                onClose: close,
                child: view()));
      });

  ActionRow _setting(
      String action, String icon, String label, String detail,
      {bool danger = false}) {
    final agent = _agent;
    return ActionRow(
      icon: icon,
      label: label,
      detail: detail,
      danger: danger,
      onTap: agent == null
          ? null
          : () => _run((host) => runCrewAgentAction(host, action,
              client: widget.client,
              agent: agent,
              onDeleted: action == 'delete' ? widget.onDeleted : null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final id = widget.agentId;
    final name = widget.agentName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionGroup(label: 'Work', rows: [
          ActionRow(
            icon: 'inbox',
            label: 'Inbox',
            detail: 'Everything sent to this agent',
            onTap: () => _openRecords('Inbox',
                () => AgentInboxView(client: client, agentId: id, agentName: name)),
          ),
          ActionRow(
            icon: 'clipboard',
            label: 'Board',
            detail: 'What it dispatched, reported and noted',
            onTap: () => _openRecords('Board',
                () => AgentBoardView(client: client, agentId: id, agentName: name)),
          ),
          ActionRow(
            icon: 'terminal',
            label: 'Desk session',
            detail: 'The conversation where its mail arrives',
            onTap: () => _run((host) =>
                _openSession(host, client, 'inbox-$id', '$name desk')),
          ),
        ]),
        ActionGroup(label: 'Agent', rows: [
          ActionRow(
            icon: kMobile ? 'book-marked' : 'brain',
            label: 'Memory',
            detail: 'What this agent remembers',
            onTap: () => _run((host) => presentScreen(host,
                builder: (_, close) => MemoryScreen(
                    client: client,
                    embedded: true,
                    onBack: close,
                    initialKey: 'agent:$id'))),
          ),
          _setting('wakes', 'calendar-clock', 'Wakes and reporting',
              'When it wakes and who it tells'),
          _setting('model', 'cpu', 'Inference profile', 'The model it runs on'),
          _setting('nickname', 'edit', 'Nickname', 'What it is called here'),
          _setting('color', 'sparkles', 'Colour', 'Its colour across the app'),
          _setting('delete', 'trash', 'Delete agent',
              'Removes its identity and notes',
              danger: true),
        ]),
      ],
    );
  }
}

/// An inbox or board on its own page, under a session-style bar.
class _RecordsPage extends StatelessWidget {
  const _RecordsPage(
      {required this.title,
      required this.subtitle,
      required this.onClose,
      required this.child});

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: readingBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kMobile)
              MobileBackBar(title: title, subtitle: subtitle, onBack: onClose)
            else
              Container(
                height: 44,
                padding: const EdgeInsets.only(left: 12, right: 6),
                color: AppColors.bg,
                child: Row(children: [
                  Text(title,
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ),
                  IconBtn('x',
                      size: 28, iconSize: 15, tooltip: 'Close', onTap: onClose),
                ]),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

typedef _Load<T> = Future<List<T>> Function(
    {int? before, String? query, String? filter});

/// A searchable, filterable, day-grouped history that loads older pages as it
/// scrolls. The inbox and the board differ only in their rows and their source.
class _RecordList<T> extends StatefulWidget {
  const _RecordList({
    super.key,
    required this.hint,
    required this.filters,
    required this.load,
    required this.idOf,
    required this.timeOf,
    required this.row,
    required this.empty,
    this.groupedFilters = const {},
  });

  /// Filters whose rows stand for groups: a group's newest row changes, so a
  /// poll replaces the list rather than prepending to it.
  final Set<String> groupedFilters;
  final String hint;
  final List<(String, String?)> filters;
  final _Load<T> load;
  final int Function(T) idOf;
  final String Function(T) timeOf;
  final Widget Function(T) row;
  final String empty;

  @override
  State<_RecordList<T>> createState() => _RecordListState<T>();
}

class _RecordListState<T> extends State<_RecordList<T>> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  Timer? _poll;
  List<T> _items = [];
  String? _filter;
  String? _error;
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  int _generation = 0;

  String? get _query {
    final q = _search.text.trim();
    return q.isEmpty ? null : q;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _reload();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _pollHead());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final page = await widget.load(query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page;
        _more = page.length >= _pageSize;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pollHead() async {
    if (!mounted || !TickerMode.valuesOf(context).enabled || _loading || _items.isEmpty) {
      return;
    }
    final generation = _generation;
    try {
      final page = await widget.load(query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      final newest = widget.idOf(_items.first);
      final fresh = page.where((e) => widget.idOf(e) > newest).toList();
      if (fresh.isEmpty) return;
      setState(() {
        if (widget.groupedFilters.contains(_filter)) {
          _items = page;
          _more = page.length >= _pageSize;
        } else {
          _items = [...fresh, ..._items];
        }
      });
    } catch (_) {
      // The next poll or a pull retries; a blip shouldn't replace the list.
    }
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _items.isEmpty) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.load(
          before: widget.idOf(_items.last), query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page];
        _more = page.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _reload);
  }

  void _pickFilter(String? value) {
    setState(() {
      _filter = value;
      _loading = true;
    });
    _reload();
  }

  /// The rows with a day heading wherever the day changes.
  List<Object> _rows() {
    final rows = <Object>[];
    String? day;
    for (final item in _items) {
      final t = _time(widget.timeOf(item));
      final label = t == null ? '' : _dayLabel(t);
      if (label != day && label.isNotEmpty) rows.add(label);
      day = label;
      rows.add(item as Object);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(_gutter, kMobile ? 12 : 10, _gutter, 8),
        child: ListSearchField(
          controller: _search,
          hint: widget.hint,
          onChanged: _searchChanged,
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 6),
        child: Row(children: [
          for (final (label, value) in widget.filters)
            _FilterChip(
              label: label,
              selected: value == _filter,
              onTap: () => _pickFilter(value),
            ),
        ]),
      ),
      Expanded(child: _list()),
    ]);
  }

  Widget _list() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.fg3),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _Notice(
        text: "Couldn't load this. $_error",
        action: 'Try again',
        onAction: () {
          setState(() => _loading = true);
          _reload();
        },
      );
    }
    if (_items.isEmpty) {
      final q = _query;
      return _Notice(text: q != null ? 'Nothing matches "$q".' : widget.empty);
    }
    final rows = _rows();
    return PullToRefresh(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: rows.length + (_more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.fg3),
                ),
              ),
            );
          }
          final row = rows[i];
          if (row is String) return _DayHeading(row, first: i == 0);
          return widget.row(row as T);
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? AppColors.surface3 : Colors.transparent,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobile ? 18 : 6),
          onTap: onTap,
          child: Container(
            height: kMobile ? 34 : 26,
            padding: EdgeInsets.symmetric(horizontal: kMobile ? 12 : 8),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(kMobile ? 13.5 : 12,
                    weight: W.label,
                    color: selected ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label, {required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(_gutter, first ? 8 : 20, _gutter, 4),
        child: Text(label,
            style: sans(_meta, weight: W.label, color: AppColors.fg3)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text,
                textAlign: TextAlign.center,
                style: sans(_body, color: AppColors.fg3, height: 1.45)),
            if (action != null)
              TextButton(
                onPressed: onAction,
                child: Text(action!,
                    style: sans(_body, color: AppColors.accent)),
              ),
          ]),
        ),
      );
}

class _StateTag extends StatelessWidget {
  const _StateTag(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(R.xs),
        ),
        child: Text(label,
            maxLines: 1,
            style: sans(_meta, weight: W.label, color: color)),
      );
}

/// One tappable record: a heading line with its time, then the content.
class _RecordRow extends StatelessWidget {
  const _RecordRow(
      {required this.leading,
      required this.time,
      required this.child,
      required this.onTap});

  final Widget leading;
  final String time;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _time(time);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: _gutter, vertical: kMobile ? 10 : 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: leading),
            if (t != null) ...[
              const SizedBox(width: 8),
              Text(_clock(t),
                  style: sans(_meta, color: AppColors.fg3, tabular: true)),
            ],
          ]),
          const SizedBox(height: 3),
          child,
        ]),
      ),
    );
  }
}

Future<void> _showRecord(
  BuildContext context, {
  required String title,
  required String meta,
  required String text,
  String? heading,
  List<Widget> extra = const [],
  List<(String, VoidCallback)> actions = const [],
}) =>
    showAppSheet<void>(
      context,
      title: title,
      maxWidth: 620,
      maxHeight: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(meta, style: sans(_meta, color: AppColors.fg3)),
          const SizedBox(height: 10),
          if (heading != null && heading.isNotEmpty) ...[
            Text(heading,
                style: sans(_title,
                    weight: W.label, color: AppColors.fg1, height: 1.35)),
            const SizedBox(height: 8),
          ],
          if (text.trim().isNotEmpty)
            CardMarkdownBody(body: text, collapsible: false),
          ...extra,
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                for (final (label, run) in actions)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      run();
                    },
                    child: Text(label,
                        style: sans(_body, color: AppColors.accent)),
                  ),
              ]),
            ),
        ],
      ),
    );

String _fullTime(String raw) {
  final t = _time(raw);
  return t == null ? '' : '${_dayLabel(t)}, ${_clock(t)}';
}

void _openSession(BuildContext context, DaemonClient client, String id, String title) {
  presentScreen(context,
      builder: (_, close) => SessionScreen(
          client: client, sessionId: id, title: title, onMenu: close));
}

/// Everything that has reached an agent: task offers, direct messages from
/// people and other agents, and task room posts that name it.
class AgentInboxView extends StatefulWidget {
  const AgentInboxView(
      {super.key, required this.client, required this.agentId, required this.agentName});

  final DaemonClient client;
  final String agentId;
  final String agentName;

  @override
  State<AgentInboxView> createState() => _AgentInboxViewState();
}

class _AgentInboxViewState extends State<AgentInboxView> {
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((agents) {
      if (!mounted) return;
      setState(() => _names = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
          });
    }).catchError((_) {});
  }

  String _sender(InboxEntry e) {
    if (e.fromKind == 'human') return 'You';
    if (e.fromId == widget.agentId) {
      final to = e.toId;
      return to == null || to == widget.agentId
          ? 'Its own session'
          : 'Sent to ${_names[to] ?? to}';
    }
    return _names[e.fromId] ?? e.fromId;
  }

  (String, Color)? _tag(InboxEntry e) {
    if (e.postKind == 'blocker' || e.postKind == 'interrupt') {
      return (e.postKind == 'blocker' ? 'Blocker' : 'Urgent', AppColors.danger);
    }
    if (e.postKind == 'question') return ('Question', AppColors.accent);
    if (e.source == 'offer') return ('Task offer', AppColors.accent);
    if (e.source == 'room') return ('Task room', AppColors.fg3);
    final envelope = e.envelope;
    if (envelope == null) return null;
    final words = envelope.replaceAll('_', ' ');
    return (words[0].toUpperCase() + words.substring(1), AppColors.fg3);
  }

  void _open(InboxEntry e) {
    final task = e.taskId;
    _showRecord(
      context,
      title: _sender(e),
      meta: [_tag(e)?.$1, _fullTime(e.createdAt)].nonNulls.join(' · '),
      heading: e.title,
      text: e.text,
      actions: [
        if (task != null && task.isNotEmpty)
          ('Open task', () => openTaskDetail(context, widget.client, task)),
      ],
    );
  }

  Widget _row(InboxEntry e) {
    final tag = _tag(e);
    final title = e.title;
    final preview = _plain(e.text);
    return _RecordRow(
      time: e.createdAt,
      onTap: () => _open(e),
      leading: Row(children: [
        Flexible(
          child: Text(_sender(e),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(_title, weight: W.label, color: AppColors.fg1)),
        ),
        if (tag != null) ...[
          const SizedBox(width: 8),
          _StateTag(tag.$1, tag.$2),
        ],
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null && title.isNotEmpty)
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(_body, color: AppColors.fg2, height: 1.4)),
        if (preview.isNotEmpty)
          Text(preview,
              maxLines: title == null || title.isEmpty ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: sans(_body, color: AppColors.fg3, height: 1.4)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RecordList<InboxEntry>(
      hint: 'Search everything sent to ${widget.agentName}',
      filters: const [
        ('All', null),
        ('Task offers', 'offer'),
        ('Messages', 'message'),
        ('Task rooms', 'room'),
      ],
      load: ({before, query, filter}) => widget.client.agentInbox(
        widget.agentId,
        before: before,
        contains: query,
        kind: filter,
        limit: _pageSize,
      ),
      idOf: (e) => e.id,
      timeOf: (e) => e.createdAt,
      row: _row,
      empty: 'Nothing has reached ${widget.agentName} yet.',
    );
  }
}

/// An agent's work log: what it dispatched, what came back, its notes and the
/// progress its sessions reported.
class AgentBoardView extends StatefulWidget {
  const AgentBoardView(
      {super.key, required this.client, required this.agentId, required this.agentName});

  final DaemonClient client;
  final String agentId;
  final String agentName;

  @override
  State<AgentBoardView> createState() => _AgentBoardViewState();
}

class _AgentBoardViewState extends State<AgentBoardView> {
  static const _automatic = 'Automatic, the session wrote no report: ';

  Set<String> _awaiting = const {};
  final Map<String, BoardEntry> _reports = {};
  bool _groupedByFolder = false;

  Future<List<BoardEntry>> _load(
      {int? before, String? query, String? filter}) async {
    _groupedByFolder = filter == 'by-folder';
    final group = switch (filter) {
      'by-task' => 'task',
      'by-folder' => 'folder',
      _ => null,
    };
    final page = await widget.client.agentBoardPage(
      widget.agentId,
      before: before,
      contains: query,
      kind: filter == 'waiting' || group != null ? null : filter,
      outstanding: filter == 'waiting',
      limit: _pageSize,
      group: group,
    );
    if (mounted) {
      setState(() {
        _awaiting = page.awaiting.toSet();
        for (final e in page.entries) {
          final id = e.correlationId;
          if (e.kind == 'reported' && id != null) _reports[id] = e;
        }
      });
    }
    return page.entries;
  }

  (String, String, Color) _look(BoardEntry e) => switch (e.kind) {
        'dispatched' => ('send', 'Dispatched', AppColors.accent),
        'reported' => ('check-circle', 'Reported', AppColors.ok),
        'progress' => (
            'activity',
            e.summary.startsWith(_automatic) ? 'Progress, automatic' : 'Progress',
            AppColors.fg2
          ),
        'noted' => ('file-text', 'Note', AppColors.fg2),
        _ => ('file-text', e.kind, AppColors.fg2),
      };

  /// The summary without what the row already says: the automatic prefix, and
  /// the task id that dispatch and report rows lead with.
  String _summary(BoardEntry e) {
    var text = e.summary.startsWith(_automatic)
        ? e.summary.substring(_automatic.length)
        : e.summary;
    final id = e.correlationId;
    if (id != null && text.startsWith(id)) {
      text = text.substring(id.length).replaceFirst(RegExp(r'^\s*[—:-]\s*'), '');
      if (text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    }
    return text;
  }

  bool _waiting(BoardEntry e) =>
      e.kind == 'dispatched' && _awaiting.contains(e.correlationId);

  void _open(BoardEntry e) {
    final look = _look(e);
    final session = e.sessionId;
    final folder = e.workspace;
    final report = e.kind == 'dispatched' ? _reports[e.correlationId] : null;
    _showRecord(
      context,
      title: look.$2,
      meta: [
        _fullTime(e.createdAt),
        if (folder != null) _folder(folder),
      ].join(' · '),
      text: _summary(e),
      extra: [
        if (report != null) ...[
          const SizedBox(height: 16),
          Text('Reported back, ${_fullTime(report.createdAt)}',
              style: sans(_meta, weight: W.label, color: AppColors.ok)),
          const SizedBox(height: 4),
          CardMarkdownBody(body: report.summary, collapsible: false),
        ],
        if (_waiting(e)) ...[
          const SizedBox(height: 12),
          Text('No report has come back yet.',
              style: sans(_body, color: AppColors.run)),
        ],
      ],
      actions: [
        if (session != null)
          ('Open session',
              () => _openSession(context, widget.client, session, widget.agentName)),
      ],
    );
  }

  void _openGroup(BoardEntry e, {required bool byFolder}) {
    final folder = e.folder ?? e.workspace;
    final task = e.correlationId;
    final Future<List<BoardEntry>>? rows = byFolder
        ? (folder == null
            ? null
            : widget.client
                .agentBoardPage(widget.agentId, workspace: folder, limit: 100)
                .then((p) => p.entries))
        : (task == null
            ? null
            : widget.client
                .agentBoardPage(widget.agentId, correlationId: task, limit: 100)
                .then((p) => p.entries));
    if (rows == null) {
      _open(e);
      return;
    }
    _showRecord(
      context,
      title: byFolder ? _folder(folder!) : (e.taskTitle ?? 'Task'),
      meta: '${e.groupCount} entries'
          '${e.taskStatus == null ? '' : ' · ${e.taskStatus!.replaceAll('_', ' ')}'}',
      text: '',
      extra: [
        FutureBuilder<List<BoardEntry>>(
          future: rows,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return Text(snap.hasError ? 'Could not load this log.' : 'Loading',
                  style: sans(_body, color: AppColors.fg3));
            }
            return BoardLog(entries: data);
          },
        ),
      ],
    );
  }

  Widget _groupRow(BoardEntry e, {required bool byFolder}) {
    final folder = e.folder ?? e.workspace;
    final String title = byFolder
        ? (folder == null ? 'No folder' : _folder(folder))
        : (e.taskTitle ??
            (e.correlationId == null ? 'Not on a task' : 'Earlier work'));
    final status = e.taskStatus?.replaceAll('_', ' ');
    final count = e.groupCount ?? 1;
    return _RecordRow(
      time: e.createdAt,
      onTap: () => _openGroup(e, byFolder: byFolder),
      leading: Row(children: [
        AppIcon(byFolder ? 'folder' : 'file-text',
            size: kMobile ? 15 : 13, color: AppColors.fg2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(_body, weight: W.label, color: AppColors.fg1)),
        ),
        const SizedBox(width: 8),
        Text(
            [
              '$count',
              if (!byFolder && status != null) status,
            ].join(' · '),
            maxLines: 1,
            style: sans(_meta, color: AppColors.fg3)),
      ]),
      child: Text(_plain(_summary(e)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: sans(_body, color: AppColors.fg2, height: 1.4)),
    );
  }

  Widget _row(BoardEntry e) {
    if (e.groupCount != null) {
      return _groupRow(e, byFolder: _groupedByFolder);
    }
    final look = _look(e);
    final folder = e.workspace;
    return _RecordRow(
      time: e.createdAt,
      onTap: () => _open(e),
      leading: Row(children: [
        AppIcon(look.$1, size: kMobile ? 15 : 13, color: look.$3),
        const SizedBox(width: 6),
        Text(look.$2,
            maxLines: 1,
            style: sans(_body, weight: W.label, color: AppColors.fg1)),
        if (folder != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(_folder(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(_meta, color: AppColors.fg3)),
          ),
        ],
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_plain(_summary(e)),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: sans(_body, color: AppColors.fg2, height: 1.4)),
        if (_waiting(e))
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: _WaitingTag(),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RecordList<BoardEntry>(
      hint: "Search ${widget.agentName}'s work",
      groupedFilters: const {'by-task', 'by-folder'},
      filters: const [
        ('All', null),
        ('By task', 'by-task'),
        ('By folder', 'by-folder'),
        ('Waiting', 'waiting'),
        ('Dispatched', 'dispatched'),
        ('Reported', 'reported'),
        ('Progress', 'progress'),
        ('Notes', 'noted'),
      ],
      load: _load,
      idOf: (e) => e.id,
      timeOf: (e) => e.createdAt,
      row: _row,
      empty: 'No work recorded for ${widget.agentName} yet.',
    );
  }
}

/// A running log, newest first. Automatic entries only show when nothing was
/// written, since they say little beside what the agent recorded itself.
class BoardLog extends StatelessWidget {
  const BoardLog({super.key, required this.entries, this.showAgent = false});

  static const _automatic = 'Automatic, the session wrote no report: ';

  final List<BoardEntry> entries;
  final bool showAgent;

  String _text(BoardEntry e) {
    var text = e.summary.startsWith(_automatic)
        ? e.summary.substring(_automatic.length)
        : e.summary;
    final id = e.correlationId;
    if (id != null && text.startsWith(id)) {
      text = text.substring(id.length).replaceFirst(RegExp(r'^\s*[—:-]\s*'), '');
      if (text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    }
    return text.replaceAllMapped(
        RegExp(r'\n(Why|Learned): '), (m) => '\n\n**${m[1]}:** ');
  }

  @override
  Widget build(BuildContext context) {
    final written =
        entries.where((e) => !e.summary.startsWith(_automatic)).toList();
    final rows = written.isEmpty ? entries : written;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    [
                      _fullTime(e.createdAt),
                      if (showAgent) e.agentId,
                      if (e.kind != 'progress') e.kind,
                    ].join(' · '),
                    style: sans(_meta, color: AppColors.fg3)),
                const SizedBox(height: 2),
                CardMarkdownBody(body: _text(e), collapsible: false),
              ],
            ),
          ),
      ],
    );
  }
}

class _WaitingTag extends StatelessWidget {
  const _WaitingTag();

  @override
  Widget build(BuildContext context) =>
      _StateTag('Waiting for report', AppColors.run);
}
