import 'package:flutter/material.dart';

import 'dart:async';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lanes.dart' show laneSections, LaneDetailCard;

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
    this.client,
    this.sessionId,
  });

  final DaemonClient? client;
  final String? sessionId;

  final List<Checkpoint> checkpoints;
  final void Function(Checkpoint) onRewind;
  final void Function(Checkpoint) onFork;

  @override
  Widget build(BuildContext context) {
    if (checkpoints.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('No checkpoints yet.', style: TS.meta()),
      );
    }
    if (!kMobile) {
      return _CheckpointTimeline(
          checkpoints: checkpoints,
          onRewind: onRewind,
          onFork: onFork,
          client: client,
          sessionId: sessionId);
    }
    final dense = !kMobile;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          dense ? S.s12 : M.gutter, S.s12, dense ? S.s12 : M.gutter, S.s24),
      children: [
        PaneLabel('Checkpoints · ${checkpoints.length}'),
        ListGroup(children: [
          for (final c in checkpoints)
            InkWell(
              onTap: () => onRewind(c),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    12, dense ? 8 : 10, dense ? 4 : 6, dense ? 8 : 10),
                child: Row(children: [
                  AppIcon('history',
                      size: dense ? 13 : 16, color: AppColors.fg3),
                  SizedBox(width: dense ? 10 : 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label.isEmpty ? 'Checkpoint' : c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: dense
                                  ? sans(13, color: AppColors.fg1)
                                  : TS.rowTitle()),
                          const SizedBox(height: 2),
                          Text(formatCheckpointDate(c.createdAt),
                              style: dense
                                  ? mono(10, color: AppColors.fg3)
                                  : TS.meta()),
                        ]),
                  ),
                  IconBtn('git-branch',
                      size: dense ? 26 : M.minTarget,
                      iconSize: dense ? 13 : 17,
                      tooltip: 'Fork from here',
                      onTap: () => onFork(c)),
                ]),
              ),
            ),
        ]),
      ],
    );
  }
}

/// Delegated lanes, reusing the public `LaneDetailCard` so the pane and the
/// full Lanes screen cannot diverge.
class SessionLanesPanel extends StatelessWidget {
  const SessionLanesPanel(
      {super.key, required this.lanes, this.client, this.sessionId});
  final List<LaneInfo> lanes;
  final DaemonClient? client;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return _DeskLanes(lanes: lanes, client: client, sessionId: sessionId);
    }
    if (lanes.isEmpty) {
      return const EmptyState(
          icon: 'layers',
          title: 'No delegated lanes',
          body: 'Parallel agent work will appear here when started.');
    }
    final side = kMobile ? M.gutter : S.s12;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, S.s12, side, S.s24),
      children: laneSections(lanes),
    );
  }
}

Widget _paneLabel(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: sans(11, spacing: 0.9, color: AppColors.fg4)),
        ),
        if (trailing != null) trailing,
      ]),
    );

class _CheckpointTimeline extends StatefulWidget {
  const _CheckpointTimeline(
      {required this.checkpoints,
      required this.onRewind,
      required this.onFork,
      this.client,
      this.sessionId});
  final DaemonClient? client;
  final String? sessionId;
  final List<Checkpoint> checkpoints;
  final void Function(Checkpoint) onRewind;
  final void Function(Checkpoint) onFork;

  @override
  State<_CheckpointTimeline> createState() => _CheckpointTimelineState();
}

