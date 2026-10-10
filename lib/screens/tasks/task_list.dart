import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../platform.dart';
import '../../components.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../shell_nav.dart' show kNavPadH, kNavRowHeight;
import 'task_common.dart';

/// Tasks grouped by status, in board order, narrowed by a search and a status
/// filter. The phone tab, the desktop sidebar and the standalone screen all
/// render this, so the three cannot disagree about order or grouping.
class TaskList extends StatelessWidget {
  const TaskList({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.onRefresh,
    this.query = '',
    this.filter = const {},
    this.padding,
  });

  final List<TaskItem> tasks;
  final ValueChanged<TaskItem> onOpen;
  final Future<void> Function() onRefresh;
  final String query;

  /// Statuses to show; empty means all of them.
  final Set<TaskStatus> filter;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final visible = tasks
        .where((t) => filter.isEmpty || filter.contains(t.status))
        .where((t) => taskMatches(t, query))
        .toList();
    final pad = padding ??
        (kMobile
            ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 24)
            : const EdgeInsets.fromLTRB(8, 0, 8, 18));
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: pad, children: [_empty()]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          for (final status in TaskStatus.values)
            ..._group(status, visible.where((t) => t.status == status)),
        ],
      ),
    );
  }

  List<Widget> _group(TaskStatus status, Iterable<TaskItem> items) {
    if (items.isEmpty) return const [];
    if (kMobile) {
      final list = items.toList();
      return [
        TaskStatusHeader(status: status, count: list.length),
        for (var i = 0; i < list.length; i++)
          TaskRow(
              task: list[i],
              onTap: () => onOpen(list[i]),
              divider: i < list.length - 1),
      ];
    }
    return [
      TaskStatusHeader(status: status, count: items.length),
      for (final task in items) TaskRow(task: task, onTap: () => onOpen(task)),
    ];
  }

  // Three different empties: nothing filed, nothing matching the search, and
  // nothing in the chosen columns.
  Widget _empty() {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: 'layers',
        title: 'No tasks yet',
        body: 'File a task and Mission Control routes it to a session.',
      );
    }
    if (query.trim().isNotEmpty) {
      return EmptyState(
        icon: 'search',
        title: 'No matching tasks',
        body: 'Nothing matches “${query.trim()}”.',
      );
    }
    return EmptyState(
      icon: 'layers',
      title: filter.length == 1
          ? 'Nothing in ${filter.first.label}'
          : 'Nothing in ${filter.length} columns',
      body: 'Try another column, or clear the filter.',
    );
  }
}

class TaskStatusHeader extends StatelessWidget {
  const TaskStatusHeader(
      {super.key, required this.status, required this.count});
  final TaskStatus status;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(0, 22, 0, 2)
            : const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: statusColor(status), shape: BoxShape.circle),
          ),
          const SizedBox(width: S.s8),
          Text(status.label,
              style: kMobile ? sans(13, color: AppColors.fg2) : TS.label()),
          const SizedBox(width: S.s8),
          if (kMobile)
            Text('$count', style: sans(13, color: AppColors.fg4))
          else
            CountBadge(count),
        ]),
      );
}

/// One task. Desktop gets a single dense line; a phone adds the first line of
/// the description, so a row says what the work is without opening it.
class TaskRow extends StatelessWidget {
  const TaskRow(
      {super.key,
      required this.task,
      required this.onTap,
      this.divider = false});
  final TaskItem task;
  final VoidCallback onTap;

