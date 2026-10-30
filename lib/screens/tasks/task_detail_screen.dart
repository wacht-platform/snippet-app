import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../coordination/coordination_thread_state.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mochi.dart';
import '../mobile_chrome.dart';
import 'task_common.dart' show statusColor;

/// One task: its state, its roster, its links, and its own message room.
///
/// The room is the whole point of a task owning a thread. Agents assigned to
/// this task — and the human — read and post here, and nobody on a DIFFERENT
/// task is woken by it, which is what a single global board could not give.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.client,
    required this.taskId,
    this.onClose,
    this.embedded = false,
    this.pane = false,
  });

  final DaemonClient client;
  final String taskId;
  final VoidCallback? onClose;
  final bool embedded;
  final bool pane;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskItem? task;
  List<TaskAgent> roster = const [];
  TaskLinks links = const TaskLinks();
  bool loading = true;
  String? error;
  bool busy = false;

  CoordinationThreadState? room;
  final _composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    room?.removeListener(_onRoomChanged);
    room?.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final task = await widget.client.getTask(widget.taskId);
      final roster = await widget.client.taskAgents(widget.taskId);
      final links = await widget.client.taskLinks(widget.taskId);
      if (!mounted) return;
      // The room is keyed by the task's own thread id, which the daemon derives
      // from the task — so a client never invents one, and reconnecting lands in
      // the same conversation.
      final room = CoordinationThreadState(
          client: widget.client, threadId: task.threadId)
        ..addListener(_onRoomChanged);
      room.attachLive();
      unawaited(room.refresh());
      setState(() {
        this.task = task;
        this.roster = roster;
        this.links = links;
        this.room = room;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _publish(TaskItem t) {
    final feed = widget.client.swr.entry<List<TaskItem>>('coordination:tasks');
    final data = feed.data;
    if (data == null) return;
    feed.mutate([for (final x in data) x.id == t.id ? t : x]);
  }

  Future<void> _setStatus(TaskStatus status) async {
    final before = task;
    if (before == null) return;
    final moved = before.movedTo(status);
    setState(() => task = moved);
    _publish(moved);
    try {
      final updated = await widget.client.setTaskStatus(widget.taskId, status);
      if (!mounted) return;
      setState(() => task = updated);
      _publish(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => task = before);
      _publish(before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _addAgent() async {
    final agents = await widget.client.coordinationAgents();
    if (!mounted) return;
    final onTask = roster.where((r) => r.active).map((r) => r.agentId).toSet();
    // Mission Control is not a task agent — it coordinates — so it is not
    // offered for membership either.
    final candidates = agents
        .where((a) => !onTask.contains(a.id) && !a.isMissionControl)
        .toList();
    if (candidates.isEmpty) {
      toast(context, 'Every agent is already on this task');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Add an agent',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in candidates)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(a.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(children: [
                    AppIcon('agent', size: 16, color: AppColors.fg3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          a.displayName.trim().isEmpty ? a.id : a.displayName,
                          style: sans(13, color: AppColors.fg1)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final before = roster;
    setState(() => roster = [
          ...roster,
          TaskAgent.fromJson({
            'task_id': widget.taskId,
            'agent_id': picked,
            'role': 'implementer',
            'status': roster.any((r) => r.active) ? 'waiting' : 'active',
            'added_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ]);
    try {
      await widget.client.addTaskAgent(widget.taskId, picked);
      final updated = await widget.client.taskAgents(widget.taskId);
      if (!mounted) return;
      setState(() => roster = updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => roster = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _transferLeaseTo(TaskAgent target) async {
    final currentActive = roster.firstWhere(
      (a) => a.hasSessionLease && a.active,
      orElse: () => roster.first,
    );
    final confirm = await showAppSheet<bool>(
      context,
      title: 'Transfer session lease',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Transfer the active work session lease to ${target.agentId}?\nOnly one agent can work in the session at a time.',
              style: sans(13, color: AppColors.fg2, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel', style: sans(13, color: AppColors.fg3)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Transfer lease', style: sans(13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final before = roster;
    TaskAgent withStatus(TaskAgent a, String status) => TaskAgent.fromJson({
          'task_id': a.taskId,
          'agent_id': a.agentId,
          'role': a.role,
          'work_session_id': a.workSessionId,
          'scope': a.scope,
          'status': status,
          'added_at': a.addedAt,
          'removed_at': a.removedAt,
        });
    setState(() => roster = [
          for (final a in roster)
            a.agentId == target.agentId
                ? withStatus(a, 'active')
                : a.agentId == currentActive.agentId
                    ? withStatus(a, 'waiting')
                    : a
        ]);
    try {
      await widget.client.transferTaskLease(
        widget.taskId,
        currentActive.agentId,
        target.agentId,
      );
      final updated = await widget.client.taskAgents(widget.taskId);
      if (mounted) setState(() => roster = updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => roster = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _linkTask() async {
    final cached =
        widget.client.swr.entry<List<TaskItem>>('coordination:tasks').data;
    final all = cached ?? await widget.client.tasks();
    if (!mounted) return;
    final other = all.where((t) => t.id != widget.taskId).toList();
    if (other.isEmpty) {
      toast(context, 'No other task to link to');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Blocks which task?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in other)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(t.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.client.linkTasks(widget.taskId, picked);
      final updated = await widget.client.taskLinks(widget.taskId);
      if (!mounted) return;
      setState(() => links = updated);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final room = this.room;
    if (text.isEmpty || room == null) return;
    _composer.clear();
    final sent = await room.send(
      actorKind: 'human',
      actorId: 'local',
      body: text,
      // Stable per attempt so a retried send cannot double-post.
      idempotencyKey:
          'task-${widget.taskId}-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (sent == null) _composer.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Scaffold(
      backgroundColor: !kMobile && (widget.embedded || widget.pane)
          ? Colors.transparent
          : AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (!kMobile && widget.pane)
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.s40, S.s32, S.s40, S.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t?.title ?? 'Task',
                          style: sans(20,
                              weight: W.strong,
                              spacing: -0.2,
                              color: AppColors.fg1)),
                      if (t != null) ...[
                        const SizedBox(height: S.s4),
                        Text(t.status.label,
                            style: sans(13, color: AppColors.fg3)),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else if (kMobile)
            MobileBackBar(
              title: t?.title ?? 'Task',
              subtitle: t?.status.label,
              onTitleTap: () {},
            )
          else if (widget.embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
              child: Row(children: [
                IconBtn(
                  'chevron-left',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Back',
                  onTap: widget.onClose ?? () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(t?.title ?? 'Task',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                ),
              ]),
            )
          else
            SnAppBar(
              title: t?.title ?? 'Task',
              compact: true,
              bordered: false,
            ),
          Expanded(
            child: !kMobile && widget.pane
                ? Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.s24),
                        child: _body(t),
                      ),
                    ),
                  )
                : _body(t),
          ),
        ]),
      ),
    );
  }

  Widget _body(TaskItem? t) {
    return loading
        ? const Center(child: DelayedSpinner(size: 22))
        : error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error!,
                      textAlign: TextAlign.center,
                      style: sans(12, color: AppColors.danger)),
                ),
              )
            : t == null
                ? const EmptyState(icon: 'layers', title: 'Task not found')
                : Column(children: [
                    Expanded(
                      child: CustomScrollView(slivers: [
                        SliverToBoxAdapter(child: _meta(t)),
                        SliverToBoxAdapter(
                            child: Divider(height: 1, color: AppColors.line)),
                        ..._roomSlivers(),
                      ]),
                    ),
                    _composerBar(),
                  ]);
  }

  Widget _meta(TaskItem t) => Padding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(20, 8, 20, 16)
            : const EdgeInsets.fromLTRB(S.s16, S.s12, S.s16, S.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.description.trim().isNotEmpty) ...[
              _Description(markdown: t.description),
              const SizedBox(height: S.s12),
            ],
            if (t.workPlan.isNotEmpty) ...[
              _WorkPlan(steps: t.workPlan),
              const SizedBox(height: S.s12),
            ],
            // Column picker. The current state is always shown, so the row
            // reads as the task's position; In progress is never offered, as
            // only a dispatch starts work.
            Container(
              height: kMobile ? 44 : 32,
              padding: kMobile ? const EdgeInsets.all(4) : EdgeInsets.zero,
              decoration: kMobile
                  ? BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.fg1.withValues(alpha: 0.08),
                            spreadRadius: 1),
                      ],
                    )
                  : null,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in TaskStatus.values)
                    if (s == t.status ||
                        (s != TaskStatus.inProgress &&
                            (s == TaskStatus.todo ||
                                !{
                                  TaskStatus.done,
                                  TaskStatus.failed,
                                  TaskStatus.cancelled
                                }.contains(t.status))))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: busy || s == t.status
                                ? null
                                : () => _setStatus(s),
                            borderRadius:
                                BorderRadius.circular(kMobile ? 18 : R.chip),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: kMobile ? 13 : 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                // Same chip rule as the board's filter bar: the
                                // surface STEP separates, never a hairline.
                                color: s == t.status
                                    ? (kMobile
                                        ? AppColors.surface3
                                        : AppColors.surface2)
                                    : (kMobile
                                        ? Colors.transparent
                                        : AppColors.surface3),
                                borderRadius: BorderRadius.circular(
                                    kMobile ? 18 : R.chip),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (s == t.status) ...[
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                            color: statusColor(s),
                                            shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: S.s6),
                                    ],
                                    Text(s.label,
                                        style: sans(kMobile ? 14 : 12,
                                            weight: s == t.status
                                                ? W.label
                                                : W.body,
                                            color: s == t.status
                                                ? AppColors.fg1
                                                : AppColors.fg3)),
                                  ]),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _section('Agents', onAdd: _addAgent),
            if (roster.isEmpty)
              Text('Nobody assigned yet.', style: TS.meta())
            else if (kMobile)
              Column(children: [
                for (final a in roster)
                  InkWell(
                    onTap: (a.active && !a.hasSessionLease)
                        ? () => _transferLeaseTo(a)
                        : null,
                    child: SizedBox(
                      height: 48,
                      child: Row(children: [
                        a.hasSessionLease
                            ? WorkingMochi(
                                size: 22, color: mochiColorFor(a.agentId))
                            : AgentMochi(a.agentId, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(a.agentId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(15.5,
                                  color: a.active
                                      ? AppColors.fg1
                                      : AppColors.fg3)),
                        ),
                        Text(
                            a.hasSessionLease
                                ? 'working'
                                : (a.active ? 'waiting' : 'left'),
                            style: sans(13,
                                color: a.hasSessionLease
                                    ? AppColors.accent
                                    : AppColors.fg4)),
                      ]),
                    ),
                  ),
              ])
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(children: [
                  for (var i = 0; i < roster.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: AppColors.line),
                    InkWell(
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(10) : Radius.zero,
                        bottom: i == roster.length - 1
                            ? const Radius.circular(10)
                            : Radius.zero,
                      ),
                      onTap: (roster[i].active && !roster[i].hasSessionLease)
                          ? () => _transferLeaseTo(roster[i])
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(children: [
                          roster[i].hasSessionLease
                              ? WorkingMochi(
                                  size: 18,
                                  color: mochiColorFor(roster[i].agentId))
                              : AgentMochi(roster[i].agentId, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(roster[i].agentId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(12.5,
                                    color: roster[i].active
                                        ? AppColors.fg1
                                        : AppColors.fg3)),
                          ),
                          Text(
                            roster[i].hasSessionLease
                                ? 'working'
                                : (roster[i].active ? 'waiting' : 'left'),
                            style: sans(11.5,
                                color: roster[i].hasSessionLease
                                    ? AppColors.accent
                                    : AppColors.fg4),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            const SizedBox(height: 14),
            _section('Related', onAdd: _linkTask),
            if (links.links.isEmpty && links.blockedBy.isEmpty)
              Text('No linked tasks.', style: TS.meta())
            else ...[
              // Blockers first: "what is holding this up" is the question the
              // links exist to answer.
              for (final blocker in links.blockedBy)
                _linkRow('Blocked by', blocker, AppColors.danger),
              for (final l in links.links)
                if (l.kind == TaskLinkKind.relatesTo)
                  _linkRow(
                      'Relates to',
                      l.toTaskId == t.id ? l.fromTaskId : l.toTaskId,
                      AppColors.fg3),
            ],
          ],
        ),
      );

  Widget _section(String label, {required VoidCallback onAdd}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: kMobile
                  ? sans(12,
                      weight: W.label, spacing: 0.7, color: AppColors.fg4)
                  : caps(11, color: AppColors.fg3)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(12, 8, 0, 8)
                  : const EdgeInsets.all(2),
              child: AppIcon('plus',
                  size: kMobile ? 16 : 14, color: AppColors.fg3),
            ),
          ),
        ]),
      );

  Widget _linkRow(String prefix, String id, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$prefix  ', style: sans(11, color: color)),
          Expanded(
            child: Text(id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg3)),
          ),
        ]),
      );

  List<Widget> _roomSlivers() {
    final room = this.room;
    if (room == null) return const [];
    if (room.events.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: S.s16),
            child: EmptyState(
              icon: 'message-text',
              title: 'No messages yet',
              body: 'Agents on this task talk here. You can post too.',
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(20, 18, 20, 12)
            : const EdgeInsets.all(S.s12),
        sliver: SliverList.builder(
          itemCount: room.events.length,
          itemBuilder: (_, i) {
            final e = room.events[i];
            final mine = e.actorKind == 'human';
            final body = e.payload['body']?.toString() ?? '';
            if (body.trim().isEmpty) return const SizedBox.shrink();
            if (kMobile) {
              final md = MarkdownBody(
                data: body,
                selectable: true,
                styleSheet:
                    mine ? markdownStyle(context) : agentMarkdownStyle(context),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (txt, href, title) =>
                    openMarkdownLink(href, context),
              );
              if (mine) {
                return Padding(
                  padding: const EdgeInsets.only(left: 48, bottom: 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 11),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: md,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AgentMochi(e.actorId, size: 18),
                      const SizedBox(width: 8),
                      Text(e.actorId,
                          style:
                              sans(13, weight: W.label, color: AppColors.fg2)),
                    ]),
                    const SizedBox(height: 6),
                    md,
                  ],
                ),
              );
            }
            if (mine) {
              return Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: MarkdownBody(
                      data: body,
                      selectable: true,
                      styleSheet: markdownStyle(context),
                      builders: {'pre': PreBlockBuilder()},
                      onTapLink: (txt, href, title) =>
                          openMarkdownLink(href, context),
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AgentMochi(e.actorId, size: 16),
                    const SizedBox(width: 6),
                    Text(e.actorId,
                        style: sans(12, weight: W.label, color: AppColors.fg2)),
                  ]),
                  const SizedBox(height: 5),
                  MarkdownBody(
                    data: body,
                    selectable: true,
                    styleSheet: markdownStyle(context),
                    builders: {'pre': PreBlockBuilder()},
                    onTapLink: (txt, href, title) =>
                        openMarkdownLink(href, context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _composerBar() => kMobile
      ? SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.fg1.withValues(alpha: 0.08),
                      spreadRadius: 1),
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    style: sans(16, color: AppColors.fg1),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Message this task…',
                      hintStyle: sans(16, color: AppColors.fg4),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: (room?.sending ?? false) ? null : _send,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.accentFill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon('arrow-up',
                        size: 16, color: AppColors.accentFg),
                  ),
                ),
              ]),
            ),
          ),
        )
      : SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    style: sans(13, color: AppColors.fg1),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Message this task…',
                      hintStyle: sans(13, color: AppColors.fg4),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: (room?.sending ?? false) ? null : _send,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: AppColors.accentFill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon('arrow-up',
                        size: 13, color: AppColors.accentFg),
                  ),
                ),
              ]),
            ),
          ),
        );
}

