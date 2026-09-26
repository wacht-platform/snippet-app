import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// A focused view of delegated work. The session owns the live state; this
/// screen polls the getter so progress continues updating while it is open.
class LanesScreen extends StatefulWidget {
  final List<LaneInfo> Function() liveLanes;
  final VoidCallback? onClose;

  const LanesScreen({
    super.key,
    required this.liveLanes,
    this.onClose,
  });

  @override
  State<LanesScreen> createState() => _LanesScreenState();
}

class _LanesScreenState extends State<LanesScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lanes = widget.liveLanes();
    final running = lanes.where((lane) => lane.running).toList();
    // Group by OUTCOME, not by "still running or not". Folding every finished
    // lane into one bucket labelled "Completed" filed failed and cancelled lanes
    // under a header that claimed they succeeded.
    final failed = lanes.where((lane) => lane.status == 'failed').toList();
    final cancelled =
        lanes.where((lane) => lane.status == 'cancelled').toList();
    final completed = lanes
        .where((lane) =>
            !lane.running &&
            lane.status != 'failed' &&
            lane.status != 'cancelled')
        .toList();

    final groups = <Widget>[];
    void section(String label, List<LaneInfo> items, {Color? badgeColor}) {
      if (items.isEmpty) return;
      if (groups.isNotEmpty) groups.add(const SizedBox(height: 16));
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
      groups.add(const SizedBox(height: 10));
      for (final lane in items) {
        groups.add(LaneDetailCard(lane: lane));
        groups.add(const SizedBox(height: 10));
      }
    }

    section('In progress', running, badgeColor: AppColors.accent);
    section('Failed', failed, badgeColor: AppColors.danger);
    section('Completed', completed, badgeColor: AppColors.ok);
    section('Cancelled', cancelled, badgeColor: AppColors.fg3);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Delegated lanes',
            titleSize: 14,
            compact: true,
            subtitle: _subtitle(lanes, running.length, failed.length),
            onBack: widget.onClose ?? () => Navigator.pop(context),
          ),
          Expanded(
            child: lanes.isEmpty
                ? const EmptyState(
                    icon: 'layers',
                    title: 'No delegated lanes',
                    body: 'Parallel agent work will appear here when started.')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    children: groups,
                  ),
          ),
        ]),
      ),
    );
  }

  String _subtitle(List<LaneInfo> lanes, int running, int failed) {
    if (lanes.isEmpty) return 'No parallel work';
    final total = '${lanes.length} ${lanes.length == 1 ? 'lane' : 'lanes'}';
    if (running > 0) return '$total · $running running';
    if (failed > 0) return '$total · $failed failed';
    return '$total · complete';
  }
}

class LaneDetailCard extends StatefulWidget {
  final LaneInfo lane;
  const LaneDetailCard({super.key, required this.lane});

  @override
  State<LaneDetailCard> createState() => _LaneDetailCardState();
}

class _LaneDetailCardState extends State<LaneDetailCard> {
  bool _expanded = false;

  LaneInfo get lane => widget.lane;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final hasDetails = _hasDetails(lane);
    final failed = lane.status == 'failed';
    final cancelled = lane.status == 'cancelled';
    final color = lane.running
        ? AppColors.accent
        : failed
            ? AppColors.danger
            : cancelled
                ? AppColors.fg3
                : AppColors.ok;

    final statusLabel = lane.running
        ? 'RUNNING · ${_elapsed(lane.startedAt)}'
        : failed
            ? 'FAILED'
            : cancelled
                ? 'CANCELLED'
                : 'COMPLETED';

    final iconName = lane.running
        ? 'cpu'
        : failed
            ? 'alert-triangle'
            : cancelled
                ? 'x-circle'
                : 'check-circle';

