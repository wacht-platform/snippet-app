import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../list_search_field.dart';
import 'task_common.dart';
import 'task_list.dart' show PriorityMark;

/// The task board as columns, for a wide window.
///
/// Cards drag between columns to change status. In progress takes no drops:
/// only a dispatch starts work, because only a dispatch binds the session
/// allowed to report it. A move shows at once and is corrected if the daemon
/// refuses it.
class TaskKanban extends StatefulWidget {
  const TaskKanban({super.key, required this.client});

  final DaemonClient client;

  @override
  State<TaskKanban> createState() => _TaskKanbanState();
}

/// Column widths: expanded columns share the pane between these bounds, and a
/// folded column is a slim strip.
const double _minColumn = 248;
const double _maxColumn = 360;
const double _foldedColumn = 48;

class _TaskKanbanState extends State<TaskKanban> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  /// The card being dragged, so columns can say whether they take it.
  TaskItem? _dragging;

  /// Failed and cancelled work is kept but folded away, the way modern boards
  /// treat finished columns; a click opens one. Remembered on this device.
  final Set<TaskStatus> _folded = {TaskStatus.failed, TaskStatus.cancelled};
  static const _foldedKey = 'tasks_board_folded';

  @override
  void initState() {
    super.initState();
    _loadFolded();
  }

  Future<void> _loadFolded() async {
    try {
      final saved = (await SharedPreferences.getInstance())
          .getStringList(_foldedKey);
      if (saved == null || !mounted) return;
      setState(() => _folded
        ..clear()
        ..addAll(TaskStatus.values.where((s) => saved.contains(s.wire))));
    } catch (_) {}
  }

  Future<void> _saveFolded() async {
    try {
      await (await SharedPreferences.getInstance())
          .setStringList(_foldedKey, [for (final s in _folded) s.wire]);
    } catch (_) {}
  }
  double _columnWidth = _minColumn;

  @override
  void didUpdateWidget(covariant TaskKanban oldWidget) {
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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  Future<void> _open(TaskItem task) async {
    await openTaskDetail(context, widget.client, task.id);
    if (mounted) await _feed.refresh();
  }

  static bool _accepts(TaskStatus column, TaskItem task) =>
      column != TaskStatus.inProgress && column != task.status;

  Future<void> _move(TaskItem task, TaskStatus to) async {
    HapticFeedback.selectionClick();
    _feed.replace(task.movedTo(to));
    try {
      _feed.replace(await widget.client.setTaskStatus(task.id, to));
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Could not move “${task.title}”: $e', danger: true);
      await _feed.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: readingBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          Expanded(child: _board()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final open = _feed.tasks.where((t) => !_finished(t.status)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(children: [
        Text('Tasks', style: TS.sectionTitle()),
        const SizedBox(width: 10),
        if (!_feed.loading)
          Text('$open open', style: TS.meta()),
        const Spacer(),
        SizedBox(
          width: 240,
          child: ListSearchField(
            controller: _search,
            hint: 'Search tasks',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 8),
        Btn('New task', small: true, icon: 'plus', onTap: _create),
      ]),
    );
  }

  static bool _finished(TaskStatus s) =>
      s == TaskStatus.done || s == TaskStatus.failed || s == TaskStatus.cancelled;

  Widget _board() {
    if (_feed.loading) {
      return Center(child: Spinner(size: 20, color: AppColors.fg3));
    }
    final error = _feed.error;
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load tasks', style: sans(13, color: AppColors.fg2)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: _feed.refresh),
        ]),
      );
    }
    final visible =
        _feed.tasks.where((t) => taskMatches(t, _query)).toList();
    return LayoutBuilder(builder: (context, constraints) {
      // Open columns fill the pane when they fit, so a board with room never
      // scrolls sideways; a narrow pane scrolls at the minimum width.
      final open = TaskStatus.values.length - _folded.length;
      final room = constraints.maxWidth - 32 - _folded.length * (_foldedColumn + 8);
      _columnWidth = (room / open - 8).clamp(_minColumn, _maxColumn);
      return Scrollbar(
        controller: _scroll,
        child: ListView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final status in TaskStatus.values)
              _column(
                  status, visible.where((t) => t.status == status).toList()),
          ],
        ),
      );
    });
  }

  Widget _column(TaskStatus status, List<TaskItem> items) {
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (d) => _accepts(status, d.data),
      onAcceptWithDetails: (d) => _move(d.data, status),
      builder: (context, candidates, _) {
        final dragging = _dragging;
        final hovering = candidates.isNotEmpty;
        final refuses = dragging != null &&
            dragging.status != status &&
            !_accepts(status, dragging);
        if (_folded.contains(status)) {
          return _foldedStrip(status, items.length, hovering);
        }
        return AnimatedContainer(
          duration: Motion.fast,
          width: _columnWidth,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: hovering ? AppColors.surface2 : AppColors.bg,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Opacity(
            opacity: refuses ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _columnHeader(status, items.length),
                Expanded(
                  child: items.isEmpty
                      ? _emptyColumn(status, refuses)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _draggableCard(items[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleFold(TaskStatus status) {
    setState(() {
      if (!_folded.remove(status)) _folded.add(status);
    });
    _saveFolded();
  }

  /// A folded column: its dot, count and name on end. Still a drop target, so
  /// a card can be dropped on it without opening it.
  Widget _foldedStrip(TaskStatus status, int count, bool hovering) => Tooltip(
        message: 'Show ${status.label}',
        child: InkWell(
          onTap: () => _toggleFold(status),
          borderRadius: BorderRadius.circular(R.lg),
          child: AnimatedContainer(
            duration: Motion.fast,
            width: _foldedColumn,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              color: hovering ? AppColors.surface2 : AppColors.bg,
              borderRadius: BorderRadius.circular(R.lg),
            ),
            child: Column(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: statusColor(status), shape: BoxShape.circle),
              ),
              const SizedBox(height: 10),
              Text('$count', style: TS.meta()),
              const SizedBox(height: 12),
              RotatedBox(
                quarterTurns: 1,
                child: Text(status.label, style: TS.label()),
              ),
            ]),
          ),
        ),
      );

  Widget _columnHeader(TaskStatus status, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: statusColor(status), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(status.label, style: TS.label(AppColors.fg1)),
          const SizedBox(width: 8),
          Text('$count', style: TS.meta()),
          const Spacer(),
          IconBtn('minimize',
              size: 24,
              iconSize: 14,
              tooltip: 'Fold ${status.label}',
              onTap: () => _toggleFold(status)),
        ]),
      );

  Widget _emptyColumn(TaskStatus status, bool refuses) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(
                status == TaskStatus.inProgress
                    ? (refuses ? 'Only a dispatch starts work' : 'Nothing running')
                    : 'No tasks',
                style: TS.meta(AppColors.fg4)),
          ),
        ),
      );

  Widget _draggableCard(TaskItem task) {
    final card = _TaskCard(task: task, onTap: () => _open(task));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Draggable<TaskItem>(
        data: task,
        onDragStarted: () => setState(() => _dragging = task),
        onDragEnd: (_) => setState(() => _dragging = null),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: _columnWidth - 16,
            child: Transform.rotate(
              angle: -0.02,
              child: _TaskCard(task: task, lifted: true),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: card,
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({required this.task, this.onTap, this.lifted = false});

  final TaskItem task;
  final VoidCallback? onTap;
  final bool lifted;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final detail = t.description.trim();
    final age = taskAge(t);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _hover || widget.lifted
                ? AppColors.surface2
                : AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            boxShadow: widget.lifted
                ? const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 8)),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TS.label(AppColors.fg1)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta()),
              ],
              if (t.priority > 0 || age.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  if (t.priority > 0) ...[
                    PriorityMark(t.priority),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  if (age.isNotEmpty) Text(age, style: TS.caption(AppColors.fg4)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
