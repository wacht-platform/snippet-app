import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
    final finished = lanes.where((lane) => !lane.running).toList();
    final failed = lanes.where((lane) => lane.status == 'failed').length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Delegated lanes',
            subtitle: _subtitle(lanes, running.length, failed),
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
                    children: [
                      if (running.isNotEmpty) ...[
                        const SectionLabel('In progress'),
                        const SizedBox(height: 8),
                        for (final lane in running) ...[
                          LaneDetailCard(lane: lane),
                          const SizedBox(height: 8),
                        ],
                      ],
                      if (finished.isNotEmpty) ...[
                        if (running.isNotEmpty) const SizedBox(height: 12),
                        const SectionLabel('Completed'),
                        const SizedBox(height: 8),
                        for (final lane in finished) ...[
                          LaneDetailCard(lane: lane),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
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
                ? AppColors.fg4
                : AppColors.ok;
    final status = lane.running
        ? 'running · ${_elapsed(lane.startedAt)}'
        : failed
            ? 'failed'
            : cancelled
                ? 'cancelled'
                : 'completed';
    final activity = lane.activity?.trim();
    final summary = lane.summary?.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(
            color: lane.running ? AppColors.accentLine : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lane.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(14, weight: FontWeight.w600, color: AppColors.fg1),
                ),
              ),
              const SizedBox(width: 10),
              Text(status, style: mono(10.5, color: color)),
            ]),
            if (activity != null && activity.isNotEmpty && lane.running) ...[
              const SizedBox(height: 10),
              _ActivityLine(text: activity, color: color),
            ],
            if (summary != null && summary.isNotEmpty && !_expanded) ...[
              const SizedBox(height: 9),
              MarkdownPreview(data: summary, maxLines: 2),
            ],
            if (hasDetails) ...[
              const SizedBox(height: 10),
              Row(children: [
                Text(_expanded ? 'Hide details' : 'View details',
                    style: mono(10.5, color: AppColors.accent)),
                const SizedBox(width: 5),
                AppIcon(_expanded ? 'chevron-up' : 'chevron-down',
                    size: 13, color: AppColors.accent),
              ]),
            ],
            if (_expanded) ...[
              const SizedBox(height: 14),
              _details(context),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final sections = <Widget>[];
    void add(String label, String? value, {bool danger = false}) {
      if (value == null || value.trim().isEmpty) return;
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: mono(10,
                  weight: FontWeight.w600,
                  color: danger ? AppColors.danger : AppColors.fg4)),
          const SizedBox(height: 6),
          MarkdownBody(
            data: value,
            selectable: true,
            styleSheet: markdownStyle(context),
            builders: {'pre': PreBlockBuilder()},
          ),
        ]),
      ));
    }

    add('HANDOFF', lane.handoff);
    add('RESULT', lane.report);
    add('ERROR', lane.error, danger: true);
    if (lane.activityLog.isNotEmpty) {
      sections.add(_ActivityHistory(entries: lane.activityLog));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: sections);
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
  Widget build(BuildContext context) => Row(children: [
        AppIcon('terminal', size: 14, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono(11, color: AppColors.fg3)),
        ),
      ]);
}

class _ActivityHistory extends StatelessWidget {
  final List<LaneActivity> entries;
  const _ActivityHistory({required this.entries});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ACTIVITY HISTORY',
              style: mono(10, weight: FontWeight.w600, color: AppColors.fg4)),
          const SizedBox(height: 7),
          for (final entry in entries.reversed.take(24))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: AppColors.fg4, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.text,
                      style: mono(10.5, height: 1.35, color: AppColors.fg3)),
                ),
              ]),
            ),
        ],
      );
}
