import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../theme.dart';
import '../widgets.dart';

/// Mission Control board — shows dashboard overview, managed tasks, and
/// managed sessions with health indicators, refresh, and archive actions.
///
/// Opened via [presentScreen] from the sidebar or the command palette.
class MissionControlScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;
  const MissionControlScreen({super.key, required this.client, this.onClose});
  @override
  State<MissionControlScreen> createState() => _MissionControlScreenState();
}

class _MissionControlScreenState extends State<MissionControlScreen> {
  MissionControlOverview? _overview;
  List<MissionControlTask> _tasks = const [];
  List<ManagedSession> _sessions = const [];
  bool _loading = true;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Gently refresh while open so the board stays live.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _error == null;
      });
    }
    try {
      final c = widget.client;
      final results = await Future.wait([
        c.mcOverview(),
        c.mcTasks(archived: false),
        c.mcSessions(archived: false),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as MissionControlOverview;
        _tasks = results[1] as List<MissionControlTask>;
        _sessions = results[2] as List<ManagedSession>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _archiveTask(MissionControlTask t) async {
    try {
      await widget.client.mcArchiveTask(t.id);
      if (mounted) {
        toast(context, 'Archived "${t.title}"');
        setState(() => _tasks = _tasks.where((x) => x.id != t.id).toList());
        // Refresh overview counts.
        _refreshOverviewOnly();
      }
    } catch (e) {
      if (mounted) toast(context, 'Archive failed: $e', danger: true);
    }
  }

  Future<void> _archiveSession(ManagedSession s) async {
    try {
      await widget.client.mcArchiveSession(s.id);
      if (mounted) {
        toast(context, 'Archived session');
        setState(
            () => _sessions = _sessions.where((x) => x.id != s.id).toList());
        _refreshOverviewOnly();
      }
    } catch (e) {
      if (mounted) toast(context, 'Archive failed: $e', danger: true);
    }
  }

  /// Lightweight overview-only refresh after an archive.
  void _refreshOverviewOnly() {
    widget.client.mcOverview().then((ov) {
      if (mounted) setState(() => _overview = ov);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Mission Control',
            subtitle: _overview != null
                ? '${_overview!.activeTasks} active tasks · '
                    '${_overview!.activeSessions} active sessions'
                : (_loading ? 'Loading…' : null),
            onBack: widget.onClose ?? () => Navigator.pop(context),
            actions: [
              IconBtn('refresh',
                  size: 38,
                  iconSize: 19,
                  tooltip: 'Refresh',
                  onTap: _loading ? null : () => _refresh()),
            ],
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null && _overview == null) {
      return _errorState(_error!);
    }
    if (_loading && _overview == null) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final ov = _overview!;
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          // --- Overview stats ---
          _OverviewStats(overview: ov),
          const SizedBox(height: 24),

          // --- Active tasks ---
          const SectionLabel('Active tasks'),
          const SizedBox(height: 8),
          if (_tasks.isEmpty)
            _emptyCard(
                'No active tasks',
                'Tasks tracked by Mission Control '
                    'will appear here.'),
          for (final t in _tasks)
            _TaskCard(task: t, onArchive: () => _archiveTask(t)),
          if (_tasks.isNotEmpty) const SizedBox(height: 8),

          // --- Managed sessions ---
          const SectionLabel('Sessions'),
          const SizedBox(height: 8),
          if (_sessions.isEmpty)
            _emptyCard(
                'No managed sessions',
                'Sessions registered in '
                    'Mission Control will appear here.'),
          for (final s in _sessions)
            _SessionCard(session: s, onArchive: () => _archiveSession(s)),
        ],
      ),
    );
  }

  Widget _errorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('alert-triangle', size: 28, color: AppColors.danger),
          const SizedBox(height: 12),
          Text('Failed to load',
              style: sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: sans(12.5, color: AppColors.fg3)),
          const SizedBox(height: 20),
          IconBtn('refresh',
              size: 36, iconSize: 18, tooltip: 'Retry', onTap: _refresh),
        ]),
      ),
    );
  }

  Widget _emptyCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: sans(14, weight: FontWeight.w500, color: AppColors.fg2)),
        const SizedBox(height: 4),
        Text(body, style: sans(12, color: AppColors.fg4)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview stats row
// ---------------------------------------------------------------------------

class _OverviewStats extends StatelessWidget {
  final MissionControlOverview overview;
  const _OverviewStats({required this.overview});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _stat('Tasks', '${overview.activeTasks}', AppColors.accent),
      const SizedBox(width: 10),
      _stat('Completed', '${overview.completedTasks}', AppColors.ok),
      const SizedBox(width: 10),
      _stat('Sessions', '${overview.activeSessions}', AppColors.run),
    ]);
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: sans(22, weight: FontWeight.w600, color: color)),
          const SizedBox(height: 2),
          Text(label, style: mono(10.5, color: AppColors.fg3)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final MissionControlTask task;
  final VoidCallback onArchive;
  const _TaskCard({required this.task, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    final prioColor = _priorityColor(task.priority);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Status dot.
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            // Title + description.
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14,
                            weight: FontWeight.w600, color: AppColors.fg1)),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg3)),
                    ],
                  ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Meta row: status badge + priority badge + tags + archive.
          Row(children: [
            _badge(task.status.replaceAll('_', ' '), statusColor),
            const SizedBox(width: 6),
            _badge(task.priority, prioColor),
            if (task.assignee != null && task.assignee!.isNotEmpty) ...[
              const SizedBox(width: 6),
              _badge('→ ${task.assignee}', AppColors.fg3),
            ],
            for (final tag in task.tags.take(3)) ...[
              const SizedBox(width: 6),
              _badge(tag, AppColors.fg4),
            ],
            const Spacer(),
            GestureDetector(
              onTap: onArchive,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon('minimize', size: 16, color: AppColors.fg4),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  static Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Text(text, style: mono(10, color: color)),
    );
  }

  static Color _statusColor(String s) => switch (s) {
        'in_progress' => AppColors.run,
        'completed' => AppColors.ok,
        'failed' => AppColors.danger,
        _ => AppColors.fg3,
      };

  static Color _priorityColor(String p) => switch (p) {
        'critical' => AppColors.danger,
        'high' => AppColors.run,
        'medium' => AppColors.accent,
        _ => AppColors.fg4,
      };
}

