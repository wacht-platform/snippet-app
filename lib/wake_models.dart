// Wake schedules, their runs, and prompt-cache keep-warm, as the daemon
// reports them.

int? _int(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) {
  final s = v is String ? v.trim() : '';
  return s.isEmpty ? null : s;
}

class WakeQuietHours {
  final String start;
  final String end;
  const WakeQuietHours(this.start, this.end);

  static WakeQuietHours? parse(dynamic raw) {
    if (raw is! Map) return null;
    final s = _str(raw['start']);
    final e = _str(raw['end']);
    return s == null || e == null ? null : WakeQuietHours(s, e);
  }

  String get label => '$start to $end';
}

/// Where a wake's result is sent: mission_control, user, task_room or none.
class WakeReport {
  final String to;
  final String? taskId;
  final bool onlyOnChange;
  const WakeReport(
      {this.to = 'mission_control', this.taskId, this.onlyOnChange = true});

  factory WakeReport.fromJson(dynamic j) => j is Map
      ? WakeReport(
          to: _str(j['to']) ?? 'mission_control',
          taskId: _str(j['task_id']),
          onlyOnChange: j['only_on_change'] as bool? ?? true)
      : const WakeReport();

  Map<String, dynamic> toJson() =>
      {'to': to, 'task_id': taskId, 'only_on_change': onlyOnChange};

  static String labelFor(String to) => switch (to) {
        'mission_control' => 'Mission Control',
        'user' => 'You',
        'task_room' => 'Task room',
        'none' => 'Nobody',
        _ => to,
      };

  String get label => labelFor(to);
}

class WakeSchedule {
  final String owner;
  final String ownerKind;
  final String jobId;
  final String sessionId;
  final String title;
  final String brief;
  final String schedule;
  final String scheduleText;
  final bool enabled;
  final WakeQuietHours? quietHours;
  final int? utcOffsetMinutes;
  final WakeReport report;
  final String setBy;
  final int maxRunsPerDay;
  final int runsLastDay;
  final int nextRunAt;
  final int? lastRunAt;
  final String? lastStatus;
  final String? lastResult;
  final String? lastError;
  final bool queued;

  WakeSchedule.fromJson(Map<String, dynamic> j)
      : owner = j['owner'] as String? ?? '',
        ownerKind = j['owner_kind'] as String? ?? 'agent',
        jobId = j['job_id'] as String? ?? '',
        sessionId = j['session_id'] as String? ?? '',
        title = j['title'] as String? ?? '',
        brief = j['brief'] as String? ?? '',
        schedule = j['schedule'] is String ? j['schedule'] as String : '',
        scheduleText = _str(j['schedule_text']) ??
            (j['schedule'] is String ? j['schedule'] as String : ''),
        enabled = j['enabled'] as bool? ?? true,
        quietHours = WakeQuietHours.parse(j['quiet_hours']),
        utcOffsetMinutes = _int(j['utc_offset_minutes']),
        report = WakeReport.fromJson(j['report']),
        setBy = j['set_by'] as String? ?? '',
        maxRunsPerDay = _int(j['max_runs_per_day']) ?? 0,
        runsLastDay = _int(j['runs_last_day']) ?? 0,
        nextRunAt = _int(j['next_run_at']) ?? 0,
        lastRunAt = _int(j['last_run_at']),
        lastStatus = _str(j['last_status']),
        lastResult = _str(j['last_result']),
        lastError = _str(j['last_error']),
        queued = j['queued'] as bool? ?? false;

  /// The text to put back in the schedule field when editing.
  String get editableSchedule => schedule.isNotEmpty ? schedule : scheduleText;
}

class WakeLimits {
  final int minUserIntervalSecs;
  final int minAgentIntervalSecs;
  final int maxRunsPerDayUser;
  final int defaultMaxRunsPerDay;

  const WakeLimits(
      {this.minUserIntervalSecs = 900,
      this.minAgentIntervalSecs = 900,
      this.maxRunsPerDayUser = 96,
      this.defaultMaxRunsPerDay = 24});

  factory WakeLimits.fromJson(dynamic j) {
    if (j is! Map) return const WakeLimits();
    final mins = j['min_interval_secs'];
    final caps = j['max_runs_per_day'];
    return WakeLimits(
      minUserIntervalSecs: mins is Map ? _int(mins['user']) ?? 900 : 900,
      minAgentIntervalSecs: mins is Map ? _int(mins['agent']) ?? 900 : 900,
      maxRunsPerDayUser: caps is Map ? _int(caps['user']) ?? 96 : 96,
      defaultMaxRunsPerDay: _int(j['default_max_runs_per_day']) ?? 24,
    );
  }
}

class WakeList {
  final List<WakeSchedule> wakes;
  final WakeLimits limits;
  const WakeList(this.wakes, this.limits);

  factory WakeList.fromJson(Map<String, dynamic> j) => WakeList([
        for (final w in (j['wakes'] as List?) ?? const [])
          if (w is Map<String, dynamic>) WakeSchedule.fromJson(w)
      ], WakeLimits.fromJson(j['limits']));
}

