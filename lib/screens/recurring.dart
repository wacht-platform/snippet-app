import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Recurring pokes — list, create, pause, and delete jobs that fire into
/// Mission Control or any conversation as a normal scheduled chat turn.
class RecurringScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;
  /// Prefills create-sheet session (current chat, or `mission-control`).
  final String? defaultSessionId;
  final String? defaultSessionTitle;
  const RecurringScreen({
    super.key,
    required this.client,
    this.onClose,
    this.defaultSessionId,
    this.defaultSessionTitle,
  });
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late Future<List<RecurringJob>> _future;

  String get _defaultSessionId =>
      (widget.defaultSessionId?.trim().isNotEmpty == true)
          ? widget.defaultSessionId!.trim()
          : 'mission-control';

  @override
  void initState() {
    super.initState();
    _future = widget.client.recurringJobs();
  }

  void _refresh() {
    if (mounted) setState(() => _future = widget.client.recurringJobs());
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final prompt = TextEditingController();
    final plan = TextEditingController();
    final daily = TextEditingController(text: '09:00');
    var sessionId = _defaultSessionId;
    var schedule = 'every 1h';
    var customDaily = false;
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
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Schedule a poke',
                        style: sans(16, color: AppColors.fg1)),
                    const SizedBox(height: 6),
                    Text(
                      'Fires as a normal chat turn. Minimum interval is 5 minutes. Optional plan file is read at fire time.',
                      style: sans(12, height: 1.4, color: AppColors.fg3),
                    ),
                    const SizedBox(height: 14),
                    AppField(
                        label: 'Title',
                        controller: title,
                        hint: 'Nightly review'),
                    const SizedBox(height: 12),
                    Text('Session',
                        style: sans(12, color: AppColors.fg3)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _chip(
                        'Mission Control',
                        sessionId == 'mission-control',
                        () => setSheet(() => sessionId = 'mission-control'),
                      ),
                      if (_defaultSessionId != 'mission-control')
                        _chip(
                          widget.defaultSessionTitle?.trim().isNotEmpty == true
                              ? widget.defaultSessionTitle!
                              : 'This conversation',
                          sessionId == _defaultSessionId,
                          () => setSheet(() => sessionId = _defaultSessionId),
                        ),
                    ]),
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
                        _chip(s, !customDaily && schedule == s, () {
                          setSheet(() {
                            customDaily = false;
                            schedule = s;
                          });
                        }),
                      _chip('daily', customDaily, () {
                        setSheet(() {
                          customDaily = true;
                          schedule = 'daily ${daily.text.trim()}';
                        });
                      }),
                    ]),
                    if (customDaily) ...[
                      const SizedBox(height: 10),
                      AppField(
                          label: 'Time (HH:MM)',
                          controller: daily,
                          mono: true,
                          hint: '09:00',
                          onSubmitted: (v) => setSheet(
                              () => schedule = 'daily ${v.trim()}')),
                    ],
                    const SizedBox(height: 12),
                    AppField(
                        label: 'Prompt',
                        controller: prompt,
                        hint: 'What should the agent do?',
                        minLines: 3,
                        maxLines: 6),
                    const SizedBox(height: 12),
                    AppField(
                        label: 'Plan file (optional)',
                        controller: plan,
                        mono: true,
                        hint: 'notes/plan.md — read at fire time'),
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
    final sched = customDaily ? 'daily ${daily.text.trim()}' : schedule;
    title.dispose();
    prompt.dispose();
    plan.dispose();
    daily.dispose();
    if (saved != true) return;
    if (t.isEmpty) {
      if (mounted) toast(context, 'Title is required', danger: true);
      return;
    }
    if (p.isEmpty && planPath.isEmpty) {
      if (mounted) {
        toast(context, 'Prompt or plan file is required', danger: true);
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
                      'Scheduled pokes wake Mission Control or a conversation. Minimum interval is 5 minutes. A plan file is reread each fire.',
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

  Widget _jobRow(RecurringJob job) {
    final paused = !job.enabled;
    final target = job.sessionId == 'mission-control'
        ? 'Mission Control'
        : job.sessionId;
    final bits = <String>[
      job.scheduleLabel,
      target,
      if (job.queued) 'queued',
      if (paused) 'paused',
      if (job.planPath != null) job.planPath!,
    ];
    final sub = bits.where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AppIcon('clock',
              size: 16, color: paused ? AppColors.fg4 : AppColors.fg3),
        ),
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