  /// A hairline under the row, between rows of one status on a phone.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final detail = task.description.trim().split('\n').first;
    final age = taskAge(task);
    if (kMobile) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: AppColors.border))
                : null,
          ),
          child: Row(children: [
            if (task.priority > 0) ...[
              PriorityMark(task.priority),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16, height: 21 / 16, color: AppColors.fg1)),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 18 / 13, color: AppColors.fg3)),
                  ],
                ],
              ),
            ),
            if (age.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(age, style: sans(12, color: AppColors.fg4, tabular: true)),
            ],
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(kMobile ? R.md : R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kMobile ? R.md : R.sm),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: kMobile ? M.rowHeight : kNavRowHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: kMobile ? M.rowPadH : kNavPadH,
                  vertical: kMobile ? 8 : 0),
              child: Row(children: [
                if (task.priority > 0) ...[
                  PriorityMark(task.priority),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kMobile
                              ? TS.rowTitle(AppColors.fg2)
                              : TS.label()),
                      if (kMobile && detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ],
                    ],
                  ),
                ),
                if (age.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(age, style: TS.meta(AppColors.fg4)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Priority as a mark: nothing at the default, a small chip when raised.
class PriorityMark extends StatelessWidget {
  const PriorityMark(this.priority, {super.key});
  final int priority;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: AppColors.accentBg,
            borderRadius: BorderRadius.circular(R.xs)),
        child: Text('P$priority',
            style: sans(11, weight: W.label, color: AppColors.accent)),
      );
}

/// Pick which statuses to show. Empty means all of them.
Future<Set<TaskStatus>?> showTaskFilter(BuildContext context,
    {required Set<TaskStatus> selected, required List<TaskItem> tasks}) {
  return showAppSheet<Set<TaskStatus>>(
    context,
    title: 'Filter by status',
    child: _FilterPanel(
      selected: selected,
      counts: {
        for (final s in TaskStatus.values)
          s: tasks.where((t) => t.status == s).length,
      },
    ),
  );
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({required this.selected, required this.counts});

  final Set<TaskStatus> selected;
  final Map<TaskStatus, int> counts;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final Set<TaskStatus> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            label: 'All statuses',
            selected: _selected.isEmpty,
            onTap: () => setState(() => _selected.clear()),
          ),
          if (kMobile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Container(height: 1, color: AppColors.line),
            )
          else
            const SizedBox(height: S.s8),
          for (final s in TaskStatus.values)
            _row(
              label: s.label,
              count: widget.counts[s] ?? 0,
              dot: statusColor(s),
              selected: _selected.contains(s),
              onTap: () => setState(() {
                if (!_selected.remove(s)) _selected.add(s);
              }),
            ),
          const SizedBox(height: S.s16),
          // "Apply", not "Done": Done is already a status row above.
          Btn('Apply',
              full: true,
              onTap: () => Navigator.pop<Set<TaskStatus>>(context, _selected)),
        ],
      );

  Widget _row({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    Color? dot,
  }) =>
      kMobile
          ? _mobileRow(
              label: label,
              selected: selected,
              onTap: onTap,
              count: count,
              dot: dot)
          : Padding(
              padding: const EdgeInsets.only(bottom: S.s2),
              child: Material(
                color: selected ? AppColors.accentBg : Colors.transparent,
                borderRadius: BorderRadius.circular(R.md),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  borderRadius: BorderRadius.circular(R.md),
                  child: Container(
                    height: kMobile ? M.minTarget + 4 : 36,
                    padding: const EdgeInsets.symmetric(horizontal: S.s12),
                    child: Row(children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? AppColors.accentFill
                              : Colors.transparent,
                          border: Border.all(
                              color: selected
                                  ? AppColors.accentFill
                                  : AppColors.lineStrong,
                              width: 1.5),
                        ),
                        child: selected
                            ? AppIcon('check',
                                size: 12, color: AppColors.accentFg)
                            : null,
                      ),
                      const SizedBox(width: S.s12),
                      if (dot != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: S.s8),
                      ],
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS
                                .ui(selected ? AppColors.fg1 : AppColors.fg2)),
                      ),
                      if (count != null) Text('$count', style: TS.meta()),
                    ]),
                  ),
                ),
              ),
            );

  Widget _mobileRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    Color? dot,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(16,
                      color: selected ? AppColors.accent : AppColors.fg1)),
            ),
            if (count != null)
              Text('$count',
                  style: sans(14, color: AppColors.fg3, tabular: true)),
            SizedBox(
              width: 32,
              child: selected
                  ? Align(
                      alignment: Alignment.centerRight,
                      child:
                          AppIcon('check', size: 18, color: AppColors.accent))
                  : null,
            ),
          ]),
        ),
      );
}
