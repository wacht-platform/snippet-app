import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/wake_models.dart';

final _frozen = DateTime(2026, 10, 31, 10);
final nowSecs = _frozen.millisecondsSinceEpoch ~/ 1000;

void freezeWakeClock() {
  wakeClock = () => _frozen;
  addTearDown(() => wakeClock = DateTime.now);
}

Map<String, dynamic> wakeJson({
  String owner = 'scout',
  bool enabled = true,
  String? lastError,
}) =>
    {
      'owner': owner,
      'owner_kind': 'agent',
      'job_id': 'wake-$owner',
      'session_id': 'inbox-$owner',
      'title': 'Wake Scout',
      'brief': 'Check the revenue pipeline and flag anything stalled.',
      'schedule': 'weekdays 09:00',
      'schedule_text': 'Weekdays at 09:00',
      'enabled': enabled,
      'quiet_hours': {'start': '22:00', 'end': '07:00'},
      'utc_offset_minutes': 60,
      'report': {
        'to': 'mission_control',
        'task_id': null,
        'only_on_change': true
      },
      'set_by': 'user',
      'max_runs_per_day': 24,
      'runs_last_day': 1,
      'next_run_at': nowSecs + 5400,
      'last_run_at': nowSecs - 7200,
      'last_status': lastError == null ? 'ok' : 'failed',
      'last_result': 'Two deals stalled; nothing else changed.',
      'last_error': lastError,
      'queued': false,
      'created_at': nowSecs - 86400,
      'updated_at': nowSecs - 3600,
    };

Map<String, dynamic> keepWarmJson({
  bool enabled = true,
  String? skipped,
  String? provider,
}) =>
    {
      'owner': 'scout',
      'owner_kind': 'agent',
      'session_id': 'inbox-scout',
      'enabled': enabled,
      'interval_minutes': 4,
      'max_idle_hours': 2,
      'set_by': 'user',
      'updated_at': nowSecs,
      'last_warm_at': null,
      'last_cache_read_tokens': null,
      'last_cache_creation_tokens': null,
      'skipped_reason': skipped,
      'provider_reason': provider,
      'warms': 0,
    };

List<WakeRun> sampleRuns() => [
      WakeRun.fromJson({
        'id': 12,
        'job_id': 'wake-scout',
        'owner': 'scout',
        'session_id': 'inbox-scout',
        'fired_at': nowSecs - 7200,
        'finished_at': nowSecs - 7100,
        'status': 'ok',
        'summary': 'Two deals stalled',
        'reported_to': 'mission_control',
      }),
      WakeRun.fromJson({
        'id': 11,
        'job_id': 'wake-scout',
        'owner': 'scout',
        'session_id': 'inbox-scout',
        'fired_at': nowSecs - 93600,
        'status': 'failed',
        'summary': 'Session was busy',
      }),
    ];

class FakeWakeClient extends DaemonClient {
  FakeWakeClient({
    this.wakeState,
    this.warmState,
    this.runs,
  }) : super('https://daemon.invalid', 'test');

  WakeSchedule? wakeState;
  KeepWarmEntry? warmState;
  List<WakeRun>? runs;
  final puts = <Map<String, dynamic>>[];
  final warmPuts = <Map<String, dynamic>>[];
  final contexts = <int?>[];
  bool cleared = false;

  @override
  Future<WakeSchedule?> wake(String owner) async => wakeState;

  @override
  Future<WakeList> wakes() async =>
      WakeList([if (wakeState != null) wakeState!], const WakeLimits());

  @override
  Future<List<WakeRun>> wakeRuns({String? owner, int limit = 10}) async =>
      runs ?? const [];

  @override
  Future<KeepWarmEntry?> keepWarmFor(String owner) async => warmState;

  @override
  Future<KeepWarmList> keepWarm() async =>
      KeepWarmList([if (warmState != null) warmState!], const KeepWarmLimits(),
          calls7d: 0);

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'scout', 'display_name': 'Revenue Scout'}),
      ];

  @override
  Future<WakeSchedule> setWake(String owner, Map<String, dynamic> body) async {
    puts.add(body);
    final merged = wakeJson(owner: owner);
    if (body['schedule'] is String) merged['schedule'] = body['schedule'];
    if (body['schedule'] is String) merged['schedule_text'] = body['schedule'];
    if (body['enabled'] is bool) merged['enabled'] = body['enabled'];
    return wakeState = WakeSchedule.fromJson(merged);
  }

  @override
  Future<void> clearWake(String owner) async {
    cleared = true;
    wakeState = null;
  }

  @override
  Future<KeepWarmEntry> setKeepWarm(String owner,
      {required bool enabled, int? intervalMinutes, int? maxIdleHours}) async {
    warmPuts.add({
      'enabled': enabled,
      'interval_minutes': intervalMinutes,
      'max_idle_hours': maxIdleHours,
    });
    return warmState = KeepWarmEntry.fromJson(keepWarmJson(enabled: enabled));
  }

  @override
  Future<void> setAgentContext(String agentId, int? tokens) async {
    contexts.add(tokens);
  }
}
