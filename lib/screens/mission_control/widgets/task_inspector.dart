/// Right-rail task inspector — used by the desktop layout.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';

class TaskInspector extends StatelessWidget {
  const TaskInspector({super.key, required this.task, this.state});
  final dynamic task;
  final MissionControlState? state;

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.title as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(15, weight: FontWeight.w600, color: AppColors.fg1),
                ),
              ),
              _StatusPill(status: t.status as String),
            ],
          ),
          const SizedBox(height: 12),
          if ((t.sessionId as String?) != null &&
              (t.sessionId as String).isNotEmpty) ...[
            const SectionLabel('Target session'),
            const SizedBox(height: 4),
            Text(t.sessionId as String, style: mono(11, color: AppColors.fg3)),
            const SizedBox(height: 12),
          ],
          if ((t.description as String).isNotEmpty) ...[
            const SectionLabel('Description'),
            const SizedBox(height: 4),
            Text(t.description as String,
                style: sans(13, color: AppColors.fg2)),
            const SizedBox(height: 12),
          ],
          if (state != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => state!.sendMessage(
                      'Tell me about task "${t.title}" — what\'s the current status?'),
                  icon: AppIcon('message', size: 14, color: AppColors.accentFg),
                  label: const Text('Ask agent'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    final confirm = await confirmAction(
                      context,
                      title: 'Archive task?',
                      body:
                          '“${t.title}” will be cancelled and removed from the active board.',
                      confirmLabel: 'Archive task',
                    );
                    if (!confirm || state == null) return;
                    try {
                      await state!.client.mcArchiveTask(t.id as String);
                      await state!.refresh(silent: true);
                    } catch (e) {
                      if (context.mounted) {
                        toast(context, 'Archive failed: $e', danger: true);
                      }
                    }
                  },
                  icon: AppIcon('archive', size: 14, color: AppColors.fg2),
                  label: const Text('Archive'),
                ),
              ],
            ),
          ],
        ],
      ),
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
