import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';
import '../mochi.dart';
import 'mochi_color_picker.dart';

/// One agent on the phone's Agents page, in the Mission Control card's shape:
/// who it is, whether it is working, and its task counts.
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
    this.onDelete,
  });

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> {
  Future<void> _actions(Offset? point) async {
    final name = widget.agent.displayName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.displayName.trim();
    if (kMobile) {
      showAppSheet(context,
          title: name,
          child: SheetActions([
            SheetAction('sparkles', 'Change colour', () {
              Navigator.pop(context);
              showMochiColorPicker(context, widget.client, widget.agent.id, name);
            }),
            if (widget.onDelete != null)
              SheetAction('trash', 'Delete agent', () {
                Navigator.pop(context);
                widget.onDelete?.call();
              }, danger: true),
          ]));
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      point: point,
      anchor: point == null ? context : null,
      items: [
        appMenuItem(value: 'color', icon: 'sparkles', label: 'Change colour'),
        if (widget.onDelete != null)
          appMenuItem(
              value: 'delete', icon: 'trash', label: 'Delete agent', danger: true),
      ],
    );
    if (picked == 'delete') widget.onDelete?.call();
    if (picked == 'color' && mounted) {
      showMochiColorPicker(context, widget.client, widget.agent.id, name,
          point: point);
    }
  }

  List<TaskItem> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentCard old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client || old.agent.id != widget.agent.id) _load();
  }

  Future<void> _load() async {
    if (widget.agent.taskCounts != null) return;
    final id = widget.agent.id;
    try {
      final tasks = await widget.client.tasks(agentId: id, limit: 100);
      if (mounted) setState(() => _tasks = tasks);
    } catch (_) {}
  }

  int _count(Set<TaskStatus> statuses, Set<String> keys) =>
      widget.agent.taskCounts != null
          ? widget.agent.tasksIn(keys)
          : _tasks.where((t) => statuses.contains(t.status)).length;

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final working = _count({TaskStatus.inProgress}, {'in_progress'});
    final queued = _count({TaskStatus.todo}, {'todo'});
    final blocked =
        _count({TaskStatus.blocked, TaskStatus.failed}, {'blocked', 'failed'});
    final open = working + queued + blocked;
    final done = _count({TaskStatus.done}, {'done'});
    final role = agent.role.trim();
    final status = !agent.available
        ? 'Paused'
        : working > 0
            ? 'Working'
            : 'Available';
    final (summary, summaryColor) = !agent.available
        ? ('Paused', AppColors.fg4)
        : blocked > 0
            ? ('$blocked blocked', AppColors.danger)
            : open > 0
                ? ('$open open', AppColors.fg3)
                : done > 0
                    ? ('$done done', AppColors.fg4)
                    : ('No tasks', AppColors.fg4);
    final nameSize = kMobile ? 15.5 : 13.0;
    final metaSize = kMobile ? 13.0 : 11.5;
    final segments = [
      (working, AppColors.run),
      (queued, AppColors.surface3),
      (blocked, AppColors.danger),
      (done, AppColors.ok.withValues(alpha: 0.55)),
    ].where((e) => e.$1 > 0).toList();
    final barHeight = kMobile ? 4.0 : 3.0;
    return GestureDetector(
      onSecondaryTapUp: kMobile ? null : (d) => _actions(d.globalPosition),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kMobile ? 0 : 8),
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () => _actions(null),
          borderRadius: BorderRadius.circular(kMobile ? 0 : 8),
          child: Padding(
            padding: kMobile
                ? const EdgeInsets.fromLTRB(16, 13, 16, 13)
                : const EdgeInsets.fromLTRB(10, 8, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Opacity(
                      opacity: agent.available ? 1 : 0.5,
                      child: AgentMochi(agent.id, size: kMobile ? 22 : 18),
                    ),
                    SizedBox(width: kMobile ? 10 : 8),
                    Flexible(
                      flex: 0,
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(nameSize,
                              weight: kMobile ? W.label : W.body,
                              color: agent.available
                                  ? AppColors.fg1
                                  : AppColors.fg3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(role.isEmpty ? status : role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(metaSize, color: AppColors.fg4)),
                    ),
                    const SizedBox(width: 8),
                    SwapText(summary,
                        style: sans(metaSize,
                            color: summaryColor, tabular: true)),
                  ],
                ),
                SizedBox(height: kMobile ? 9 : 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(barHeight),
                  child: SizedBox(
                    height: barHeight,
                    child: segments.isEmpty
                        ? ColoredBox(
                            color: AppColors.surface2,
                            child: const SizedBox.expand())
                        : Row(children: [
                            for (var j = 0; j < segments.length; j++) ...[
                              if (j > 0) const SizedBox(width: 2),
                              Expanded(
                                flex: segments[j].$1,
                                child: ColoredBox(
                                    color: segments[j].$2,
                                    child: const SizedBox.expand()),
                              ),
                            ],
                          ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
