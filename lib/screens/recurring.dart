import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'files.dart';
import 'mission_control.dart';
import 'shell_nav.dart';

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

  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;

  /// Host-supplied back action for [embedded] use. This screen draws its OWN
  /// `NavBackRow`, so exactly one header exists per level.
  final VoidCallback? onBack;
  final ValueChanged<bool>? onAddingChanged;

  /// Docked in the desktop side pane: compact insets and its own small header,
  /// since the pane's tab strip carries only the name.
  final bool pane;

  const RecurringScreen({
    super.key,
    required this.client,
    this.onClose,
    this.sessionId,
    this.workspace,
    this.listOnly = false,
    this.embedded = false,
    this.onBack,
    this.onAddingChanged,
    this.pane = false,
  });
  @override
  State<RecurringScreen> createState() => RecurringScreenState();
}

class RecurringScreenState extends State<RecurringScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<List<RecurringJob>> _future;
  List<SessionInfo>? _sessions;
  StreamSubscription<dynamic>? _eventsSub;
  Timer? _refreshDebounce;
  Timer? _eventsReconnect;
  bool _closed = false;

  bool _adding = false;
  bool get isAdding => _adding;
  bool _submitting = false;
  final _titleCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  final _dailyCtrl = TextEditingController(text: '09:00');
  final _customEveryCtrl = TextEditingController();
  String _mode = 'preset';
  String _schedule = 'every 1h';

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant RecurringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.sessionId != widget.sessionId) {
      _future = widget.client.recurringJobs();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _refreshDebounce?.cancel();
    _eventsReconnect?.cancel();
    _eventsSub?.cancel();
    _titleCtrl.dispose();
    _promptCtrl.dispose();
    _planCtrl.dispose();
    _dailyCtrl.dispose();
    _customEveryCtrl.dispose();
    super.dispose();
  }

  void _scheduleEventsReconnect() {
    if (_closed || !mounted || (_eventsReconnect?.isActive ?? false)) return;
    _eventsReconnect = Timer(const Duration(seconds: 3), () {
      if (!_closed && mounted) _watchEvents();
    });
  }

  void _watchEvents() {
    _eventsSub?.cancel();
    try {
      _eventsSub = widget.client.events().stream.listen((msg) {
        try {
          final raw = msg is String ? msg : msg.toString();
          final event = jsonDecode(raw);
          if (event is Map && event['kind'] == 'recurring') {
            _refreshDebounce?.cancel();
            _refreshDebounce =
                Timer(const Duration(milliseconds: 150), _refresh);
          }
        } catch (_) {
          // The schedule list remains usable if an unrelated event is malformed.
        }
      },
          onError: (_) => _scheduleEventsReconnect(),
          onDone: _scheduleEventsReconnect);
    } catch (_) {
      _scheduleEventsReconnect();
    }
  }

  String get _boundSessionId {
    final id = widget.sessionId?.trim() ?? '';
    return id.isEmpty ? 'mission-control' : id;
  }

  bool get _canAdd => !widget.listOnly;

  @override
  void initState() {
    super.initState();
    _future = widget.client.recurringJobs();
    _watchEvents();
    widget.client.sessions().then((s) {
      if (mounted) setState(() => _sessions = s);
    }).catchError((_) {});
  }

  void _refresh() {
    if (mounted) setState(() => _future = widget.client.recurringJobs());
  }

  void add() => _add();

  Future<void> _add() async {
    if (!_canAdd) return;
    if (!kMobile) {
      setState(() {
        _titleCtrl.clear();
        _promptCtrl.clear();
        _planCtrl.clear();
        _dailyCtrl.text = '09:00';
        _customEveryCtrl.clear();
        _mode = 'preset';
        _schedule = 'every 1h';
        _submitting = false;
        _adding = true;
      });
      widget.onAddingChanged?.call(true);
      return;
    }
    final title = TextEditingController();
    final prompt = TextEditingController();
    final plan = TextEditingController();
    final daily = TextEditingController(text: '09:00');
    final customEvery = TextEditingController();
    var sessionId = _boundSessionId;
    var schedule = 'every 1h';
    var mode = 'preset'; // preset | custom | daily | onceAt | onceIn
    final saved = await showModalBottomSheet<bool>(
      sheetAnimationStyle: sheetMotion,
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
                    Text('Schedule a goal or message',
                        style: sans(14, weight: W.label, color: AppColors.fg1)),
                    const SizedBox(height: 10),
                    Text(
                      'The first run fires immediately, then repeats per the schedule. Minimum interval is 5 minutes. A plan file is reread each fire.',
                      style: sans(12, height: 1.4, color: AppColors.fg3),
                    ),
                    const SizedBox(height: 14),
                    AppField(
                        label: 'Title',
                        controller: title,
                        hint: 'Nightly review'),
                    const SizedBox(height: 12),
                    Text('Schedule', style: TS.meta()),
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
                      _chip('once at', mode == 'onceAt', () {
                        setSheet(() => mode = 'onceAt');
                      }),
                      _chip('once in', mode == 'onceIn', () {
                        setSheet(() => mode = 'onceIn');
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
                    if (mode == 'onceAt') ...[
                      const SizedBox(height: 10),
                      AppField(
                          label: 'Time today/tomorrow (HH:MM)',
                          controller: daily,
                          mono: true,
                          hint: '14:30'),
                    ],
                    if (mode == 'onceIn') ...[
                      const SizedBox(height: 10),
                      AppField(
                          label: 'From now (e.g. 30m, 2h)',
                          controller: customEvery,
                          mono: true,
                          hint: '30m'),
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
      'onceAt' => 'at ${daily.text.trim()}',
      'onceIn' => 'in ${customEvery.text.trim()}',
      'custom' => _customSchedule(customEvery.text),
      _ => schedule,
    };
    const label = 'Goal';
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
        toast(context, '$label or plan file is required', danger: true);
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
        goal: true,
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
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: kMobile ? 14 : 6),
        decoration: BoxDecoration(
          // Selection = a NEUTRAL surface step, accent reserved for state.
          color: on ? AppColors.surface3 : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: on ? AppColors.border2 : AppColors.border),
        ),
        child: Text(label,
            style: sans(12, color: on ? AppColors.fg1 : AppColors.fg2)),
      ),
    );
  }

  Future<void> _saveInline() async {
    if (_submitting) return;
    final t = _titleCtrl.text.trim();
    final p = _promptCtrl.text.trim();
    final planPath = _planCtrl.text.trim();
    final sched = switch (_mode) {
      'daily' => 'daily ${_dailyCtrl.text.trim()}',
      'onceAt' => 'at ${_dailyCtrl.text.trim()}',
      'onceIn' => 'in ${_customEveryCtrl.text.trim()}',
      'custom' => _customSchedule(_customEveryCtrl.text),
      _ => _schedule,
    };
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
    setState(() => _submitting = true);
    try {
      await widget.client.createRecurring(
        title: t,
        sessionId: _boundSessionId,
        prompt: p,
        planPath: planPath.isEmpty ? null : planPath,
        schedule: sched,
        goal: true,
      );
      if (mounted) {
        setState(() {
          _adding = false;
          _submitting = false;
        });
        widget.onAddingChanged?.call(false);
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        toast(context, '$e', danger: true);
      }
    }
  }

  Future<void> _pickPlanInline() async {
    final start =
        (widget.workspace?.trim().isNotEmpty == true) ? widget.workspace : null;
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
    if (picked != null && picked.trim().isNotEmpty && mounted) {
      setState(() {
        _planCtrl.text = picked.trim();
      });
    }
  }

  Widget _inlineAddCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule a goal or message',
                  style: TS.label(AppColors.fg1),
                ),
              ),
              IconBtn('x', size: 24, iconSize: 13, tooltip: 'Cancel',
                  onTap: () {
                setState(() => _adding = false);
                widget.onAddingChanged?.call(false);
              }),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The first run fires immediately, then repeats per the schedule. Minimum interval is 5 minutes.',
            style: TS.meta(),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Title',
            controller: _titleCtrl,
            hint: 'Nightly review',
          ),
          const SizedBox(height: 10),
          Text('Schedule', style: TS.meta()),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in const [
              'every 5m',
              'every 15m',
              'every 1h',
              'every 1d',
            ])
              _chip(s, _mode == 'preset' && _schedule == s, () {
                setState(() {
                  _mode = 'preset';
                  _schedule = s;
                });
              }),
            _chip('custom', _mode == 'custom', () {
              setState(() => _mode = 'custom');
            }),
            _chip('daily', _mode == 'daily', () {
              setState(() => _mode = 'daily');
            }),
            _chip('once at', _mode == 'onceAt', () {
              setState(() => _mode = 'onceAt');
            }),
            _chip('once in', _mode == 'onceIn', () {
              setState(() => _mode = 'onceIn');
            }),
          ]),
          if (_mode == 'custom') ...[
            const SizedBox(height: 8),
            AppField(
              label: 'Every (min 5m)',
              controller: _customEveryCtrl,
              mono: true,
              hint: '5m  ·  90m  ·  2h  ·  300s',
            ),
          ],
          if (_mode == 'daily') ...[
            const SizedBox(height: 8),
            AppField(
              label: 'Time (HH:MM)',
              controller: _dailyCtrl,
              mono: true,
              hint: '09:00',
            ),
          ],
          if (_mode == 'onceAt') ...[
            const SizedBox(height: 8),
            AppField(
              label: 'Time today/tomorrow (HH:MM)',
              controller: _dailyCtrl,
              mono: true,
              hint: '14:30',
            ),
          ],
          if (_mode == 'onceIn') ...[
            const SizedBox(height: 8),
            AppField(
              label: 'From now (e.g. 30m, 2h)',
              controller: _customEveryCtrl,
              mono: true,
              hint: '30m',
            ),
          ],
          const SizedBox(height: 10),
          AppField(
            label: 'Goal',
            controller: _promptCtrl,
            hint: 'The piece of work to complete',
            minLines: 2,
            maxLines: 5,
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'Plan file (optional)',
            controller: _planCtrl,
            mono: true,
            hint: 'notes/plan.md — pick or type a path',
            rightSlot: IconBtn('folder',
                size: 28,
                iconSize: 14,
                tooltip: 'Pick file',
                onTap: _pickPlanInline),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Btn('Cancel', small: true, variant: BtnVariant.ghost, onTap: () {
                setState(() => _adding = false);
                widget.onAddingChanged?.call(false);
              }),
              const SizedBox(width: 8),
              Btn('Save job',
                  small: true, disabled: _submitting, onTap: _saveInline),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(context); // Rebuild on theme change
    final body = FutureBuilder<List<RecurringJob>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ListSkeleton();
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Text('${snap.error}',
                style: sans(13, height: 1.4, color: AppColors.danger)),
          );
        }
        final allJobs = snap.data ?? const [];
        final bound = widget.sessionId?.trim();
        final jobs = (bound != null && bound.isNotEmpty)
            ? allJobs.where((j) {
                if (isDedicatedMcSession(bound) || bound == 'mission-control') {
                  return j.sessionId == 'mission-control' ||
                      isDedicatedMcSession(j.sessionId);
                }
                return j.sessionId == bound || j.sessionId.contains(bound);
              }).toList()
            : allJobs;
        final children = [
          if (widget.pane)
            Row(children: [
              Expanded(child: PaneLabel('Scheduled jobs · ${jobs.length}')),
              if (_canAdd && !_adding)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.s8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.xs),
                    onTap: _add,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: S.s4, vertical: 2),
                      child: Text('+ New',
                          style: mono(10, color: AppColors.accent)),
                    ),
                  ),
                ),
            ]),
          if (_adding) ...[_inlineAddCard(), const SizedBox(height: S.s12)],
          if (jobs.isEmpty && !_adding)
            EmptyState(
              icon: 'repeat',
              title: 'No scheduled jobs',
              body:
                  'Run a prompt on a schedule, like a morning triage or a nightly audit.',
              action: _canAdd
                  ? HeaderAction('New job', onTap: _add)
                  : null,
            )
          else if (jobs.isNotEmpty)
            ListGroup(children: [for (final j in jobs) _jobRow(j)]),
        ];
        if (!widget.pane) return PageBody(children: children);
        return ListView(
          padding: const EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s24),
          children: children,
        );
      },
    );
    // Three cases, and the header differs for each:
    //   not embedded        → owned Scaffold + SnAppBar
    //   embedded + onBack   → OWNED NavBackRow (phone drill-down)
    //   embedded, no onBack → NO header (desktop dialog pane; the host's section
    //                         chip strip is the navigation)
    // Drawing a row regardless is what stacked two back rows in the editor.
    if (!widget.embedded) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            SnAppBar(
                title: 'Scheduled jobs',
                compact: true,
                onBack: widget.onClose ?? () => Navigator.pop(context),
                actions: [
                  if (_canAdd && !_adding)
                    HeaderAction('New job', onTap: _add),
                ]),
            Expanded(child: body),
          ]),
        ),
      );
    }
    // Embedded with a back action → phone drill-down, so THIS level owns the
    // header. Embedded without one → the desktop dialog pane, where the host's
    // section chip strip is the navigation and a back row would duplicate it.
    if (widget.onBack == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavBackRow(title: 'Scheduled jobs', onBack: widget.onBack!, trailing: [
          if (_canAdd && !_adding)
            HeaderAction('New job', onTap: _add),
        ]),
        Expanded(child: body),
      ],
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

  String _targetLabel(RecurringJob job) {
    if (job.sessionId == 'mission-control' ||
        isDedicatedMcSession(job.sessionId)) {
      return 'Mission Control';
    }
    final match = _sessions
        ?.where((s) => s.id == job.sessionId || job.sessionId.contains(s.id))
        .firstOrNull;
    if (match != null && match.folder.isNotEmpty) {
      return lastPathSegment(match.folder, ifEmpty: match.title);
    }
    final clean = job.sessionId.replaceAll('.json', '');
    if (clean.contains('/conversations/')) {
      final parts = clean.split('/conversations/');
      if (parts.length == 2 && parts[1].isNotEmpty) {
        return parts[1].length > 8 ? parts[1].substring(0, 8) : parts[1];
      }
    }
    return lastPathSegment(clean, ifEmpty: clean);
  }

  Widget _jobRow(RecurringJob job) {
    final paused = !job.enabled;
    final target = _targetLabel(job);
    final bits = <String>[
      if (!job.delivery) 'message',
      job.scheduleLabel,
      target,
      _nextIn(job),
      if (job.planPath != null) job.planPath!,
    ];
    final sub = bits.where((s) => s.isNotEmpty).join(' · ');
    final error = job.lastError?.trim() ?? '';
    final dense = !kMobile;
    final btn = dense ? 26.0 : 32.0;
    final ico = dense ? 13.0 : 16.0;
    return Padding(
      padding: dense
          ? const EdgeInsets.fromLTRB(12, 8, 4, 8)
          : const EdgeInsets.fromLTRB(S.s12, S.s12, S.s4, S.s12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (dense)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: paused ? AppColors.fg4 : AppColors.accent,
                  shape: BoxShape.circle),
            ),
          )
        else ...[
          IconTile('repeat', tone: paused ? Tone.neutral : Tone.accent),
          const SizedBox(width: S.s12),
        ],
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(job.title.isEmpty ? job.id : job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dense
                        ? sans(13,
                            color: paused ? AppColors.fg3 : AppColors.fg1)
                        : TS.rowTitle(paused ? AppColors.fg3 : AppColors.fg1)),
              ),
              if (paused && !dense) ...[
                const SizedBox(width: S.s8),
                const Tag('Paused'),
              ],
            ]),
            const SizedBox(height: S.s2),
            Text(sub,
                style: dense ? mono(10, color: AppColors.fg3) : TS.meta()),
            if (error.isNotEmpty) ...[
              const SizedBox(height: S.s4),
              Text(error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dense
                      ? sans(12, color: AppColors.danger)
                      : TS.meta(AppColors.danger)),
            ],
          ]),
        ),
        Semantics(
          button: true,
          label: paused ? 'Resume scheduled job' : 'Pause scheduled job',
          child: IconBtn(paused ? 'play' : 'pause',
              size: btn,
              iconSize: ico,
              tooltip: paused ? 'Resume' : 'Pause',
              onTap: () => _toggle(job)),
        ),
        Semantics(
          button: true,
          label: 'Delete scheduled job',
          child: IconBtn('trash',
              size: btn,
              iconSize: ico,
              tooltip: 'Delete',
              onTap: () => _remove(job)),
        ),
      ]),
    );
  }
}
