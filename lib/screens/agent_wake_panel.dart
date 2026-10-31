import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';

/// Wake schedule, keep-warm and context length for one agent, in a popover on
/// desktop and a sheet on phones.
Future<void> showAgentWakeSettings(
  BuildContext context, {
  required DaemonClient client,
  required String owner,
  required String name,
  CoordinationAgent? agent,
  Offset? point,
  VoidCallback? onChanged,
}) {
  final panel = AgentWakePanel(
      client: client,
      owner: owner,
      name: name,
      agent: agent,
      onChanged: onChanged);
  if (kMobile) {
    return showAppSheet(context, title: name, maxHeight: 640, child: panel);
  }
  return showPointPopover<void>(context,
      point: point,
      width: 400,
      maxHeight: 700,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.s12),
          child: panel,
        ),
      ));
}

/// Overridden in tests so relative times stay stable.
@visibleForTesting
DateTime Function() wakeClock = DateTime.now;

String _clock(int unixSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final now = wakeClock();
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'today $hm';
  }
  final t = now.add(const Duration(days: 1));
  if (d.year == t.year && d.month == t.month && d.day == t.day) {
    return 'tomorrow $hm';
  }
  return '${d.day}/${d.month} $hm';
}

/// "in 25m" for a future time, "5m ago" for a past one.
String wakeWhen(int unixSec, {int? now}) {
  final n = now ?? wakeClock().millisecondsSinceEpoch ~/ 1000;
  final diff = unixSec - n;
  final span = diff.abs();
  final text = span < 60
      ? '<1m'
      : span < 3600
          ? '${span ~/ 60}m'
          : span < 86400
              ? '${span ~/ 3600}h'
              : '${span ~/ 86400}d';
  if (span < 60) return diff >= 0 ? 'in under a minute' : 'just now';
  return diff >= 0 ? 'in $text' : '$text ago';
}

Color wakeStatusColor(String? status) => switch (status) {
      'ok' || 'done' || 'completed' || 'success' => AppColors.ok,
      'error' || 'failed' => AppColors.danger,
      _ => AppColors.fg4,
    };

class AgentWakePanel extends StatefulWidget {
  const AgentWakePanel({
    super.key,
    required this.client,
    required this.owner,
    required this.name,
    this.agent,
    this.onChanged,
  });

  final DaemonClient client;
  final String owner;
  final String name;

  /// Present for a named agent; sessions have no context ceiling to set.
  final CoordinationAgent? agent;
  final VoidCallback? onChanged;

  @override
  State<AgentWakePanel> createState() => _AgentWakePanelState();
}

class _AgentWakePanelState extends State<AgentWakePanel> {
  WakeSchedule? _wake;
  WakeLimits _wakeLimits = const WakeLimits();
  List<WakeRun> _runs = const [];
  KeepWarmEntry? _warm;
  KeepWarmLimits _warmLimits = const KeepWarmLimits();
  int? _context;
  bool _loading = true;
  String? _error;

  bool _editing = false;
  bool _saving = false;
  bool _enabled = true;
  String _reportTo = 'mission_control';
  bool _onlyOnChange = true;
  final _schedule = TextEditingController();
  final _brief = TextEditingController();
  final _quietStart = TextEditingController();
  final _quietEnd = TextEditingController();
  final _taskId = TextEditingController();
  final _cap = TextEditingController();

