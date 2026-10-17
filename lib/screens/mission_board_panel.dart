import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

import 'shell_models.dart' show RightTab;

class MissionBoardPanel extends StatefulWidget {
  const MissionBoardPanel({
    super.key,
    required this.client,
    required this.onOpenSession,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
    this.onExpandReadout,
  });

  final DaemonClient client;
  final void Function(String sessionId, String title) onOpenSession;
  final List<RightTab> readouts;
  final String? activeReadout;
  final Widget Function(RightTab readout)? readoutBody;
  final ValueChanged<RightTab>? onSelectReadout;
  final ValueChanged<RightTab>? onCloseReadout;
  final VoidCallback? onClearReadout;
  final ValueChanged<RightTab>? onExpandReadout;

  @override
  State<MissionBoardPanel> createState() => _MissionBoardPanelState();
}

class _MissionBoardPanelState extends State<MissionBoardPanel> {
  List<MissionControlTask> _tasks = const [];
  List<RecurringJob> _jobs = const [];
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(MissionBoardPanel old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await widget.client.mcOverview();
      List<RecurringJob> jobs = const [];
      try {
        jobs = await widget.client.recurringJobs();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tasks = o.recentTasks.where((t) => !t.archived).toList();
        _jobs = jobs.where((j) => j.enabled && j.nextRunAt > 0).toList()
          ..sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt));
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _at(int secs) {
    final t = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final now = DateTime.now();
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return hm;
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return t.difference(now).inDays < 6
        ? days[t.weekday - 1]
        : '${t.day}/${t.month}';
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Text(text.toUpperCase(),
            style: sans(11, spacing: 0.9, color: AppColors.fg4)),
      );

  Widget _taskRow(MissionControlTask t, {required bool done}) {
    final sid = t.sessionId;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: sid == null ? null : () => widget.onOpenSession(sid, t.title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.ok : AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t.title.isEmpty ? '(untitled)' : t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: done ? AppColors.fg3 : AppColors.fg1)),
            ),
            const SizedBox(width: 8),
            Text(relativeTime(t.updatedAt),
                style: sans(11.5, color: AppColors.fg4, tabular: true)),
          ]),
        ),
      ),
    );
  }

  RightTab? get _readout => widget.readouts
      .where((r) => r.key == widget.activeReadout)
      .firstOrNull;

  Widget _seg(String text, bool on, VoidCallback onTap,
      {VoidCallback? onClose}) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: on ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 6, onClose != null ? 6 : 10, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(text,
                  style: sans(12.5,
                      color: on ? AppColors.fg1 : AppColors.fg3)),
              if (onClose != null) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: AppIcon('x', size: 11, color: AppColors.fg3),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _headerBar() {
    if (widget.readouts.isEmpty) {
      return Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerLeft,
        child: Text('Board', style: sans(12.5, color: AppColors.fg3)),
      );
    }
    final reading = _readout;
    return Container(
      height: 46,
      padding: const EdgeInsets.fromLTRB(10, 2, 8, 2),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _seg('Board', reading == null,
                  () => widget.onClearReadout?.call()),
              for (final r in widget.readouts)
                _seg(r.label, r.key == widget.activeReadout,
                    () => widget.onSelectReadout?.call(r),
                    onClose: () => widget.onCloseReadout?.call(r)),
            ]),
          ),
        ),
        if (reading != null && widget.onExpandReadout != null)
          IconBtn('maximize-2',
              size: 28,
              iconSize: 13,
              tooltip: 'Open in main view',
              onTap: () => widget.onExpandReadout!(reading)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _readout;
    if (reading != null && widget.readoutBody != null) {
      return Container(
        color: AppColors.windowBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerBar(),
            Expanded(
              child: ColoredBox(
                color: AppColors.bg,
                child: widget.readoutBody!(reading),
              ),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    bool today(int s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s * 1000);
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }

    final doing = _tasks
        .where((t) => t.status == 'in_progress' || t.status == 'blocked')
        .toList();
    final done =
        _tasks.where((t) => t.status == 'done' && today(t.updatedAt)).toList();
    return Container(
      color: AppColors.windowBg,
      child: !_loaded
          ? Center(child: DelayedSpinner(size: 16))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _headerBar(),
                if (doing.isEmpty && _jobs.isEmpty && done.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 120, 24, 0),
                    child: Column(children: [
                      const DottedMochi(width: 120),
                      const SizedBox(height: 18),
                      Text('All quiet',
                          style: sans(15, color: AppColors.fg1)),
                      const SizedBox(height: 6),
                      Text(
                          'Work your agents pick up, scheduled runs and '
                          'what finished today land here.',
                          textAlign: TextAlign.center,
                          style: sans(12.5,
                              height: 1.5, color: AppColors.fg4)),
                    ]),
                  ),
                if (doing.isNotEmpty) ...[
                  _label('Working now'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(children: [
                      for (final t in doing) _taskRow(t, done: false),
                    ]),
                  ),
                ],
                if (_jobs.isNotEmpty) ...[
                  _label('Up next'),
                  for (final j in _jobs.take(6))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                      child: Row(children: [
                        SizedBox(
                          width: 48,
                          child: Text(_at(j.nextRunAt),
                              style: mono(11.5, color: AppColors.fg3)),
                        ),
                        Expanded(
                          child: Text(j.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13, color: AppColors.fg2)),
                        ),
                      ]),
                    ),
                ],
                if (done.isNotEmpty) ...[
                  _label('Done today'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(children: [
                      for (final t in done.take(8)) _taskRow(t, done: true),
                    ]),
                  ),
                ],
              ],
            ),
    );
  }
}
