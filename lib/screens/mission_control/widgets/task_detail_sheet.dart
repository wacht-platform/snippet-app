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
    final title = (t.title as String).trim().isEmpty ? 'Untitled task' : t.title as String;
    final description = (t.description as String).trim();
    final sessionId = (t.sessionId as String?)?.trim() ?? '';
    final status = t.status as String;

    Future<void> archive() async {
      final confirm = await confirmAction(
        context,
        title: 'Archive task?',
        body: '“$title” will be cancelled and removed from the active board.',
        confirmLabel: 'Archive task',
      );
      if (!confirm || !context.mounted) return;
      try {
        await state.client.mcArchiveTask(t.id as String);
        if (!context.mounted) return;
        Navigator.of(context).pop();
        await state.refresh(silent: true);
      } catch (e) {
        if (context.mounted) toast(context, 'Archive failed: $e', danger: true);
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.46,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: const [0.72, 0.94],
      expand: false,
      builder: (context, controller) => Material(
        color: AppColors.bg,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: AppIcon('layers', size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(18, weight: W.label, color: AppColors.fg1)),
              ),
              IconBtn('x',
                  size: 36,
                  iconSize: 16,
                  tooltip: 'Close task',
                  onTap: () => Navigator.of(context).pop()),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _StatusPill(status: status),
                    if (sessionId.isNotEmpty) _MetaPill(text: 'Session linked'),
                    _MetaPill(text: 'Updated ${_ago((t.updatedAt as num).toInt())}'),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionLabel('Description'),
                  const SizedBox(height: 7),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Text(description,
                        style: sans(13, color: AppColors.fg2, height: 1.45)),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionLabel('Actions'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Btn('Ask agent',
                        small: true,
                        icon: 'message',
                        onTap: () async {
                          Navigator.of(context).pop();
                          await state.sendMessage(
                              'Tell me about task "$title" — what\'s the current status?');
                        }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Btn('Archive',
                        small: true,
                        icon: 'archive',
                        variant: BtnVariant.secondary,
                        onTap: archive),
                  ),
                ]),
                const SizedBox(height: 18),
                const SectionLabel('Task context'),
                const SizedBox(height: 7),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(children: [
                    _contextRow('Status', statusLabel(status), _statusColor(status)),
                    if (sessionId.isNotEmpty) ...[
                      const Divider(height: 16),
                      _contextRow('Session', sessionId, AppColors.fg2),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _contextRow(String label, String value, Color color) => Row(children: [
        SizedBox(width: 68, child: Text(label, style: sans(11, color: AppColors.fg3))),
        Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: sans(12, weight: W.label, color: color))),
      ]);

  String statusLabel(String status) => status.replaceAll('_', ' ');

  Color _statusColor(String status) => switch (status) {
        'in_progress' => AppColors.run,
        'done' || 'completed' => AppColors.ok,
        'blocked' || 'failed' || 'cancelled' => AppColors.danger,
        _ => AppColors.fg3,
      };
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
