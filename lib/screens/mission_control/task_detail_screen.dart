import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../coordination/coordination_thread_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'task_board_screen.dart' show statusColor;

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
  });

  final DaemonClient client;
  final String taskId;
  final VoidCallback? onClose;

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

  Future<void> _setStatus(TaskStatus status) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final updated = await widget.client.setTaskStatus(widget.taskId, status);
      if (mounted) setState(() => task = updated);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addAgent() async {
    final agents = await widget.client.coordinationAgents();
    if (!mounted) return;
    final onTask = roster.where((r) => r.active).map((r) => r.agentId).toSet();
    final candidates = agents.where((a) => !onTask.contains(a.id)).toList();
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
                    AppIcon('users', size: 16, color: AppColors.fg3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          a.displayName.trim().isEmpty ? a.id : a.displayName,
                          style: sans(13.5, color: AppColors.fg1)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.client.addTaskAgent(widget.taskId, picked);
      // Fetched OUTSIDE setState: its callback is not async, so awaiting in it
      // does not compile.
      final updated = await widget.client.taskAgents(widget.taskId);
      if (!mounted) return;
      setState(() => roster = updated);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _linkTask() async {
    final all = await widget.client.tasks();
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
                      style: sans(13.5, color: AppColors.fg1)),
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
      appBar: AppBar(
        title: Text(t?.title ?? 'Task'),
        leading: IconButton(
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
          icon: AppIcon('chevron-left', size: 20, color: AppColors.fg2),
        ),
      ),
      body: loading
          ? const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!,
                        textAlign: TextAlign.center,
                        style: sans(12.5, color: AppColors.danger)),
                  ),
                )
              : t == null
                  ? const EmptyState(icon: 'layers', title: 'Task not found')
                  : Column(children: [
                      _meta(t),
                      Divider(height: 1, color: AppColors.border),
                      Expanded(child: _roomView()),
                      _composerBar(),
                    ]),
    );
  }

  Widget _meta(TaskItem t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.description.trim().isNotEmpty) ...[
              Text(t.description,
                  style: sans(13, color: AppColors.fg2, height: 1.45)),
              const SizedBox(height: 14),
            ],
            // Column picker. Every state is offered, including the current one,
            // so the row reads as the task's position rather than a menu.
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in TaskStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: busy ? null : () => _setStatus(s),
                          borderRadius: BorderRadius.circular(R.chip),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: s == t.status
                                  ? AppColors.surface2
                                  : Colors.transparent,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(R.chip),
                            ),
                            child: Text(s.label,
                                style: sans(12,
                                    weight: s == t.status ? W.label : W.body,
                                    color: s == t.status
                                        ? AppColors.fg1
                                        : statusColor(s))),
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
              Text('Nobody assigned yet.',
                  style: sans(12.5, color: AppColors.fg4))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in roster)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            a.active ? AppColors.accentBg : AppColors.surface2,
                        borderRadius: BorderRadius.circular(R.chip),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(a.agentId,
                            style: sans(12,
                                color: a.active
                                    ? AppColors.accent
                                    : AppColors.fg4)),
                        if (!a.active) ...[
                          const SizedBox(width: 5),
                          Text('left', style: sans(10, color: AppColors.fg4)),
                        ],
                      ]),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            _section('Related', onAdd: _linkTask),
            if (links.links.isEmpty && links.blockedBy.isEmpty)
              Text('No linked tasks.', style: sans(12.5, color: AppColors.fg4))
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
              style: sans(11,
                  weight: W.label, color: AppColors.fg3, spacing: 0.5)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AppIcon('plus', size: 14, color: AppColors.fg3),
            ),
          ),
        ]),
      );

  Widget _linkRow(String prefix, String id, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$prefix  ', style: sans(11.5, color: color)),
          Expanded(
            child: Text(id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg3)),
          ),
        ]),
      );

  Widget _roomView() {
    final room = this.room;
    if (room == null) return const SizedBox.shrink();
    if (room.events.isEmpty) {
      return const EmptyState(
        icon: 'message-text',
        title: 'No messages yet',
        body: 'Agents on this task talk here. You can post too.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: room.events.length,
      itemBuilder: (_, i) {
        final e = room.events[i];
        final mine = e.actorKind == 'human';
        final body = e.payload['body']?.toString() ?? '';
        if (body.trim().isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: mine ? AppColors.surface2 : AppColors.surface1,
              borderRadius: BorderRadius.circular(R.card),
            ),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(e.actorId,
                        style: sans(10.5,
                            weight: W.label, color: AppColors.accent)),
                  ),
                Text(body, style: sans(13, color: AppColors.fg1, height: 1.4)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composerBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(children: [
            Expanded(
              child: AppField(
                controller: _composer,
                hint: 'Message this task…',
                maxLines: 4,
                minLines: 1,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            IconBtn('send',
                size: 40,
                iconSize: 18,
                tooltip: 'Send',
                onTap: (room?.sending ?? false) ? null : _send),
          ]),
        ),
      );
}
