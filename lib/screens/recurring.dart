import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'files.dart';

/// Recurring goals — list, create, pause, and delete jobs that SetGoal a
/// session. The daemon detects `~/.snippet/recurring/<id>.json`. If that
/// session is already on a goal, the fire queues and starts immediately after
/// `complete_goal`.
class RecurringScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;
  /// Target session when creating (this chat, or Mission Control itself).
  /// Settings uses [listOnly]. Cross-session jobs are created by the MC agent
  /// via `create_recurring_job` (job files), not this UI.
  final String? sessionId;
  final String? workspace;
  /// Settings: list/pause/delete only — create from a chat menu.
  final bool listOnly;
  const RecurringScreen({
    super.key,
    required this.client,
    this.onClose,
    this.sessionId,
    this.workspace,
    this.listOnly = false,
  });
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late Future<List<RecurringJob>> _future;

  String get _boundSessionId {
    final id = widget.sessionId?.trim() ?? '';
    return id.isEmpty ? 'mission-control' : id;
  }

  bool get _canAdd => !widget.listOnly;

  @override
  void initState() {
    super.initState();
    _future = widget.client.recurringJobs();
  }

  void _refresh() {
    if (mounted) setState(() => _future = widget.client.recurringJobs());
  }

  Future<void> _add() async {
    if (!_canAdd) return;
    final title = TextEditingController();
    final prompt = TextEditingController();
    final plan = TextEditingController();
    final daily = TextEditingController(text: '09:00');
    final customEvery = TextEditingController();
    var sessionId = _boundSessionId;
    var schedule = 'every 1h';
    var mode = 'preset'; // preset | custom | daily
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          Future<void> pickPlan() async {
            final start = (widget.workspace?.trim().isNotEmpty == true)
                ? widget.workspace
                : null;
            final picked = await presentScreen<String>(
              context,
              builder: (_, close) => FileExplorer(
                client: widget.client,
                title: 'Plan file',
                start: start,
                onClose: close,
                onPickFile: (path) {},
              ),
            );
            if (picked != null && picked.trim().isNotEmpty) {
              plan.text = picked.trim();
              setSheet(() {});
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Schedule a goal',
                        style: sans(16, color: AppColors.fg1)),
                    const SizedBox(height: 6),
                    Text(
                      'Each fire sets an autonomous goal on this chat. Minimum interval is 5 minutes. If a goal is already running, the next fire waits and starts the moment it completes. A plan file is reread each fire.',
                      style: sans(12, height: 1.4, color: AppColors.fg3),
                    ),
                    const SizedBox(height: 14),
                    AppField(
                        label: 'Title',
                        controller: title,
                        hint: 'Nightly review'),
                    const SizedBox(height: 12),
                    Text('Schedule',
                        style: sans(12, color: AppColors.fg3)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in const [
                        'every 5m',
                        'every 15m',
                        'every 1h',
                        'every 1d',
                      ])
                        _chip(s, mode == 'preset' && schedule == s, () {
                          setSheet(() {
                            mode = 'preset';
                            schedule = s;
                          });
                        }),
                      _chip('custom', mode == 'custom', () {
                        setSheet(() => mode = 'custom');
                      }),
                      _chip('daily', mode == 'daily', () {
                        setSheet(() => mode = 'daily');
                      }),
                    ]),
                    if (mode == 'custom') ...[
                      const SizedBox(height: 10),
                      AppField(
                          label: 'Every (min 5m)',
                          controller: customEvery,
                          mono: true,
                          hint: '5m  ·  90m  ·  2h  ·  300s'),
                    ],
                    if (mode == 'daily') ...[
                      const SizedBox(height: 10),
                      AppField(
                          label: 'Time (HH:MM)',
                          controller: daily,
                          mono: true,
                          hint: '09:00'),
                    ],
                    const SizedBox(height: 12),
                    AppField(
                        label: 'Goal',
                        controller: prompt,
                        hint: 'The piece of work to complete',
                        minLines: 3,
                        maxLines: 6),
                    const SizedBox(height: 12),
                    AppField(
                        label: 'Plan file (optional)',
                        controller: plan,
                        mono: true,
                        hint: 'notes/plan.md — pick or type a path',
                        rightSlot: IconBtn('folder',
                            size: 32,
                            iconSize: 16,
                            tooltip: 'Pick file',
                            onTap: pickPlan)),
                    const SizedBox(height: 16),
                    Btn('Save',
                        full: true, onTap: () => Navigator.pop(ctx, true)),
                    const SizedBox(height: 8),
                  ]),
            ),
          );
        },
      ),
    );
    final t = title.text.trim();
    final p = prompt.text.trim();
    final planPath = plan.text.trim();
    final sched = switch (mode) {
      'daily' => 'daily ${daily.text.trim()}',
      'custom' => _customSchedule(customEvery.text),
      _ => schedule,
    };
    title.dispose();
    prompt.dispose();
    plan.dispose();
    daily.dispose();
    customEvery.dispose();
    if (saved != true) return;
    if (t.isEmpty) {
      if (mounted) toast(context, 'Title is required', danger: true);
      return;
    }
    if (p.isEmpty && planPath.isEmpty) {
      if (mounted) {
        toast(context, 'Goal or plan file is required', danger: true);
      }
      return;
    }
    if (sched == null) {
      if (mounted) {
        toast(context, 'Interval must be at least 5 minutes (e.g. 5m, 2h)',
            danger: true);
      }
      return;
    }
    try {
      await widget.client.createRecurring(
        title: t,
        sessionId: sessionId,
        prompt: p,
        planPath: planPath.isEmpty ? null : planPath,
        schedule: sched,
      );
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  String? _customSchedule(String raw) {
    final t = raw.trim().toLowerCase().replaceAll(' ', '');
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d+)([smhd])$').firstMatch(t);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!) ?? 0;
    if (n <= 0) return null;
    final unit = m.group(2)!;
    final secs = switch (unit) {
      's' => n,
      'm' => n * 60,
      'h' => n * 3600,
      'd' => n * 86400,
      _ => 0,
    };
    if (secs < 300) return null;
    return 'every $n$unit';
  }

  Future<void> _toggle(RecurringJob job) async {
    try {
      await widget.client.updateRecurring(job.id, enabled: !job.enabled);
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _remove(RecurringJob job) async {
    try {
      await widget.client.deleteRecurring(job.id);
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
              color: on ? AppColors.accent : AppColors.border),
        ),
        child: Text(label,
            style: sans(12, color: on ? AppColors.accent : AppColors.fg2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Recurring',
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(
            child: FutureBuilder<List<RecurringJob>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.fg3)));
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    child: Text('${snap.error}',
                        style: sans(13, height: 1.4, color: AppColors.danger)),
                  );
                }
                final jobs = snap.data ?? const [];
                final list = ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    Text(
                      widget.listOnly
                          ? 'Scheduled goals across chats. Pause or delete here. Create from a chat or Mission Control menu. If a session is already on a goal, the next fire starts the moment it completes.'
                          : 'Each fire sets an autonomous goal on this chat. Minimum 5 minutes. A plan file is reread each fire. If a goal is already running, the next one queues and starts immediately after.',
                      style: sans(12, height: 1.4, color: AppColors.fg3),
                    ),
                    const SizedBox(height: 10),
                    if (jobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                        child: Text('No recurring jobs yet.',
                            style: sans(13, color: AppColors.fg3)),
                      ),
                    ...jobs.map(_jobRow),
                    if (_canAdd) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _add,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            AppIcon('plus', size: 16, color: AppColors.fg3),
                            const SizedBox(width: 12),
                            Text('Add job',
                                style: sans(14, color: AppColors.fg2)),
                          ]),
                        ),
                      ),
                    ],
                  ],
                );
                return kMobile
                    ? list
                    : Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: list));
              },
            ),
          ),
        ]),
      ),
    );
  }

  String _nextIn(RecurringJob job) {
    if (!job.enabled) return 'paused';
    if (job.queued) return 'queued — next after current goal';
    if (job.nextRunAt <= 0) return '';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final secs = job.nextRunAt - now;
    if (secs <= 0) return 'due now';
    if (secs < 60) return 'next in <1 min';
    final mins = (secs + 59) ~/ 60;
    if (mins < 60) return 'next in $mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    if (hours < 24) {
      return rem == 0 ? 'next in ${hours}h' : 'next in ${hours}h ${rem}m';
    }
    final days = hours ~/ 24;
    return 'next in ${days}d';
  }

  Widget _jobRow(RecurringJob job) {
    final paused = !job.enabled;
    final target = job.sessionId == 'mission-control'
        ? 'Mission Control'
        : job.sessionId;
    final bits = <String>[
      job.scheduleLabel,
      target,
      _nextIn(job),
      if (job.planPath != null) job.planPath!,
    ];
    final sub = bits.where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        AppIcon('clock',
            size: 16, color: paused ? AppColors.fg4 : AppColors.fg3),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job.title.isEmpty ? job.id : job.title,
                style: sans(14, color: paused ? AppColors.fg3 : AppColors.fg1)),
            const SizedBox(height: 2),
            Text(sub, style: sans(12, color: AppColors.fg4)),
            if (job.lastError != null && job.lastError!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(job.lastError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.danger)),
            ],
          ]),
        ),
        IconBtn(paused ? 'play' : 'pause',
            size: 32,
            iconSize: 16,
            tooltip: paused ? 'Resume' : 'Pause',
            onTap: () => _toggle(job)),
        IconBtn('trash',
            size: 32,
            iconSize: 16,
            tooltip: 'Delete',
            onTap: () => _remove(job)),
      ]),
    );
  }
}
