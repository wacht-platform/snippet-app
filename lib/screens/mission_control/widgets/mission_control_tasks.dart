/// Task board for the Mission Control chat. Opened as a panel from the session
/// header — MC stays a conversation, this is just the list of dispatched work.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../widgets.dart';

class MissionControlTasksScreen extends StatefulWidget {
  const MissionControlTasksScreen({
    super.key,
    required this.client,
    this.onClose,
    this.onAskTask,
  });
  final DaemonClient client;
  final VoidCallback? onClose;
  final void Function(MissionControlTask task)? onAskTask;

  @override
  State<MissionControlTasksScreen> createState() =>
      _MissionControlTasksScreenState();
}

class _MissionControlTasksScreenState extends State<MissionControlTasksScreen> {
  List<MissionControlTask>? _tasks;
  bool _loading = true;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = _tasks == null;
        _error = null;
      });
    }
    try {
      final tasks = await widget.client.mcTasks(archived: false);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<MissionControlTask> _of(String status) =>
      (_tasks ?? const []).where((t) => t.status == status).toList();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final tasks = _tasks ?? const <MissionControlTask>[];
    final active = tasks.where((t) => t.isActive).length;
    final blocked = _of('blocked').length;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Tasks',
            subtitle: tasks.isEmpty
                ? null
                : '$active active${blocked > 0 ? ' · $blocked blocked' : ''}',
            onBack: widget.onClose ?? () => Navigator.pop(context),
            actions: [IconBtn('refresh', onTap: () => _load())],
          ),
          if (_loading)
            Expanded(
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fg3))))
          else if (_error != null)
            Expanded(
                child: EmptyState(
                    icon: 'layers', title: "Couldn't load tasks", body: _error!))
          else if (tasks.isEmpty)
            const Expanded(
                child: EmptyState(
                    icon: 'layers',
                    title: 'No tasks yet',
                    body:
                        'Work Mission Control dispatches will show up here.'))
          else
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface2,
                onRefresh: () => _load(silent: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    for (final (label, status) in const [
                      ('In progress', 'in_progress'),
                      ('Pending', 'pending'),
                      ('Blocked', 'blocked'),
                      ('Failed', 'failed'),
                      ('Done', 'done'),
                      ('Cancelled', 'cancelled'),
                    ])
                      if (_of(status).isNotEmpty) ...[
                        SectionLabel(label),
                        const SizedBox(height: 8),
                        for (final t in _of(status)) ...[
                          _TaskTile(
                            task: t,
                            onTap: () => _openDetail(t),
                          ),
                          const SizedBox(height: 6),
                        ],
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _openDetail(MissionControlTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      ),
      builder: (sheetCtx) => _TaskDetail(
        task: task,
        onAsk: widget.onAskTask == null
            ? null
            : () {
                Navigator.pop(sheetCtx);
                Navigator.pop(context);
                widget.onAskTask!(task);
              },
        onArchive: () async {
          final confirm = await confirmAction(
            sheetCtx,
            title: 'Archive task?',
            body:
                '“${task.title}” will be cancelled and removed from the active board.',
            confirmLabel: 'Archive task',
          );
          if (!confirm) return;
          try {
            await widget.client.mcArchiveTask(task.id);
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
            await _load(silent: true);
          } catch (e) {
            if (sheetCtx.mounted) {
              toast(sheetCtx, 'Archive failed: $e', danger: true);
            }
          }
        },
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onTap});
  final MissionControlTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.status);
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.isEmpty ? '(untitled)' : task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: AppColors.fg1),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      task.status.replaceAll('_', ' '),
                      if (relativeTime(task.updatedAt).isNotEmpty)
                        relativeTime(task.updatedAt),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg4),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TaskDetail extends StatelessWidget {
  const _TaskDetail({
    required this.task,
    this.onAsk,
    this.onArchive,
  });
  final MissionControlTask task;
  final VoidCallback? onAsk;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.status);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            task.title.isEmpty ? '(untitled)' : task.title,
            style: sans(17, weight: FontWeight.w600, color: AppColors.fg1),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(R.xs),
              ),
              child: Text(task.status.replaceAll('_', ' '),
                  style: mono(10, color: color)),
            ),
            if ((task.sessionId ?? '').isNotEmpty)
              Text('session ${task.sessionId}',
                  style: mono(10, color: AppColors.fg4)),
          ]),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(task.description, style: sans(14, color: AppColors.fg2)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            if (onAsk != null)
              FilledButton(
                onPressed: onAsk,
                child: const Text('Ask in chat'),
              ),
            const Spacer(),
            if (onArchive != null)
              TextButton(
                onPressed: onArchive,
                child: Text('Archive', style: sans(13, color: AppColors.fg3)),
              ),
          ]),
        ],
      ),
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'in_progress' => AppColors.run,
      'done' || 'completed' => AppColors.ok,
      'blocked' || 'failed' || 'cancelled' => AppColors.danger,
      _ => AppColors.fg4,
    };
