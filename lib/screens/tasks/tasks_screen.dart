import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../goals/goal_widgets.dart';
import '../list_search_field.dart';
import 'task_common.dart';
import 'task_list.dart';

/// Tasks as a screen of its own, for places that open it as a panel (Mission
/// Control's shortcut). The phone tab and the desktop sidebar embed
/// [TaskList] directly under their own headers.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.client});

  final DaemonClient client;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  String _query = '';
  Set<TaskStatus> _filter = {};
  bool _goals = false;

  void _sync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: _goals ? 'Goals' : 'Tasks',
            titleSize: kMobile ? M.pageTitle : 18,
            background: AppColors.bg,
            bordered: false,
            actions: [
              Btn(_goals ? 'Tasks' : 'Goals',
                  small: true,
                  variant: BtnVariant.surface,
                  onTap: () => setState(() => _goals = !_goals)),
              const SizedBox(width: 6),
              if (!_goals) IconBtn('sliders',
                  size: kMobile ? M.minTarget : 24,
                  iconSize: 16,
                  active: _filter.isNotEmpty,
                  tooltip: _filter.isEmpty
                      ? 'Filter'
                      : 'Filter (${_filter.length} selected)',
                  onTap: _pickFilter),
              const SizedBox(width: 6),
              if (!_goals)
                Btn('New task',
                    small: true,
                    icon: 'plus',
                    variant: BtnVariant.surface,
                    onTap: _create),
              const SizedBox(width: 2),
            ],
          ),
          if (!_goals)
            Padding(
              padding: const EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 4),
              child: ListSearchField(
                controller: _search,
                hint: 'Search tasks',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          Expanded(
              child: _goals
                  ? GoalsList(client: widget.client)
                  : _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_feed.loading) return const Center(child: Spinner(size: 22));
    final error = _feed.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error,
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.danger)),
            const SizedBox(height: 12),
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
    );
  }
}
