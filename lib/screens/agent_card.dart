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

  Widget _pill(String label, {bool alert = false}) => Container(
        height: kMobile ? 24 : 20,
        padding: EdgeInsets.symmetric(horizontal: kMobile ? 9 : 7),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface2 : AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (alert) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: AppColors.danger, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          SwapText(label,
              style: sans(kMobile ? 12 : 11,
                  height: 16 / 12, color: AppColors.fg2)),
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
    final open = working + queued + blocked;
    final role = agent.role.trim();
    final (status, dot) = !agent.available
        ? ('Paused', AppColors.fg4)
        : working > 0
            ? ('Working', AppColors.run)
            : ('Available', AppColors.ok);
    if (!kMobile) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  if (role.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(11.5, color: AppColors.fg4)),
                    ),
                  ],
                ]),
              ),
              if (open > 0) ...[
                const SizedBox(width: 6),
                _pill('$open', alert: blocked > 0),
              ],
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? 10 : 6),
      child: Material(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                kMobile ? 18 : 14, kMobile ? 14 : 11, kMobile ? 12 : 10,
                kMobile ? 14 : 11),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 16 : 14,
                            spacing: -0.2,
                            height: kMobile ? 21 / 16 : 19 / 14,
                            color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
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
              if (open > 0) ...[
                const SizedBox(width: 10),
                _pill('$open ${open == 1 ? 'task' : 'tasks'}',
                    alert: blocked > 0),
              ],
              const SizedBox(width: 6),
              AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}
