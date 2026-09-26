import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lanes.dart' show LaneDetailCard;

/// Human-readable checkpoint timestamp ('Today · 3:04 PM').
///
/// Lives here rather than in session.dart so this shared module has no
/// dependency back on the session screen — the direction is session -> panels.
/// session.dart imports it from here.
String formatCheckpointDate(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final daysAgo = today.difference(day).inDays;
  final hour = parsed.hour == 0
      ? 12
      : (parsed.hour > 12 ? parsed.hour - 12 : parsed.hour);
  final minute = parsed.minute.toString().padLeft(2, '0');
  final meridiem = parsed.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $meridiem';

  if (daysAgo == 0) return 'Today · $time';
  if (daysAgo == 1) return 'Yesterday · $time';
  if (daysAgo >= 0 && daysAgo < 7) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[parsed.weekday - 1]} · $time';
  }
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  return '$date · $time';
}

/// Session panels that render in a host.
///
/// Scaffold-free on purpose: the shell's right pane hosts them directly, and the
/// session's own drawer hosts the same widgets, so the two can never show a
/// different Checkpoints and Lanes view. Before this each had its own
/// copy and they were already drifting.

/// Checkpoint history. `onRewind`/`onFork` are supplied by the host so the shell
/// and the session route the action back through the same session handler.
class SessionCheckpointsPanel extends StatelessWidget {
  const SessionCheckpointsPanel({
    super.key,
    required this.checkpoints,
    required this.onRewind,
    required this.onFork,
  });

  final List<Checkpoint> checkpoints;
  final void Function(Checkpoint) onRewind;
  final void Function(Checkpoint) onFork;

  @override
  Widget build(BuildContext context) {
    if (checkpoints.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('No checkpoints yet.',
            style: sans(12, color: AppColors.fg3)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final c in checkpoints)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(13),
              onTap: () => onRewind(c),
              child: Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(R.md)),
                    child: AppIcon('history', size: 17, color: AppColors.fg3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.label.isEmpty ? c.id : c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                weight: W.label,
                                height: 1.2,
                                color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Text(formatCheckpointDate(c.createdAt),
                            style: mono(11, color: AppColors.fg3)),
                      ]),
                ),
                IconBtn('git-branch',
                    size: 32,
                    iconSize: 16,
                    tooltip: 'Fork from here',
                    onTap: () => onFork(c)),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Delegated lanes, reusing the public `LaneDetailCard` so the pane and the
/// full Lanes screen cannot diverge.
class SessionLanesPanel extends StatelessWidget {
  const SessionLanesPanel({super.key, required this.lanes});
  final List<LaneInfo> lanes;

  @override
  Widget build(BuildContext context) {
    if (lanes.isEmpty) {
      return const EmptyState(
          icon: 'layers',
          title: 'No delegated lanes',
          body: 'Parallel agent work will appear here when started.');
    }
    final running = lanes.where((l) => l.running).toList();
    final failed = lanes.where((l) => l.status == 'failed').toList();
    final cancelled = lanes.where((l) => l.status == 'cancelled').toList();
    final completed = lanes
        .where((l) =>
            !l.running && l.status != 'failed' && l.status != 'cancelled')
        .toList();

    final groups = <Widget>[];
    void section(String label, List<LaneInfo> items, {Color? badgeColor}) {
      if (items.isEmpty) return;
      if (groups.isNotEmpty) groups.add(const SizedBox(height: 14));
      groups.add(Row(
        children: [
          SectionLabel(label),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (badgeColor ?? AppColors.fg3).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (badgeColor ?? AppColors.fg3).withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Text(
              '${items.length}',
              style: mono(10,
                  weight: FontWeight.w600,
                  color: badgeColor ?? AppColors.fg3),
            ),
          ),
        ],
      ));
      groups.add(const SizedBox(height: 8));
      for (final lane in items) {
        groups.add(LaneDetailCard(lane: lane));
        groups.add(const SizedBox(height: 8));
      }
    }

    section('In progress', running, badgeColor: AppColors.accent);
    section('Failed', failed, badgeColor: AppColors.danger);
    section('Completed', completed, badgeColor: AppColors.ok);
    section('Cancelled', cancelled, badgeColor: AppColors.fg3);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: groups,
    );
  }
}