  @override
  void initState() {
    super.initState();
    _context = widget.agent?.maxContextTokens;
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _schedule,
      _brief,
      _quietStart,
      _quietEnd,
      _taskId,
      _cap
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = widget.client;
    try {
      final wake = await c.wake(widget.owner);
      final runs = await c
          .wakeRuns(owner: widget.owner, limit: 3)
          .catchError((_) => <WakeRun>[]);
      final warm = await c.keepWarmFor(widget.owner).catchError((_) => null);
      final lists = await Future.wait<Object?>([
        c.wakes().then<Object?>((l) => l.limits).catchError((_) => null),
        c.keepWarm().then<Object?>((l) => l.limits).catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _wake = wake;
        _runs = runs;
        _warm = warm;
        _wakeLimits = lists[0] as WakeLimits? ?? _wakeLimits;
        _warmLimits = lists[1] as KeepWarmLimits? ?? _warmLimits;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _fail(Object e) {
    if (mounted) toast(context, '$e', danger: true);
  }

  void _startEdit() {
    final w = _wake;
    _schedule.text = w?.editableSchedule ?? '';
    _brief.text = w?.brief ?? '';
    _quietStart.text = w?.quietHours?.start ?? '';
    _quietEnd.text = w?.quietHours?.end ?? '';
    _taskId.text = w?.report.taskId ?? '';
    _cap.text = '${w?.maxRunsPerDay ?? _wakeLimits.defaultMaxRunsPerDay}';
    setState(() {
      _enabled = w?.enabled ?? true;
      _reportTo = w?.report.to ?? 'mission_control';
      _onlyOnChange = w?.report.onlyOnChange ?? true;
      _editing = true;
    });
  }

  Future<void> _save() async {
    final schedule = _schedule.text.trim();
    if (schedule.isEmpty) {
      toast(context, 'Enter a schedule, for example daily 09:00', danger: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final wake = await widget.client.setWake(widget.owner, {
        'schedule': schedule,
        'brief': _brief.text.trim(),
        'title': _wake?.title.isNotEmpty == true
            ? _wake!.title
            : 'Wake ${widget.name}',
        'enabled': _enabled,
        'quiet_start': _quietStart.text.trim(),
        'quiet_end': _quietEnd.text.trim(),
        'report': WakeReport(
                to: _reportTo,
                taskId:
                    _reportTo == 'task_room' && _taskId.text.trim().isNotEmpty
                        ? _taskId.text.trim()
                        : null,
                onlyOnChange: _onlyOnChange)
            .toJson(),
        if (int.tryParse(_cap.text.trim()) != null)
          'max_runs_per_day': int.parse(_cap.text.trim()),
      });
      if (!mounted) return;
      setState(() {
        _wake = wake;
        _editing = false;
        _saving = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _fail(e);
    }
  }

  Future<void> _remove() async {
    try {
      await widget.client.clearWake(widget.owner);
      if (!mounted) return;
      setState(() {
        _wake = null;
        _editing = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _toggleWake(bool on) async {
    final before = _wake;
    if (before == null) return;
    try {
      final wake = await widget.client.setWake(widget.owner, {'enabled': on});
      if (mounted) setState(() => _wake = wake);
      widget.onChanged?.call();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _pickReport(BuildContext anchor) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 240,
      maxWidth: 320,
      items: [
        for (final (v, label, sub) in const [
          ('mission_control', 'Mission Control', 'Summarised in its feed'),
          ('user', 'You', 'Sent as a notification'),
          ('task_room', 'Task room', 'Posted on a task'),
          ('none', 'Nobody', 'Runs silently'),
        ])
          appMenuRow<String>(
              value: v,
              icon: 'check-circle',
              label: label,
              description: sub,
              selected: v == _reportTo),
      ],
    );
    if (picked != null && mounted) setState(() => _reportTo = picked);
  }

  Future<void> _setWarm(bool on) async {
    final before = _warm;
    try {
      final entry = await widget.client.setKeepWarm(widget.owner,
          enabled: on,
          intervalMinutes:
              before?.intervalMinutes == 0 ? null : before?.intervalMinutes,
          maxIdleHours:
              before?.maxIdleHours == 0 ? null : before?.maxIdleHours);
      if (mounted) setState(() => _warm = entry);
      widget.onChanged?.call();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _pickWarmNumber(
      BuildContext anchor, bool interval, List<int> options) async {
    final w = _warm;
    if (w == null) return;
    final current = interval ? w.intervalMinutes : w.maxIdleHours;
    final picked = await showAppMenu<int>(
      context,
      anchor: anchor,
      minWidth: 200,
      maxWidth: 260,
      items: [
        appMenuHeading<int>(interval ? 'Ping every' : 'Stop after idle for'),
        for (final o in options)
          appMenuRow<int>(
              value: o,
              icon: 'repeat',
              label: interval ? '$o min' : '$o h',
              selected: o == current),
      ],
    );
    if (picked == null || picked == current) return;
    try {
      final entry = await widget.client.setKeepWarm(widget.owner,
          enabled: w.enabled,
          intervalMinutes: interval ? picked : w.intervalMinutes,
          maxIdleHours: interval ? w.maxIdleHours : picked);
      if (mounted) setState(() => _warm = entry);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _editContext(BuildContext anchor) async {
    final agent = widget.agent;
    if (agent == null) return;
    final text = await promptText(context,
        title: 'Context length for ${widget.name}',
        initial: _context == null ? '' : tokensLabel(_context!),
        hint: 'For example 128k. Minimum 16k; empty uses the model window.',
        anchored: true);
    if (text == null || !mounted) return;
    final next = text.trim().isEmpty ? null : parseTokens(text);
    if (text.trim().isNotEmpty &&
        (next == null || next < kMinAgentContextTokens)) {
      toast(context, 'Enter at least 16k tokens, for example 128k',
          danger: true);
      return;
    }
    if (next == _context) return;
    try {
      await widget.client.setAgentContext(agent.id, next);
      if (mounted) setState(() => _context = next);
      widget.onChanged?.call();
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: S.s24),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: S.s8),
            child: Text(_error!, style: sans(12, color: AppColors.danger)),
          ),
        _wakeSection(),
        if (widget.agent != null) ...[
          const SizedBox(height: S.s16),
          _contextSection(),
        ],
        const SizedBox(height: S.s16),
        _warmSection(),
        const SizedBox(height: S.s4),
      ],
    );
  }

  Widget _head(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6),
        child: Row(children: [
          Expanded(child: Text(text, style: TS.label(AppColors.fg2))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _line(String label, String value, {Color? color, Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 76,
              child: Text(label, style: sans(13, color: AppColors.fg4))),
          Expanded(
              child: Text(value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: color ?? AppColors.fg1))),
        ]),
      );

  Widget _wakeSection() {
    final w = _wake;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Wakes and reporting',
          trailing: _editing
              ? null
              : GestureDetector(
                  onTap: _startEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.s4),
                    child: Text(w == null ? 'Set schedule' : 'Edit',
                        style: sans(13, color: AppColors.accent)),
                  ),
                )),
      if (w == null && !_editing)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s4),
          child: Text(
              'No wake schedule. A wake gives ${widget.name} a brief on a timetable and reports back.',
              style: sans(13, color: AppColors.fg3)),
        ),
      if (w != null && !_editing) ...[
        _line('Schedule', w.scheduleText.isEmpty ? w.schedule : w.scheduleText,
            key: const ValueKey('wake-schedule')),
        if (w.brief.isNotEmpty) _line('Brief', w.brief),
        _line('Quiet hours', w.quietHours?.label ?? 'None'),
        _line('Reports to',
            '${w.report.label}${w.report.onlyOnChange ? ', only on change' : ''}'),
        _line(
            'Next',
            !w.enabled
                ? 'Paused'
                : w.queued
                    ? 'Queued behind the current goal'
                    : w.nextRunAt > 0
                        ? '${wakeWhen(w.nextRunAt)} (${_clock(w.nextRunAt)})'
                        : 'Not scheduled',
            key: const ValueKey('wake-next')),
        _line(
            'Last',
            w.lastRunAt == null
                ? 'Never run'
                : '${wakeWhen(w.lastRunAt!)}${w.lastStatus == null ? '' : ', ${w.lastStatus}'}',
            color: w.lastError != null ? AppColors.danger : null),
        if (w.lastError != null)
          _line('Error', w.lastError!, color: AppColors.danger)
        else if (w.lastResult != null)
          _line('Result', w.lastResult!),
        _line('Today', '${w.runsLastDay} of ${w.maxRunsPerDay} runs'),
        const SizedBox(height: S.s4),
        AppToggle(
            on: w.enabled,
            onChanged: _toggleWake,
            label: 'Wake enabled',
            sub: w.setBy.isEmpty ? null : 'Set by ${w.setBy}'),
      ],
      Reveal(show: _editing, child: _form()),
      if (_runs.isNotEmpty && !_editing) ...[
        const SizedBox(height: S.s8),
        _head('Recent runs'),
        for (final r in _runs) _runRow(r),
      ],
    ]);
  }

  Widget _runRow(WakeRun r) => Padding(
        key: ValueKey('run-${r.id}'),
        padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: S.s8),
            child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: wakeStatusColor(r.status), shape: BoxShape.circle)),
          ),
          Expanded(
            child: Text(
                r.summary == null ? r.status : '${r.status}: ${r.summary}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg2)),
          ),
          const SizedBox(width: S.s8),
          Text(wakeWhen(r.firedAt), style: mono(11, color: AppColors.fg4)),
        ]),
      );

  Widget _form() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(
          label: 'Schedule',
          controller: _schedule,
          mono: true,
          hint: 'every 30m, daily 09:00, weekdays 09:00, mon,thu 18:00',
          helper:
              'Shortest interval ${_wakeLimits.minAgentIntervalSecs ~/ 60} minutes. Times are in your time zone.'),
      const SizedBox(height: S.s12),
      AppField(
          label: 'Brief',
          controller: _brief,
          minLines: 2,
          maxLines: 5,
          hint: 'What to do on each wake'),
      const SizedBox(height: S.s12),
      Row(children: [
        Expanded(
            child: AppField(
                label: 'Quiet from',
                controller: _quietStart,
                mono: true,
                hint: '22:00')),
        const SizedBox(width: S.s8),
        Expanded(
            child: AppField(
                label: 'Quiet until',
                controller: _quietEnd,
                mono: true,
                hint: '07:00')),
      ]),
      const SizedBox(height: S.s12),
      Builder(
        builder: (ctx) => ListRow(
          title: 'Report to',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(WakeReport.labelFor(_reportTo),
                style: sans(13, color: AppColors.fg3)),
            const SizedBox(width: S.s6),
            AppIcon('chevron-down', size: 15, color: AppColors.fg4),
          ]),
          onTap: () => _pickReport(ctx),
        ),
      ),
      Reveal(
        show: _reportTo == 'task_room',
        child: Padding(
          padding: const EdgeInsets.only(top: S.s8),
          child: AppField(
              label: 'Task id', controller: _taskId, mono: true, hint: 'T-123'),
        ),
      ),
      const SizedBox(height: S.s8),
      AppToggle(
          on: _onlyOnChange,
          onChanged: (v) => setState(() => _onlyOnChange = v),
          label: 'Report only on change',
          sub: 'Skip reports when nothing is new'),
      const SizedBox(height: S.s8),
      AppToggle(
          on: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          label: 'Enabled'),
      const SizedBox(height: S.s12),
      AppField(
          label: 'Runs per day',
          controller: _cap,
          mono: true,
          keyboardType: TextInputType.number,
          helper: 'Up to ${_wakeLimits.maxRunsPerDayUser}'),
      const SizedBox(height: S.s12),
      Row(children: [
        if (_wake != null)
          Btn('Remove',
              variant: BtnVariant.danger, small: true, onTap: _remove),
        const Spacer(),
        Btn('Cancel',
            variant: BtnVariant.ghost,
            small: true,
            onTap: () => setState(() => _editing = false)),
        const SizedBox(width: S.s8),
        Btn(_saving ? 'Saving' : 'Save',
            small: true, disabled: _saving, onTap: _save),
      ]),
    ]);
  }

  Widget _warmSection() {
    final w = _warm;
    final on = w?.enabled ?? false;
    final reason = w?.reason;
    final ints = {
      for (final m in [
        _warmLimits.minIntervalMinutes,
        _warmLimits.defaultIntervalMinutes,
        5,
        10,
        15,
        30,
        _warmLimits.maxIntervalMinutes
      ])
        if (m >= _warmLimits.minIntervalMinutes &&
            m <= _warmLimits.maxIntervalMinutes)
          m
    }.toList()
      ..sort();
    final idles = {
      for (final h in [
        1,
        _warmLimits.defaultMaxIdleHours,
        4,
        8,
        _warmLimits.maxIdleHoursCeiling
      ])
        if (h >= 1 && h <= _warmLimits.maxIdleHoursCeiling) h
    }.toList()
      ..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Keep warm'),
      AppToggle(
          on: on,
          onChanged: _setWarm,
          label: 'Keep prompt cache warm',
          sub: 'Pings the idle session so its cached prefix is not re-billed'),
      Padding(
        key: const ValueKey('warm-reason'),
        padding: const EdgeInsets.fromLTRB(S.s4, S.s6, S.s4, 0),
        child: Text(
            reason ??
                (w?.lastWarmAt != null
                    ? 'Warmed ${wakeWhen(w!.lastWarmAt!)}${w.lastCacheReadTokens == null ? '' : ', ${tokensLabel(w.lastCacheReadTokens!)} tokens read from cache'}.'
                    : 'Most providers cannot be warmed. If this one cannot, the reason appears here.'),
            style: sans(12.5,
                color: reason != null ? AppColors.fg2 : AppColors.fg4)),
      ),
      Reveal(
        show: w != null && on,
        child: Column(children: [
          const SizedBox(height: S.s6),
          Builder(
            builder: (ctx) => ListRow(
              title: 'Ping every',
              trailing: Text('${w?.intervalMinutes ?? 0} min',
                  style: sans(13, color: AppColors.fg3)),
              onTap: () => _pickWarmNumber(ctx, true, ints),
            ),
          ),
          Builder(
            builder: (ctx) => ListRow(
              title: 'Stop after idle for',
              trailing: Text('${w?.maxIdleHours ?? 0} h',
                  style: sans(13, color: AppColors.fg3)),
              onTap: () => _pickWarmNumber(ctx, false, idles),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _contextSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Context length'),
      Builder(
        builder: (ctx) => ListRow(
          title: 'Compact above',
          subtitle: 'Smaller ceilings compact sooner and cost less per turn',
          trailing: Text(
              _context == null ? 'Model window' : tokensLabel(_context!),
              key: const ValueKey('context-value'),
              style: sans(13, color: AppColors.fg3)),
          onTap: () => _editContext(ctx),
        ),
      ),
    ]);
  }
}
