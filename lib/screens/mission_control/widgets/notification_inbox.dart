/// Notification inbox — bell popover listing unresolved `NotificationMarker`s
/// across all MC tasks. Tap a row to jump to the underlying task.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';

class NotificationInbox extends StatelessWidget {
  const NotificationInbox({super.key, required this.state});
  final MissionControlState state;

  @override
  Widget build(BuildContext context) {
    final entries = <_InboxEntry>[];
    for (final task in state.tasks) {
      for (final n in task.notifications) {
        if (n.delivered == false) {
          entries.add(_InboxEntry(task: task, notification: n));
        }
      }
    }
    entries.sort((a, b) => b.task.updatedAt.compareTo(a.task.updatedAt));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Inbox'),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No notifications — agent is on it.',
                    style: sans(13, color: AppColors.fg3)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return _InboxRow(entry: e);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _InboxEntry {
  _InboxEntry({required this.task, required this.notification});
  final dynamic task;
  final dynamic notification;
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.entry});
  final _InboxEntry entry;
  @override
  Widget build(BuildContext context) {
    final color = switch (entry.notification.kind as String) {
      'blocked' => AppColors.danger,
      'failed' => AppColors.danger,
      _ => AppColors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AppIcon('alert-circle', size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.task.title as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                const SizedBox(height: 2),
                Text(entry.notification.message as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
