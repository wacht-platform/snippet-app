import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../motion.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../list_search_field.dart';
import '../shell_nav.dart';
import 'create_task_form.dart';
import 'task_common.dart';
import 'task_detail_screen.dart';
import 'task_list.dart';

class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.client,
    this.trailing = const [],
    this.phoneHeader = true,
  });

  final DaemonClient client;
  final List<Widget> trailing;
  final bool phoneHeader;

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
  String? _selectedTaskId;
  bool _creatingTask = false;

  @override
  void didUpdateWidget(covariant TasksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _feed.dispose();
      _feed = TaskFeed(widget.client, onChange: _sync);
      _selectedTaskId = null;
      _creatingTask = false;
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

  Future<void> create() async {
    if (!kMobile) {
      setState(() {
        _creatingTask = true;
        _selectedTaskId = null;
      });
      return;
    }
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  Future<void> _open(TaskItem task) async {
    if (!kMobile) {
      setState(() {
        _selectedTaskId = task.id;
        _creatingTask = false;
      });
      return;
    }
    await openTaskDetail(context, widget.client, task.id);
    if (mounted) await _feed.refresh();
  }

  static const _active = {TaskStatus.todo, TaskStatus.inProgress};
  static const _stuck = {TaskStatus.blocked, TaskStatus.failed};

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
    if (kMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                  color: AppColors.fg1.withValues(alpha: 0.08),
                  spreadRadius: 1),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (label, set) in tabs)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _filter = {...set};
                  _shownAt = null;
                }),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: same(_filter, set)
                        ? AppColors.surface3
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label,
                        style: sans(14,
                            weight: W.label,
                            color: same(_filter, set)
                                ? AppColors.fg1
                                : AppColors.fg3)),
                    const SizedBox(width: 6),
                    Text('${set.isEmpty ? tasks.length : count(set)}',
                        style: sans(13, color: AppColors.fg4, tabular: true)),
                  ]),
                ),
              ),
          ]),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (label, set) in tabs) ...[
          Material(
            color: same(_filter, set) ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() {
                _filter = {...set};
                _shownAt = null;
              }),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      style: sans(12,
                          weight: same(_filter, set) ? W.label : W.body,
                          color: same(_filter, set)
                              ? AppColors.fg1
                              : AppColors.fg3)),
                  const SizedBox(width: 5),
                  Text('${set.isEmpty ? tasks.length : count(set)}',
                      style: mono(11, color: AppColors.fg4)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ]),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _search.clear();
        _query = '';
      }
    });
  }

  Widget _desktopBackHeader(String title, VoidCallback onBack) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
        child: Row(children: [
          IconBtn(
            'chevron-left',
            size: 28,
            iconSize: 15,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!kMobile && _selectedTaskId != null) {
      return ColoredBox(
        color: AppColors.windowBg,
        child: TaskDetailScreen(
          key: ValueKey('sidebar-task-$_selectedTaskId'),
          client: widget.client,
          taskId: _selectedTaskId!,
          embedded: true,
          onClose: () {
            setState(() => _selectedTaskId = null);
            _feed.refresh();
          },
        ),
      );
    }
    if (!kMobile && _creatingTask) {
      return ColoredBox(
        color: AppColors.windowBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _desktopBackHeader(
                'New task', () => setState(() => _creatingTask = false)),
            Expanded(
              child: CreateTaskForm(
                client: widget.client,
                onCreated: () {
                  setState(() => _creatingTask = false);
                  _feed.refresh();
                },
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: kMobile ? AppColors.bg : AppColors.windowBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile && widget.phoneHeader) _phoneHeader(),
          if (!kMobile) _desktopHeader(),
          if (_searchOpen)
            kMobile
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        M.gutter, 2, M.gutter, 4),
                    child: ListSearchField(
                      controller: _search,
                      hint: 'Search tasks',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(children: [
                        AppIcon('search', size: 14, color: AppColors.fg4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: (v) => setState(() => _query = v),
                            style: sans(13, color: AppColors.fg1),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: 'Search tasks',
                              hintStyle: sans(13, color: AppColors.fg4),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconBtn('x',
                              size: 20,
                              iconSize: 10,
                              tooltip: 'Clear',
                              onTap: () {
                                _search.clear();
                                setState(() => _query = '');
                              }),
                      ]),
                    ),
                  ),
          if (_feed.tasks.isNotEmpty)
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 0)
                  : const EdgeInsets.fromLTRB(10, 2, 10, 4),
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
      padding: kMobile
          ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 16)
          : const EdgeInsets.fromLTRB(10, 2, 10, 16),
    );
  }
}
