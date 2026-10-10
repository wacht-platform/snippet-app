import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';

/// One agent on the phone's Agents page, in the Mission Control card's shape:
/// who it is, whether it is working, and its task counts.
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
  });

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> {
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

  Widget _chip(String label, {Color? dot, bool accent = false}) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: accent
              ? AppColors.accentBg
              : (kMobile ? AppColors.surface2 : AppColors.surface3),
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          SwapText(label,
              style: sans(12,
                  height: 16 / 12,
                  color: accent ? AppColors.accent : AppColors.fg2)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final working = _count({TaskStatus.inProgress}, {'in_progress'});
    final queued = _count({TaskStatus.todo}, {'todo'});
    final blocked =
        _count({TaskStatus.blocked, TaskStatus.failed}, {'blocked', 'failed'});
    final done = _count({TaskStatus.done}, {'done'});
    final role = agent.role.trim();
    final (status, dot) = !agent.available
        ? ('Paused', AppColors.fg4)
        : working > 0
            ? (
                'Working on $working ${working == 1 ? 'task' : 'tasks'}',
                AppColors.run
              )
            : ('Available', AppColors.ok);
    final chips = <Widget>[
      if (queued > 0) _chip('$queued queued'),
      if (blocked > 0) _chip('$blocked blocked', dot: AppColors.danger),
      if (done > 0)
        _chip(agent.taskCounts != null ? '$done done this week' : '$done done'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: AnimatedSize(
            duration: Motion.base,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            kMobile ? AppColors.surface2 : AppColors.surface3,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(name.characters.first.toUpperCase(),
                          style: sans(16, color: AppColors.fg1)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(16,
                                  spacing: -0.2,
                                  height: 21 / 16,
                                  color: AppColors.fg1)),
                          Row(children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: dot, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: SwapText(
                                  role.isEmpty ? status : '$status · $role',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(12,
                                      height: 16 / 12, color: AppColors.fg3)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                  ]),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
