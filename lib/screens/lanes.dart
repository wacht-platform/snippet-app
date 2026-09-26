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
  List<LaneInfo>? _shown;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final lanes = widget.liveLanes();
      if (identical(lanes, _shown) && !lanes.any((l) => l.running)) return;
      setState(() {});
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
    _shown = lanes;
    final running = lanes.where((lane) => lane.running).length;
    final failed = lanes.where((lane) => lane.status == 'failed').length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Delegated lanes',
            titleSize: 14,
            compact: true,
            subtitle: _subtitle(lanes, running, failed),
            onBack: widget.onClose ?? () => Navigator.pop(context),
          ),
          Expanded(
            child: lanes.isEmpty
                ? const EmptyState(
                    icon: 'layers',
                    title: 'No delegated lanes',
                    body: 'Parallel agent work will appear here when started.')
                : ListView(
                    padding:
                        const EdgeInsets.fromLTRB(S.s16, S.s16, S.s16, S.s32),
                    children: laneSections(lanes),
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

List<Widget> laneSections(List<LaneInfo> lanes) {
  final running = lanes.where((l) => l.running).toList();
  final failed = lanes.where((l) => l.status == 'failed').toList();
  final cancelled = lanes.where((l) => l.status == 'cancelled').toList();
  final completed = lanes
      .where(
          (l) => !l.running && l.status != 'failed' && l.status != 'cancelled')
      .toList();
  final out = <Widget>[];
  void section(String label, List<LaneInfo> items, Tone tone) {
    if (items.isEmpty) return;
    if (out.isNotEmpty) out.add(const SizedBox(height: S.s20));
    out.add(SectionHeader(label,
        count: items.length,
        tone: tone,
        padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8)));
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(height: S.s8));
      out.add(LaneDetailCard(key: ValueKey(items[i].id), lane: items[i]));
    }
  }

  section('In progress', running, Tone.accent);
  section('Failed', failed, Tone.danger);
  section('Completed', completed, Tone.ok);
  section('Cancelled', cancelled, Tone.neutral);
  return out;
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
    final hasDetails = _hasDetails(lane);
    final failed = lane.status == 'failed';
    final cancelled = lane.status == 'cancelled';
    final tone = lane.running
        ? Tone.accent
        : failed
            ? Tone.danger
            : cancelled
                ? Tone.neutral
                : Tone.ok;
    final icon = lane.running
        ? 'cpu'
        : failed
            ? 'alert-triangle'
            : cancelled
                ? 'x-circle'
                : 'check-circle';
    final status = lane.running
        ? 'Running · ${_elapsed(lane.startedAt)}'
        : failed
            ? 'Failed'
            : cancelled
                ? 'Cancelled'
                : 'Completed';
    final activity = lane.activity?.trim();
    final summary = lane.summary?.trim();
    final error = lane.error?.trim();

    return Material(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: const EdgeInsets.all(S.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconTile(icon, tone: tone),
                const SizedBox(width: S.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lane.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TS.rowTitle()),
                      const SizedBox(height: S.s6),
                      Tag(status, tone: tone, live: lane.running),
                    ],
                  ),
                ),
              ]),
              if (activity != null && activity.isNotEmpty && lane.running) ...[
                const SizedBox(height: S.s12),
                _ActivityLine(text: activity),
              ],
              if (summary != null && summary.isNotEmpty && !_expanded) ...[
                const SizedBox(height: S.s12),
                InsetPanel(child: MarkdownPreview(data: summary, maxLines: 2)),
              ],
              if (failed &&
                  error != null &&
                  error.isNotEmpty &&
                  !_expanded) ...[
                const SizedBox(height: S.s12),
                InsetPanel(
                  tone: Tone.danger,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: S.s2),
                        child: AppIcon('alert-triangle',
                            size: 14, color: AppColors.danger),
                      ),
                      const SizedBox(width: S.s8),
                      Expanded(
                        child: Text(error,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TS.ui(AppColors.danger)),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasDetails) ...[
                const SizedBox(height: S.s12),
                Row(children: [
                  Text(_expanded ? 'Hide details' : 'Show details',
                      style: TS.label(AppColors.accent)),
                  const SizedBox(width: S.s4),
                  AppIcon(_expanded ? 'chevron-up' : 'chevron-down',
                      size: 14, color: AppColors.accent),
                ]),
              ],
              if (_expanded) ...[
                const SizedBox(height: S.s16),
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

    void addSection(String label, String? value,
        {required String icon, Tone tone = Tone.neutral}) {
      if (value == null || value.trim().isEmpty) return;
      final (fg, _) = toneColors(tone);
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: S.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AppIcon(icon, size: 14, color: fg),
              const SizedBox(width: S.s6),
              Text(label,
                  style: TS.label(
                      tone == Tone.danger ? AppColors.danger : AppColors.fg2)),
              const Spacer(),
              TextAction('Copy', icon: 'copy', onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                toast(context, 'Copied');
              }),
            ]),
            const SizedBox(height: S.s6),
            InsetPanel(
              tone: tone == Tone.danger ? Tone.danger : null,
              child: MarkdownBody(
                data: value,
                selectable: true,
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()},
              ),
            ),
          ],
        ),
      ));
    }

    addSection('Handoff', lane.handoff,
        icon: 'corner-down-right', tone: Tone.accent);
    addSection('Report', lane.report, icon: 'file-text', tone: Tone.ok);
    addSection('Error', lane.error, icon: 'alert-triangle', tone: Tone.danger);

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
  const _ActivityLine({required this.text});

  @override
  Widget build(BuildContext context) => InsetPanel(
        padding: const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
        child: Row(children: [
          AppIcon('terminal', size: 14, color: AppColors.accent),
          const SizedBox(width: S.s8),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TS.codeSmall(AppColors.fg2)),
          ),
        ]),
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
        Row(children: [
          AppIcon('activity', size: 14, color: AppColors.fg3),
          const SizedBox(width: S.s6),
          Text('Activity', style: TS.label()),
          const SizedBox(width: S.s8),
          CountBadge(entries.length),
        ]),
        const SizedBox(height: S.s8),
        InsetPanel(
          child: Column(children: [
            for (var i = 0; i < items.length; i++)
              _TimelineEntryRow(
                entry: items[i],
                first: i == 0,
                last: i == items.length - 1,
              ),
          ]),
        ),
      ],
    );
  }
}

class _TimelineEntryRow extends StatelessWidget {
  final LaneActivity entry;
  final bool first;
  final bool last;

  const _TimelineEntryRow(
      {required this.entry, required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 12,
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: S.s6),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: first ? AppColors.accent : AppColors.fg4,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last)
                Expanded(child: Container(width: 1, color: AppColors.line)),
            ]),
          ),
          const SizedBox(width: S.s8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : S.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.kind.isNotEmpty || entry.at.isNotEmpty)
                    Text(
                      [
                        if (entry.kind.isNotEmpty) entry.kind,
                        if (entry.at.isNotEmpty) _formatTime(entry.at),
                      ].join(' · '),
                      style: TS.meta(),
                    ),
                  Text(entry.text, style: TS.codeSmall(AppColors.fg2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)}:${two(parsed.second)}';
  }
}
