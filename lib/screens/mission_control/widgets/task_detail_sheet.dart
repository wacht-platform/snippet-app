/// Task detail — used by the mobile bottom sheet.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';

class TaskDetailSheet extends StatelessWidget {
  const TaskDetailSheet({super.key, required this.task, required this.state});
  final dynamic task;
  final MissionControlState state;

  @override
  Widget build(BuildContext context) {
    final t = task;
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
            Text(t.title as String,
                style: sans(18, weight: FontWeight.w600, color: AppColors.fg1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatusPill(status: t.status as String),
                if ((t.sessionId as String?) != null &&
                    (t.sessionId as String).isNotEmpty)
                  _MetaPill(text: 'Session: ${t.sessionId}'),
                _MetaPill(
                  text: 'Updated ${_ago((t.updatedAt as num).toInt())}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            if ((t.description as String).isNotEmpty) ...[
              const SectionLabel('Description'),
              const SizedBox(height: 6),
              Text(t.description as String,
                  style: sans(14, color: AppColors.fg2)),
              const SizedBox(height: 20),
            ],
            const SectionLabel('Actions'),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await state.sendMessage(
                        'Tell me about task "${t.title}" — what\'s the current status?');
                  },
                  icon: AppIcon('message', size: 16, color: AppColors.accentFg),
                  label: const Text('Ask agent'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    if (!context.mounted) return;
                    final confirm = await confirmAction(
                      context,
                      title: 'Archive task?',
                      body:
                          '“${t.title}” will be cancelled and removed from the active board.',
                      confirmLabel: 'Archive task',
                    );
                    if (!confirm) return;
                    try {
                      await state.client.mcArchiveTask(t.id as String);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      await state.refresh(silent: true);
                    } catch (e) {
                      if (context.mounted) {
                        toast(context, 'Archive failed: $e', danger: true);
                      }
                    }
                  },
                  icon: AppIcon('archive', size: 16, color: AppColors.fg2),
                  label: const Text('Archive'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'in_progress' => AppColors.run,
      'done' || 'completed' => AppColors.ok,
      'blocked' || 'failed' || 'cancelled' => AppColors.danger,
      _ => AppColors.fg3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status, style: mono(10, color: color)),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: mono(10, color: AppColors.fg3)),
    );
  }
}

String _ago(int epoch) {
  if (epoch <= 0) return '—';
  final d = DateTime.now().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true));
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