// ---------------------------------------------------------------------------
// Session card
// ---------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  final ManagedSession session;
  final VoidCallback onArchive;
  const _SessionCard({required this.session, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    final healthColor = _healthColor(session.status);
    final lastActive = _age(session.lastActiveAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Health dot.
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: healthColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title.isEmpty ? session.folder : session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14,
                          weight: FontWeight.w600, color: AppColors.fg1),
                    ),
                    const SizedBox(height: 2),
                    Text(session.folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(11, color: AppColors.fg3)),
                  ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Meta row: status + age + tasks + profile + archive.
          Row(children: [
            _badge(session.status, healthColor),
            const SizedBox(width: 6),
            if (session.taskCount > 0)
              _badge(
                  '${session.taskCount} task${session.taskCount == 1 ? '' : 's'}',
                  AppColors.accent),
            if (session.profile != null && session.profile!.isNotEmpty) ...[
              const SizedBox(width: 6),
              _badge(session.profile!, AppColors.fg4),
            ],
            const Spacer(),
            Text(lastActive, style: mono(10, color: AppColors.fg4)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onArchive,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon('minimize', size: 16, color: AppColors.fg4),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  static Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Text(text, style: mono(10, color: color)),
    );
  }

  static Color _healthColor(String s) => switch (s) {
        'active' => AppColors.ok,
        'paused' => AppColors.run,
        'completed' => AppColors.fg3,
        'failed' => AppColors.danger,
        _ => AppColors.fg4,
      };

  static String _age(int epoch) {
    if (epoch <= 0) return '';
    final d = DateTime.now().toUtc().difference(
        DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true));
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Open the Mission Control board as a panel from anywhere with a client.
void openMissionControl(BuildContext context, DaemonClient client) {
  presentScreen(context,
      builder: (_, close) =>
          MissionControlScreen(client: client, onClose: close));
}
