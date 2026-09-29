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

/// Tasks as a home: the phone's Tasks tab and the desktop sidebar section.
///
/// Owns the live feed, the search and the status filter. On a phone the host
/// supplies the page header's trailing controls and triggers [create] from its
/// floating button; on desktop the panel draws its own section header, with
/// the board one click away.
class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.client,
    this.trailing = const [],
    this.onOpenBoard,
  });

  final DaemonClient client;

  /// Phone header controls beside the title (Mission Control, machine).
  final List<Widget> trailing;

  /// Desktop: open the Kanban board.
  final VoidCallback? onOpenBoard;

  @override
  State<TasksPanel> createState() => TasksPanelState();
}

class TasksPanelState extends State<TasksPanel> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  bool _searchOpen = kMobile;
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

  Future<void> _pickFilter() async {
    final picked =
        await showTaskFilter(context, selected: _filter, tasks: _feed.tasks);
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  void _toggleSearch() => setState(() {
        _searchOpen = !_searchOpen;
        if (!_searchOpen) {
          _search.clear();
          _query = '';
        }
      });

  String get _filterTooltip =>
      _filter.isEmpty ? 'Filter' : 'Filter (${_filter.length} selected)';

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
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
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _phoneHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
        child: Row(children: [
          Text('Tasks',
              style: sans(M.pageTitle, weight: W.label, color: AppColors.fg1)),
          const Spacer(),
          IconBtn('sliders',
              size: M.minTarget,
              iconSize: 19,
              active: _filter.isNotEmpty,
              tooltip: _filterTooltip,
              onTap: _pickFilter),
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
          ShellSectionAction(
              icon: 'sliders',
              tooltip: _filterTooltip,
              active: _filter.isNotEmpty,
              onTap: _pickFilter),
          if (widget.onOpenBoard != null)
            ShellSectionAction(
                icon: 'kanban', tooltip: 'Open board', onTap: widget.onOpenBoard),
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
    return TaskList(
      tasks: _feed.tasks,
      query: _query,
      filter: _filter,
      onOpen: _open,
      onRefresh: _feed.refresh,
      // Room at the bottom so the floating New never covers the last row.
      padding: kMobile
          ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 88)
          : null,
    );
  }
}