    final activity = lane.activity?.trim();
    final summary = lane.summary?.trim();
    final error = lane.error?.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(
          color: lane.running
              ? AppColors.accent.withValues(alpha: 0.4)
              : failed
                  ? AppColors.danger.withValues(alpha: 0.3)
                  : AppColors.border,
          width: lane.running ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(
                        color: color.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: AppIcon(iconName, size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lane.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              weight: FontWeight.w600, color: AppColors.fg1),
                        ),
                        if (lane.id.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            lane.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(10, color: AppColors.fg4),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusDot(
                          status: lane.running
                              ? 'running'
                              : (failed ? 'offline' : 'online'),
                          size: 6,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: mono(10,
                              weight: FontWeight.w600,
                              spacing: 0.4,
                              color: color),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (activity != null && activity.isNotEmpty && lane.running) ...[
                const SizedBox(height: 10),
                _ActivityLine(text: activity, color: color),
              ],
              if (summary != null && summary.isNotEmpty && !_expanded) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface2.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.6)),
                  ),
                  child: MarkdownPreview(data: summary, maxLines: 2),
                ),
              ],
              if (failed && error != null && error.isNotEmpty && !_expanded) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppIcon('alert-triangle',
                            size: 13, color: AppColors.danger),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(12, height: 1.4, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasDetails) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      _expanded
                          ? 'Hide execution details'
                          : 'View execution details',
                      style: mono(10,
                          weight: FontWeight.w500, color: AppColors.accent),
                    ),
                    const SizedBox(width: 4),
                    AppIcon(
                      _expanded ? 'chevron-up' : 'chevron-down',
                      size: 13,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 14),
                _details(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final sections = <Widget>[];

    void addSection(
      String label,
      String? value, {
      required String icon,
      bool danger = false,
      Color? iconColor,
    }) {
      if (value == null || value.trim().isEmpty) return;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    icon,
                    size: 12,
                    color: danger
                        ? AppColors.danger
                        : (iconColor ?? AppColors.fg3),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: mono(
                      10,
                      weight: FontWeight.w600,
                      spacing: 0.5,
                      color: danger ? AppColors.danger : AppColors.fg3,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      toast(context, 'Copied');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon('clipboard',
                              size: 11, color: AppColors.fg4),
                          const SizedBox(width: 4),
                          Text('Copy',
                              style: mono(9, color: AppColors.fg4)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: danger
                      ? AppColors.danger.withValues(alpha: 0.06)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(
                    color: danger
                        ? AppColors.danger.withValues(alpha: 0.2)
                        : AppColors.border.withValues(alpha: 0.6),
                  ),
                ),
                child: MarkdownBody(
                  data: value,
                  selectable: true,
                  styleSheet: markdownStyle(context),
                  builders: {'pre': PreBlockBuilder()},
                ),
              ),
            ],
          ),
        ),
      );
    }

    addSection('HANDOFF PROMPT', lane.handoff,
        icon: 'corner-down-right', iconColor: AppColors.accent);
    addSection('EXECUTION REPORT', lane.report,
        icon: 'file-text', iconColor: AppColors.ok);
    addSection('FAILURE DETAILS', lane.error,
        icon: 'alert-triangle', danger: true);

    if (lane.activityLog.isNotEmpty) {
      sections.add(_ActivityHistory(entries: lane.activityLog));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  bool _hasDetails(LaneInfo value) =>
      [value.activity, value.handoff, value.summary, value.report, value.error]
          .any((text) => text != null && text.trim().isNotEmpty) ||
      value.activityLog.isNotEmpty;

  String _elapsed(String startedAt) {
    final time = DateTime.tryParse(startedAt);
    if (time == null) return '';
    final delta = DateTime.now().toUtc().difference(time.toUtc());
    if (delta.inSeconds < 60) return '${delta.inSeconds}s';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    return '${delta.inHours}h ${delta.inMinutes % 60}m';
  }
}

class _ActivityLine extends StatelessWidget {
  final String text;
  final Color color;
  const _ActivityLine({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            AppIcon('terminal', size: 13, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg2),
              ),
            ),
          ],
        ),
      );
}

class _ActivityHistory extends StatelessWidget {
  final List<LaneActivity> entries;
  const _ActivityHistory({required this.entries});

  @override
  Widget build(BuildContext context) {
    final items = entries.reversed.take(24).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon('activity', size: 12, color: AppColors.fg3),
            const SizedBox(width: 6),
            Text(
              'ACTIVITY HISTORY (${entries.length})',
              style: mono(10,
                  weight: FontWeight.w600,
                  spacing: 0.5,
                  color: AppColors.fg3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++)
                _TimelineEntryRow(
                  entry: items[i],
                  isLast: i == items.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineEntryRow extends StatelessWidget {
  final LaneActivity entry;
  final bool isLast;

  const _TimelineEntryRow({
    required this.entry,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.kind.isNotEmpty || entry.at.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          if (entry.kind.isNotEmpty)
                            Text(
                              entry.kind.toUpperCase(),
                              style: mono(9,
                                  weight: FontWeight.w600,
                                  color: AppColors.accent),
                            ),
                          if (entry.kind.isNotEmpty && entry.at.isNotEmpty)
                            Text(' · ',
                                style: mono(9, color: AppColors.fg4)),
                          if (entry.at.isNotEmpty)
                            Text(
                              _formatTime(entry.at),
                              style: mono(9, color: AppColors.fg4),
                            ),
                        ],
                      ),
                    ),
                  Text(
                    entry.text,
                    style: mono(11, height: 1.35, color: AppColors.fg2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final h = parsed.toLocal().hour.toString().padLeft(2, '0');
    final m = parsed.toLocal().minute.toString().padLeft(2, '0');
    final s = parsed.toLocal().second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
