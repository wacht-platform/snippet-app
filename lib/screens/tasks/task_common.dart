import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../panel.dart';
import '../../platform.dart';
import '../../swr.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'create_task_form.dart';
import 'task_detail_screen.dart';

/// The live task list for one machine, shared by every task surface.
///
/// Backed by one SWR entry, so the phone tab, the desktop sidebar and the board
/// read the same data and a change on one shows on all of them.
class TaskFeed {
  TaskFeed(this.client, {required VoidCallback onChange})
      : _swr = Swr<List<TaskItem>>(
          client: client,
          key: 'coordination:tasks',
          fetch: () => client.tasks(),
          revalidateOn: Swr.coordination,
          onChange: onChange,
        );

  final DaemonClient client;
  final Swr<List<TaskItem>> _swr;

  List<TaskItem> get tasks => _swr.data ?? const [];
  bool get loading => _swr.data == null && _swr.error == null;

  /// Only a first load that failed is an error; a failed revalidation keeps
  /// showing the last good list.
  String? get error =>
      _swr.data == null && _swr.error != null ? '${_swr.error}' : null;

  Future<void> refresh() => _swr.refresh();

  /// Show a change before the daemon confirms it.
  void replace(TaskItem task) =>
      _swr.mutate([for (final t in tasks) t.id == task.id ? task : t]);

  void dispose() => _swr.dispose();
}

/// The colour a status is drawn in. In progress and blocked are the two a
/// person needs to notice.
Color statusColor(TaskStatus status) => switch (status) {
      TaskStatus.todo => AppColors.fg3,
      TaskStatus.inProgress => AppColors.run,
      TaskStatus.blocked => AppColors.danger,
      TaskStatus.done => AppColors.ok,
      TaskStatus.failed => AppColors.danger,
      TaskStatus.cancelled => AppColors.fg4,
    };

/// Whether a task matches a search: title, description or plan.
bool taskMatches(TaskItem task, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return task.title.toLowerCase().contains(q) ||
      task.description.toLowerCase().contains(q) ||
      task.plan.toLowerCase().contains(q);
}

/// How long since the task last changed, compactly ("5m", "2d").
String taskAge(TaskItem task) {
  final at = DateTime.tryParse(task.updatedAt);
  return at == null ? '' : relativeTime(at.millisecondsSinceEpoch ~/ 1000);
}

/// Open a task's detail: a sheet on a phone, a drawer on desktop.
Future<void> openTaskDetail(
    BuildContext context, DaemonClient client, String taskId) {
  if (kMobile) {
    return showModalBottomSheet<void>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        return SafeArea(
          top: false,
          child: SizedBox(
            height: (media.size.height - media.padding.top) * 0.9,
            child: Material(
              color: AppColors.bg,
              clipBehavior: Clip.antiAlias,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
              child: Column(children: [
                const SizedBox(height: 8),
                Container(
                  width: 30,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: TaskDetailScreen(
                    client: client,
                    taskId: taskId,
                    onClose: () => Navigator.of(sheet).pop(),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.task, panelId: taskId, originClient: client,
    maxWidth: 720,
    maxHeight: 820,
    builder: (_, close) =>
        TaskDetailScreen(client: client, taskId: taskId, onClose: close),
  );
}

/// File a new task. Returns whether one was created.
Future<bool> showCreateTask(BuildContext context, DaemonClient client) async {
  final created = await showAppSheet<bool>(
    context,
    title: 'New task',
    child: CreateTaskForm(client: client),
  );
  return created == true;
}