class WakeRun {
  final int id;
  final String jobId;
  final String? owner;
  final String sessionId;
  final int firedAt;
  final int? finishedAt;
  final String status;
  final String? summary;
  final String? reportedTo;

  WakeRun.fromJson(Map<String, dynamic> j)
      : id = _int(j['id']) ?? 0,
        jobId = j['job_id'] as String? ?? '',
        owner = _str(j['owner']),
        sessionId = j['session_id'] as String? ?? '',
        firedAt = _int(j['fired_at']) ?? 0,
        finishedAt = _int(j['finished_at']),
        status = j['status'] as String? ?? '',
        summary = _str(j['summary']),
        reportedTo = _str(j['reported_to']);
}

class KeepWarmLimits {
  final int defaultIntervalMinutes;
  final int minIntervalMinutes;
  final int maxIntervalMinutes;
  final int defaultMaxIdleHours;
  final int maxIdleHoursCeiling;

  const KeepWarmLimits(
      {this.defaultIntervalMinutes = 4,
      this.minIntervalMinutes = 1,
      this.maxIntervalMinutes = 60,
      this.defaultMaxIdleHours = 2,
      this.maxIdleHoursCeiling = 24});

  factory KeepWarmLimits.fromJson(dynamic j) => j is! Map
      ? const KeepWarmLimits()
      : KeepWarmLimits(
          defaultIntervalMinutes: _int(j['default_interval_minutes']) ?? 4,
          minIntervalMinutes: _int(j['min_interval_minutes']) ?? 1,
          maxIntervalMinutes: _int(j['max_interval_minutes']) ?? 60,
          defaultMaxIdleHours: _int(j['default_max_idle_hours']) ?? 2,
          maxIdleHoursCeiling: _int(j['max_idle_hours_ceiling']) ?? 24,
        );
}

class KeepWarmEntry {
  final String owner;
  final String ownerKind;
  final String sessionId;
  final bool enabled;
  final int intervalMinutes;
  final int maxIdleHours;
  final String setBy;
  final int updatedAt;
  final int? lastWarmAt;
  final int? lastCacheReadTokens;
  final int? lastCacheCreationTokens;
  final String? skippedReason;
  final String? providerReason;
  final int warms;

  KeepWarmEntry.fromJson(Map<String, dynamic> j)
      : owner = j['owner'] as String? ?? '',
        ownerKind = j['owner_kind'] as String? ?? 'agent',
        sessionId = j['session_id'] as String? ?? '',
        enabled = j['enabled'] as bool? ?? false,
        intervalMinutes = _int(j['interval_minutes']) ?? 0,
        maxIdleHours = _int(j['max_idle_hours']) ?? 0,
        setBy = j['set_by'] as String? ?? '',
        updatedAt = _int(j['updated_at']) ?? 0,
        lastWarmAt = _int(j['last_warm_at']),
        lastCacheReadTokens = _int(j['last_cache_read_tokens']),
        lastCacheCreationTokens = _int(j['last_cache_creation_tokens']),
        skippedReason = _str(j['skipped_reason']),
        providerReason = _str(j['provider_reason']),
        warms = _int(j['warms']) ?? 0;

  /// The plain-language reason it is not warming, provider first.
  String? get reason => providerReason ?? skippedReason;
}

class KeepWarmList {
  final List<KeepWarmEntry> entries;
  final KeepWarmLimits limits;

  /// Warm calls in the last 7 days, summed over the ledger rows.
  final int calls7d;
  final int cacheReadTokens7d;

  const KeepWarmList(this.entries, this.limits,
      {this.calls7d = 0, this.cacheReadTokens7d = 0});

  factory KeepWarmList.fromJson(Map<String, dynamic> j) {
    var calls = 0, read = 0;
    final spend = j['spend_7d'];
    if (spend is List) {
      for (final r in spend) {
        if (r is Map) {
          calls += _int(r['calls']) ?? 0;
          read += _int(r['cache_read_tokens']) ?? 0;
        }
      }
    }
    return KeepWarmList([
      for (final e in (j['entries'] as List?) ?? const [])
        if (e is Map<String, dynamic>) KeepWarmEntry.fromJson(e)
    ], KeepWarmLimits.fromJson(j['limits']),
        calls7d: calls, cacheReadTokens7d: read);
  }
}

/// Smallest context ceiling the daemon accepts.
const kMinAgentContextTokens = 16000;

/// Turns a stored token count into "128k" style text.
String tokensLabel(int tokens) {
  if (tokens >= 1000000 && tokens % 100000 == 0) {
    return '${tokens / 1000000}M'.replaceAll('.0M', 'M');
  }
  if (tokens >= 1000) return '${(tokens / 1000).round()}k';
  return '$tokens';
}

/// Parses "128k", "200000" or "1m"; null when it is not a count.
int? parseTokens(String raw) {
  final t = raw.trim().toLowerCase().replaceAll(',', '').replaceAll('_', '');
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([km]?)$').firstMatch(t);
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  final mult = switch (m.group(2)) { 'k' => 1000, 'm' => 1000000, _ => 1 };
  return (n * mult).round();
}
