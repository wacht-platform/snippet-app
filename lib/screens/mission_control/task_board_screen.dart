import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../panel.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'task_detail_screen.dart';

/// The task board — where a human files work.
///
/// This replaces the coordination board. That was a single global room every
/// participant had to read; a task is the unit a person actually thinks in, and
/// each task owns its own conversation (see [TaskDetailScreen]), so an agent
/// working on one task is not woken by every other task's traffic.
///
/// Columns on a wide window, a status-grouped list on a narrow one: the same
/// [TaskStatus] order drives both, so the two cannot disagree about what comes
/// first.
class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.refreshSignal,
  });

  final DaemonClient client;

  /// When embedded in the hub, suppress our own Scaffold/AppBar.
  final bool embedded;

  /// Bumped by the host to request a refetch.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen> {
  List<TaskItem> tasks = const [];
  bool loading = true;
  String? error;

  /// Null shows every column.
  TaskStatus? filter;

  @override
  void initState() {
    super.initState();
    refresh();
    widget.refreshSignal?.addListener(refresh);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh() async {
    if (mounted) setState(() => loading = tasks.isEmpty);
    try {
      final fetched = await widget.client.tasks();
      if (!mounted) return;
      setState(() {
        tasks = fetched;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context,
      title: 'New task',
      child: CreateTaskForm(client: widget.client),
    );
    if (created == true) await refresh();
  }

  Future<void> _open(TaskItem task) async {
    await presentScreen(
      context,
      style: PanelStyle.drawer,
      maxWidth: 720,
      maxHeight: 820,
      builder: (_, close) => TaskDetailScreen(
        client: widget.client,
        taskId: task.id,
        // The board may have changed while the detail was open, so the list is
        // refetched on close rather than trusting a local edit.
        onClose: () {
          close();
          refresh();
        },
      ),
    );
    if (mounted) await refresh();
  }

  List<TaskItem> get _visible =>
      filter == null ? tasks : tasks.where((t) => t.status == filter).toList();

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      _FilterBar(
        filter: filter,
        counts: {
          for (final s in TaskStatus.values)
            s: tasks.where((t) => t.status == s).length,
        },
        onSelect: (s) => setState(() => filter = s),
      ),
      Expanded(
        child: loading
            ? const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(error!,
                            textAlign: TextAlign.center,
                            style: sans(12.5, color: AppColors.danger)),
                        const SizedBox(height: 12),
                        Btn('Retry', small: true, onTap: refresh),
                      ]),
                    ),
                  )
                : _list(),
      ),
    ]);

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: AppIcon('refresh', size: 19, color: AppColors.fg2),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: AppIcon('plus', size: 18, color: AppColors.accentFg),
        label: const Text('New task'),
      ),
      body: body,
    );
  }

  Widget _list() {
    final visible = _visible;
    if (visible.isEmpty) {
      // Two different empties: a board with nothing on it is a prompt to start,
      // a filter with nothing is a prompt to widen. Saying "no tasks" for both
      // hides which one you are looking at.
      return EmptyState(
        icon: 'layers',
        title: filter == null ? 'No tasks yet' : 'Nothing in ${filter!.label}',
        body: filter == null
            ? 'Create a task and Mission Control picks it up.'
            : 'Try another column, or clear the filter.',
      );
    }
    // Grouped even when filtered, so the section header still tells you which
    // column you are reading.
    final groups = <TaskStatus, List<TaskItem>>{};
    for (final s in TaskStatus.values) {
      final inGroup = visible.where((t) => t.status == s).toList();
      if (inGroup.isNotEmpty) groups[s] = inGroup;
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          for (final entry in groups.entries) ...[
            _StatusHeader(status: entry.key, count: entry.value.length),
            for (final task in entry.value)
              _TaskRow(task: task, onTap: () => _open(task)),
          ],
        ],
      ),
    );
  }
}

/// Column selector with live counts. The counts are what make the filter
/// legible: "Blocked 0" reads as good news, where a bare label reads as nothing.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.counts,
    required this.onSelect,
  });

  final TaskStatus? filter;
  final Map<TaskStatus, int> counts;
  final ValueChanged<TaskStatus?> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            _chip(context,
                label: 'All',
                selected: filter == null,
                onTap: () => onSelect(null)),
            for (final s in TaskStatus.values)
              _chip(context,
                  label: '${s.label} ${counts[s] ?? 0}',
                  selected: filter == s,
                  tint: statusColor(s),
                  onTap: () => onSelect(filter == s ? null : s)),
          ],
        ),
      );

  Widget _chip(BuildContext context,
          {required String label,
          required bool selected,
          required VoidCallback onTap,
          Color? tint}) =>
      Padding(
        padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Selection is a neutral surface step, never the accent — the
                // accent already means state elsewhere in this app.
                color: selected ? AppColors.surface2 : Colors.transparent,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(R.chip),
              ),
              child: Text(label,
                  style: sans(12,
                      weight: selected ? W.label : W.body,
                      color:
                          selected ? AppColors.fg1 : (tint ?? AppColors.fg3))),
            ),
          ),
        ),
      );
}

/// The colour a column is drawn in. `in_progress` is amber and `blocked` is the
/// danger hue because those are the two a person needs to notice.
Color statusColor(TaskStatus status) => switch (status) {
      TaskStatus.todo => AppColors.fg3,
      TaskStatus.inProgress => AppColors.run,
      TaskStatus.blocked => AppColors.danger,
      TaskStatus.done => AppColors.ok,
      TaskStatus.cancelled => AppColors.fg4,
    };

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status, required this.count});
  final TaskStatus status;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: statusColor(status), shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(status.label.toUpperCase(),
              style: sans(11,
                  weight: W.label, color: AppColors.fg3, spacing: 0.5)),
          const SizedBox(width: 6),
          Text('$count', style: sans(11, color: AppColors.fg4)),
        ]),
      );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});
  final TaskItem task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                // Priority is a mark, not a badge: at 0 (the default) it draws
                // nothing, so an ordinary task stays quiet and a raised one
                // stands out without every row carrying an empty chip.
                if (task.priority > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(R.xs)),
                    child: Text('P${task.priority}',
                        style:
                            sans(10, weight: W.label, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13.5, color: AppColors.fg1)),
                ),
                const SizedBox(width: 8),
                AppIcon('chevron-right', size: 15, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
      );
}

/// Describe a task in prose; the daemon owns id, thread and initial column.
///
/// Shared shape with the agent form: one field that matters, the rest derived.
class CreateTaskForm extends StatefulWidget {
  const CreateTaskForm({super.key, required this.client});
  final DaemonClient client;

  @override
  State<CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends State<CreateTaskForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    // Validated on submit, not by a disabled button: `AppField` exposes no
    // `onChanged`, so a length-gated button could never re-enable as you type.
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.createTask(
        title: title,
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What needs doing? Mission Control reads this and works out which agents it needs.',
              style: sans(13, color: AppColors.fg3, height: 1.45),
            ),
            const SizedBox(height: 18),
            AppField(
              controller: _title,
              label: 'Title',
              hint: 'Ship the coordinator panel',
              autofocus: true,
            ),
            const SizedBox(height: 12),
            AppField(
              controller: _description,
              label: 'Details',
              hint:
                  'What does done look like? Anything an agent would need to know.',
              minLines: 4,
              maxLines: 8,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            Btn(
              _busy ? 'Creating…' : 'Create task',
              full: true,
              disabled: _busy,
              icon: 'plus',
              onTap: _submit,
            ),
          ],
        ),
      );
}
