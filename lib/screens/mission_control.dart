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
  bool _archiving = false;
  int _refreshGeneration = 0;
  String? _error;
  String? _backgroundError;
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
    final generation = ++_refreshGeneration;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _backgroundError = null;
      });
    }
    try {
      final c = widget.client;
      final results = await Future.wait([
        c.mcOverview(),
        c.mcTasks(archived: false),
        c.mcSessions(archived: false),
      ]);
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _overview = results[0] as MissionControlOverview;
        _tasks = results[1] as List<MissionControlTask>;
        _sessions = results[2] as List<ManagedSession>;
        _loading = false;
        _error = null;
        _backgroundError = null;
      });
    } catch (e) {
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _loading = false;
        if (_overview == null) {
          _error = '$e';
        } else {
          _backgroundError = '$e';
        }
      });
    }
  }

  Future<void> _archiveTask(MissionControlTask task) async {
    final confirmed = await confirmAction(
      context,
      title: 'Archive task?',
      body:
          '“${task.title}” will be cancelled and removed from the active board.',
      confirmLabel: 'Archive task',
    );
    if (!confirmed || !mounted || _archiving) return;
    setState(() => _archiving = true);
    try {
      await widget.client.mcArchiveTask(task.id);
      if (!mounted) return;
      toast(context, 'Archived “${task.title}”');
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, 'Archive failed: $e', danger: true);
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _archiveSession(ManagedSession session) async {
    final label = session.title.isEmpty ? session.folder : session.title;
    final confirmed = await confirmAction(
      context,
      title: 'Archive session?',
      body:
          '“$label” will be removed from Mission Control. Its history is kept.',
      confirmLabel: 'Archive session',
    );
    if (!confirmed || !mounted || _archiving) return;
    setState(() => _archiving = true);
    try {
      await widget.client.mcArchiveSession(session.id);
      if (!mounted) return;
      toast(context, 'Archived session');
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, 'Archive failed: $e', danger: true);
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
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
                  size: 44,
                  iconSize: 19,
                  tooltip: _loading ? 'Refreshing' : 'Refresh',
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
    final activeTasks = _tasks.where((task) => task.isActive).toList();
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          if (_backgroundError != null) ...[
            _staleDataNotice(),
            const SizedBox(height: 12),
          ],
          _OverviewStats(overview: ov),
          const SizedBox(height: 24),
          const SectionLabel('Active tasks'),
          const SizedBox(height: 8),
          if (activeTasks.isEmpty)
            _emptyCard(
                'No active tasks',
                'Tasks tracked by Mission Control '
                    'will appear here.'),
          for (final task in activeTasks)
            _TaskCard(
                task: task,
                archiving: _archiving,
                onArchive: () => _archiveTask(task)),
          if (activeTasks.isNotEmpty) const SizedBox(height: 8),
          const SectionLabel('Sessions'),
          const SizedBox(height: 8),
          if (_sessions.isEmpty)
            _emptyCard(
                'No managed sessions',
                'Sessions registered in '
                    'Mission Control will appear here.'),
          for (final session in _sessions)
            _SessionCard(
                session: session,
                archiving: _archiving,
                onArchive: () => _archiveSession(session)),
        ],
      ),
    );
  }

  Widget _staleDataNotice() {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          AppIcon('alert-triangle', size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Could not refresh. Showing the last available data.',
                style: sans(12, color: AppColors.fg2)),
          ),
          IconBtn('refresh',
              size: 36,
              iconSize: 17,
              tooltip: 'Retry refresh',
              onTap: _loading ? null : () => _refresh()),
        ]),
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
              size: 44,
              iconSize: 18,
              tooltip: _loading ? 'Refreshing' : 'Retry',
              onTap: _loading ? null : () => _refresh()),
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
  final bool archiving;
  final VoidCallback onArchive;
  const _TaskCard({
    required this.task,
    required this.archiving,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
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
          Row(children: [
            _badge(task.status.replaceAll('_', ' '), statusColor),
            const Spacer(),
            _ArchiveButton(
              label: 'Archive task',
              enabled: !archiving,
              onTap: onArchive,
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
        'done' || 'completed' => AppColors.ok,
        'blocked' || 'failed' || 'cancelled' => AppColors.danger,
        _ => AppColors.fg3,
      };
}

class _ArchiveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ArchiveButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(R.md),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AppIcon('trash',
                    size: 18, color: enabled ? AppColors.fg3 : AppColors.fg4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session card
// ---------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  final ManagedSession session;
  final bool archiving;
  final VoidCallback onArchive;
  const _SessionCard({
    required this.session,
    required this.archiving,
    required this.onArchive,
  });

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
            const Spacer(),
            Text(lastActive, style: mono(10, color: AppColors.fg4)),
            const SizedBox(width: 4),
            _ArchiveButton(
              label: 'Archive session',
              enabled: !archiving,
              onTap: onArchive,
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
        'archived' => AppColors.fg4,
        _ => AppColors.fg3,
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
