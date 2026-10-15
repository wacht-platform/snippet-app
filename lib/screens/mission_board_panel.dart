import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class MissionBoardPanel extends StatefulWidget {
  const MissionBoardPanel(
      {super.key, required this.client, required this.onOpenSession});

  final DaemonClient client;
  final void Function(String sessionId, String title) onOpenSession;

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
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
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

  @override
  Widget build(BuildContext context) {
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
    Widget empty(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
          child: Text(s, style: sans(12.5, color: AppColors.fg4)),
        );
    return Container(
      color: AppColors.windowBg,
      child: !_loaded
          ? Center(child: DelayedSpinner(size: 16))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.centerLeft,
                  child: Text('Board', style: sans(12.5, color: AppColors.fg3)),
                ),
                _label('Working now'),
                if (doing.isEmpty) empty('Nothing running.'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(children: [
                    for (final t in doing) _taskRow(t, done: false),
                  ]),
                ),
                _label('Up next'),
                if (_jobs.isEmpty) empty('Nothing scheduled.'),
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
                _label('Done today'),
                if (done.isEmpty) empty('Nothing finished yet today.'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(children: [
                    for (final t in done.take(8)) _taskRow(t, done: true),
                  ]),
                ),
              ],
            ),
    );
  }
}