/// The worker's plan for the task, as it ticks steps off.
class _WorkPlan extends StatelessWidget {
  const _WorkPlan({required this.steps});
  final List<WorkStep> steps;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plan · $done/${steps.length}',
            style: sans(12.5, weight: FontWeight.w500, color: AppColors.fg3)),
        const SizedBox(height: 8),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: s.done
                    ? AppIcon('check', size: 14, color: AppColors.ok)
                    : Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.current ? AppColors.accent : null,
                          border: Border.all(
                              color:
                                  s.current ? AppColors.accent : AppColors.fg4,
                              width: 1.5),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.step,
                    style: sans(14,
                        height: 19 / 14,
                        color: s.done
                            ? AppColors.fg4
                            : s.current
                                ? AppColors.fg1
                                : AppColors.fg2)),
              ),
            ]),
          ),
      ],
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.markdown});

  final String markdown;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  static const _foldHeight = 260.0;
  bool _expanded = false;

  bool get _long =>
      widget.markdown.length > 700 ||
      '\n'.allMatches(widget.markdown).length > 14;

  @override
  Widget build(BuildContext context) {
    final body = MarkdownBody(
      data: widget.markdown,
      selectable: true,
      styleSheet: markdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context),
    );
    if (!_long) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _expanded
              ? body
              : SizedBox(
                  height: _foldHeight,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.7, 1],
                      colors: [Colors.white, Colors.transparent],
                    ).createShader(r),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: body,
                      ),
                    ),
                  ),
                ),
        ),
        TextAction(_expanded ? 'Show less' : 'Show more',
            icon: _expanded ? 'chevron-up' : 'chevron-down',
            onTap: () => setState(() => _expanded = !_expanded)),
      ],
    );
  }
}