class _CheckpointTimelineState extends State<_CheckpointTimeline> {
  String? _hover;
  String? _picked;
  Map<String, ({int files, int add, int del})> _stats = const {};
  String _statsFor = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(_CheckpointTimeline old) {
    super.didUpdateWidget(old);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final c = widget.client;
    final sid = widget.sessionId;
    if (c == null || sid == null) return;
    final ids = [for (final cp in widget.checkpoints.reversed) cp.id];
    final sig = ids.join(',');
    if (sig == _statsFor || ids.isEmpty) return;
    _statsFor = sig;
    try {
      final s = await c.checkpointStats(sid, ids);
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  String _stat(String id) {
    final s = _stats[id];
    if (s == null) return '';
    if (s.files == 0) return 'no changes';
    final parts = [
      if (s.add > 0) '+${s.add}',
      if (s.del > 0) '−${s.del}',
    ];
    return '${parts.join(' ')}${parts.isEmpty ? '' : ' · '}${s.files} file${s.files == 1 ? '' : 's'}';
  }

  Widget _pill(String label, VoidCallback onTap, {bool filled = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: filled ? AppColors.surface2 : Colors.transparent,
          shape: StadiumBorder(
              side: BorderSide(
                  color: filled ? Colors.transparent : AppColors.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(label,
                  style: sans(11.5,
                      color: filled ? AppColors.fg2 : AppColors.fg3)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cps = widget.checkpoints;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        _paneLabel('Checkpoints · ${cps.length}',
            trailing: Text('Files roll back too',
                style: sans(11.5, color: AppColors.fg4))),
        Stack(children: [
          Positioned(
            left: 13,
            top: 14,
            bottom: 14,
            child: CustomPaint(
                size: const Size(2, double.infinity),
                painter: _Dots(AppColors.fg1.withValues(alpha: 0.14))),
          ),
          Column(children: [
            for (var i = 0; i < cps.length; i++) _row(cps[i], i == 0),
          ]),
        ]),
      ],
    );
  }

  Widget _row(Checkpoint c, bool latest) {
    final open = _hover == c.id || _picked == c.id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = c.id),
      onExit: (_) => setState(() => _hover = null),
      child: GestureDetector(
        onTap: () => setState(() => _picked = _picked == c.id ? null : c.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.fromLTRB(30, 9, 10, 10),
          decoration: BoxDecoration(
            color: open ? AppColors.surface1 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: -21,
              top: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: latest ? AppColors.accent : AppColors.fg4,
                  border: Border.all(color: AppColors.windowBg, width: 0),
                ),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  c.label.trim().isEmpty
                      ? 'Checkpoint'
                      : c.label.trim().replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: open ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5,
                      height: 1.45,
                      color: open || latest ? AppColors.fg1 : AppColors.fg2)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(formatCheckpointDate(c.createdAt),
                      style: sans(11, color: AppColors.fg4)),
                ),
                Text(_stat(c.id), style: mono(10.5, color: AppColors.fg3)),
              ]),
              if (open) ...[
                const SizedBox(height: 8),
                Row(children: [
                  _pill('Restore', () => widget.onRewind(c), filled: true),
                  _pill('Fork', () => widget.onFork(c)),
                ]),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Dots extends CustomPainter {
  _Dots(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += 5) {
      canvas.drawCircle(Offset(1, y), 1, p);
    }
  }

  @override
  bool shouldRepaint(_Dots old) => old.color != color;
}

String _elapsed(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

class _DeskLanes extends StatefulWidget {
  const _DeskLanes({required this.lanes, this.client, this.sessionId});
  final List<LaneInfo> lanes;
  final DaemonClient? client;
  final String? sessionId;

  @override
  State<_DeskLanes> createState() => _DeskLanesState();
}

class _DeskLanesState extends State<_DeskLanes> {
  final Set<String> _open = {};
  List<RecurringJob> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    final c = widget.client;
    if (c == null) return;
    try {
      final all = await c.recurringJobs();
      if (!mounted) return;
      setState(() => _jobs = [
            for (final j in all)
              if (j.enabled &&
                  (widget.sessionId == null || j.sessionId == widget.sessionId))
                j
          ]..sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt)));
    } catch (_) {}
  }

  String _at(int secs) {
    if (secs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[t.weekday - 1];
  }

  Widget _lane(LaneInfo l) {
    final color = switch (l.status) {
      'running' => AppColors.accent,
      'failed' => AppColors.danger,
      'cancelled' => AppColors.fg4,
      _ => AppColors.ok,
    };
    final status = switch (l.status) {
      'running' => 'working',
      'failed' => 'failed',
      'cancelled' => 'cancelled',
      _ => 'done',
    };
    final task = (l.activity ?? '').trim().isNotEmpty
        ? l.activity!.trim()
        : (l.summary ?? l.handoff ?? '').trim();
    final steps = l.activityLog.length.clamp(0, 14);
    if (_open.contains(l.id)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _open.remove(l.id)),
              child: Text('Less', style: sans(12, color: AppColors.fg3)),
            ),
          ),
          LaneDetailCard(lane: l, client: widget.client),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open.add(l.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AgentMochi(l.agent ?? l.id, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(l.title.isEmpty ? 'Lane' : l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                ),
                Text(status, style: sans(11.5, color: color)),
              ]),
              if (task.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(task,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, height: 1.45, color: AppColors.fg3)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 0; i < 14; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < steps
                          ? color
                          : AppColors.fg1.withValues(alpha: 0.10),
                    ),
                  ),
                const Spacer(),
                Text(
                    [
                      if ((l.profile ?? '').isNotEmpty) l.profile!,
                      _elapsed(l.startedAt),
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: mono(10.5, color: AppColors.fg4)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lanes = widget.lanes;
    final running = lanes.where((l) => l.running).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        _paneLabel(running > 0
            ? 'Lanes · $running running'
            : 'Lanes${lanes.isEmpty ? '' : ' · ${lanes.length}'}'),
        if (lanes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: Text(
                'Parallel work this session hands off shows up here.',
                style: sans(12.5, height: 1.5, color: AppColors.fg4)),
          )
        else
          for (final l in lanes) _lane(l),
        if (_jobs.isNotEmpty) ...[
          _paneLabel('Scheduled'),
          for (final j in _jobs.take(8))
            SizedBox(
              height: 32,
              child: Row(children: [
                SizedBox(
                  width: 46,
                  child: Text(_at(j.nextRunAt),
                      style: mono(11.5, color: AppColors.accent)),
                ),
                Expanded(
                  child: Text(j.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, color: AppColors.fg2)),
                ),
                Text(j.scheduleLabel, style: sans(11.5, color: AppColors.fg4)),
              ]),
            ),
        ],
      ],
    );
  }
}
