import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../platform.dart';
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


    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Delegated lanes',
            titleSize: 14,
            compact: true,
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
                    children: laneSections(lanes, liveLanes: widget.liveLanes),
                  ),
          ),
        ]),
      ),
    );
  }

}

List<Widget> laneSections(List<LaneInfo> lanes,
    {List<LaneInfo> Function()? liveLanes}) {
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
    out.add(PaneLabel(label));
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(height: S.s8));
      out.add(LaneDetailCard(
          key: ValueKey(items[i].id), lane: items[i], liveLanes: liveLanes));
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
  final List<LaneInfo> Function()? liveLanes;
  final bool detail;
  const LaneDetailCard({super.key, required this.lane, this.liveLanes,
    this.detail = false});

  @override
  State<LaneDetailCard> createState() => _LaneDetailCardState();
}

class _LaneDetailCardState extends State<LaneDetailCard> {
  bool get _expanded => widget.detail;

  LaneInfo get lane => widget.lane;

  @override
  Widget build(BuildContext context) {

    final failed = lane.status == 'failed';
    final cancelled = lane.status == 'cancelled';
    final tone = lane.running
        ? Tone.accent
        : failed
            ? Tone.danger
            : cancelled
                ? Tone.neutral
                : Tone.ok;
    final (toneFg, _) = toneColors(tone);
    final status = lane.running
        ? 'running · ${_elapsed(lane.startedAt)}'
        : failed
            ? 'failed'
            : cancelled
                ? 'cancelled'
                : 'done';
    final activity = lane.activity?.trim();
    final summary = lane.summary?.trim();
    final error = lane.error?.trim();
    final dense = !kMobile;
    final meta = mono(10, color: AppColors.fg3);
    final body = sans(dense ? 12 : 14, height: 1.45, color: AppColors.fg2);
    // Everything under the header lines up with the title, past the dot.
    Widget indented(Widget child, {double top = 6}) =>
        Padding(padding: EdgeInsets.only(left: 16, top: top), child: child);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.detail ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => LaneDetailScreen(
              laneId: lane.id,
              liveLanes: widget.liveLanes ?? () => [widget.lane],
            )),
          ),
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(12, dense ? 9 : 12, 12, dense ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: EdgeInsets.only(top: dense ? 6 : 8),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: toneFg, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(lane.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: dense
                            ? sans(13, weight: W.label, color: AppColors.fg1)
                            : TS.rowTitle()),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: EdgeInsets.only(top: dense ? 3 : 4),
                    child: Text(status, style: mono(10, color: toneFg)),
                  ),
                ]),
                if (activity != null && activity.isNotEmpty && lane.running)
                  indented(Row(children: [
                    AppIcon('terminal', size: 11, color: AppColors.fg3),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(activity,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mono(11, color: AppColors.fg3)),
                    ),
                  ])),
                if (summary != null && summary.isNotEmpty && !_expanded)
                  indented(
                      MarkdownPreview(data: summary, maxLines: 2, style: body)),
                if (failed && error != null && error.isNotEmpty && !_expanded)
                  indented(Text(error,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: body.copyWith(color: AppColors.danger))),
                if (!_expanded)
                  indented(Text('View details', style: meta), top: 8),
                if (_expanded) indented(_details(context), top: 12),
              ],
            ),
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
      final text = sans(kMobile ? 14 : 12, height: 1.45, color: AppColors.fg2);
      sections.add(Padding(
        padding: const EdgeInsets.only(bottom: S.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label,
                  style: mono(10,
                      color: tone == Tone.danger
                          ? AppColors.danger
                          : AppColors.fg3)),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(R.xs),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  toast(context, 'Copied');
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Copy', style: mono(10, color: AppColors.fg3)),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            MarkdownBody(
              data: value,
              selectable: true,
              styleSheet: markdownStyle(context).copyWith(
                p: tone == Tone.danger
                    ? text.copyWith(color: AppColors.danger)
                    : text,
                listBullet: text,
                strong:
                    text.copyWith(color: AppColors.fg1, fontWeight: W.strong),
              ),
              builders: {'pre': PreBlockBuilder()},
            ),
          ],
        ),
      ));
    }

    addSection('Activity', lane.activity, icon: 'terminal');
    addSection('Summary', lane.summary, icon: 'file-text');
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

  String _elapsed(String startedAt) {
    final time = DateTime.tryParse(startedAt);
    if (time == null) return '';
    final delta = DateTime.now().toUtc().difference(time.toUtc());
    if (delta.inSeconds < 60) return '${delta.inSeconds}s';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    return '${delta.inHours}h ${delta.inMinutes % 60}m';
  }
}

class LaneDetailScreen extends StatefulWidget {
  final String laneId;
  final List<LaneInfo> Function() liveLanes;
  const LaneDetailScreen({super.key, required this.laneId,
    required this.liveLanes});

  @override
  State<LaneDetailScreen> createState() => _LaneDetailScreenState();
}

class _LaneDetailScreenState extends State<LaneDetailScreen> {
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
    final lane = widget.liveLanes()
        .where((lane) => lane.id == widget.laneId).firstOrNull;
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        SnAppBar(title: lane?.title ?? 'Lane details', titleSize: 14,
          compact: true, onBack: () => Navigator.of(context).pop()),
        Expanded(child: lane == null
          ? const EmptyState(icon: 'layers', title: 'Lane unavailable',
              body: 'This delegated lane is no longer available.')
          : ListView(padding: const EdgeInsets.all(S.s16), children: [
              LaneDetailCard(lane: lane, detail: true),
            ])),
      ])),
    );
  }
}

class _ActivityHistory extends StatelessWidget {
  final List<LaneActivity> entries;
  const _ActivityHistory({required this.entries});

  @override
  Widget build(BuildContext context) {
    final items = entries.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity · ${entries.length}',
            style: mono(10, color: AppColors.fg3)),
        const SizedBox(height: S.s8),
        Column(children: [
          for (var i = 0; i < items.length; i++)
            _TimelineEntryRow(
              entry: items[i],
              first: i == 0,
              last: i == items.length - 1,
            ),
        ]),
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
                      style:
                          kMobile ? TS.meta() : mono(10, color: AppColors.fg3),
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
