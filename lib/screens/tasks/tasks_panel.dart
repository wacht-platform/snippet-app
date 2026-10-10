import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../list_search_field.dart';
import '../shell_nav.dart';
import 'task_common.dart';
import 'task_list.dart';
import '../../motion.dart';

/// Tasks as a home: the phone's Tasks tab and the desktop sidebar section.
///
/// Owns the live feed, the search and the status filter. On a phone the host
/// supplies the page header's trailing controls and triggers [create] from its
/// floating button; on desktop the panel draws its own section header.
class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.client,
    this.trailing = const [],
  });

  final DaemonClient client;

  /// Phone header controls beside the title (machine switcher).
  final List<Widget> trailing;

  @override
  State<TasksPanel> createState() => TasksPanelState();
}

class TasksPanelState extends State<TasksPanel> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  bool _searchOpen = kMobile;
  DateTime? _shownAt;
  String _query = '';
  Set<TaskStatus> _filter = {};

  @override
  void didUpdateWidget(covariant TasksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _feed.dispose();
      _feed = TaskFeed(widget.client, onChange: _sync);
    }
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    super.dispose();
  }

  /// File a new task.
  Future<void> create() async {
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  Future<void> _open(TaskItem task) async {
    await openTaskDetail(context, widget.client, task.id);
    if (mounted) await _feed.refresh();
  }

  static const _active = {TaskStatus.todo, TaskStatus.inProgress};
  static const _stuck = {TaskStatus.blocked, TaskStatus.failed};

  /// Quiet text tabs: All, Active, Blocked, Done (and Cancelled once there is
  /// any). The count sits beside each name; the chosen one is underlined.
  Widget _statusStrip() {
    final tasks = _feed.tasks;
    int count(Set<TaskStatus> s) =>
        tasks.where((t) => s.contains(t.status)).length;
    final tabs = <(String, Set<TaskStatus>)>[
      ('All', const {}),
      ('Active', _active),
      ('Blocked', _stuck),
      ('Done', const {TaskStatus.done}),
      if (count(const {TaskStatus.cancelled}) > 0)
        ('Cancelled', const {TaskStatus.cancelled}),
    ];
    bool same(Set<TaskStatus> a, Set<TaskStatus> b) =>
        a.length == b.length && a.containsAll(b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (label, set) in tabs)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _filter = {...set};
              _shownAt = null;
            }),
            child: Padding(
              padding: EdgeInsets.only(right: kMobile ? 22 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: kMobile ? 8 : 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label,
                        style: sans(kMobile ? 15 : 13,
                            color: same(_filter, set)
                                ? AppColors.fg1
                                : AppColors.fg3)),
                    const SizedBox(width: 5),
                    Text('${set.isEmpty ? tasks.length : count(set)}',
                        style: sans(kMobile ? 13 : 12,
                            color: AppColors.fg4, tabular: true)),
                  ]),
                  SizedBox(height: kMobile ? 7 : 5),
                  AnimatedContainer(
                    duration: Motion.quick,
                    height: 2,
                    width: same(_filter, set) ? 20 : 0,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  void _toggleSearch() => setState(() {
        _searchOpen = !_searchOpen;
        if (!_searchOpen) {
          _search.clear();
          _query = '';
        }
      });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kMobile ? _phoneHeader() : _desktopHeader(),
          if (_searchOpen)
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 6)
                  : const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ListSearchField(
                controller: _search,
                hint: 'Search tasks',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          if (_feed.tasks.isNotEmpty)
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(M.gutter + 2, 0, M.gutter, 0)
                  : const EdgeInsets.fromLTRB(18, 0, 10, 4),
              child: _statusStrip(),
            ),
          Expanded(
            child: Swap(
              stateKey: _feed.loading
                  ? 'loading'
                  : (_feed.error != null ? 'error' : 'list'),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
        child: Row(children: [
          Text('Tasks', style: TS.pageTitle()),
          const Spacer(),
          ...widget.trailing,
        ]),
      );

  Widget _desktopHeader() => ShellSectionHeader(
        label: 'Tasks',
        actions: [
          ShellSectionAction(
              icon: 'search',
              tooltip: 'Search tasks',
              active: _searchOpen,
              onTap: _toggleSearch),
          ShellSectionAction(icon: 'plus', tooltip: 'New task', onTap: create),
        ],
      );

  Widget _body() {
    if (_feed.loading) {
      return Center(
        child: kMobile
            ? const AppLoading(label: 'Loading tasks')
            : Spinner(size: 20, color: AppColors.fg3),
      );
    }
    final error = _feed.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load tasks',
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg2)),
            const SizedBox(height: 10),
            Btn('Retry', small: true, onTap: _feed.refresh),
          ]),
        ),
      );
    }
    if (_feed.tasks.isNotEmpty) _shownAt ??= DateTime.now();
    return TaskList(
      appearSince: _shownAt,
      tasks: _feed.tasks,
      query: _query,
      filter: _filter,
      onOpen: _open,
      onRefresh: _feed.refresh,
      padding:
          kMobile ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 16) : null,
    );
  }
}
