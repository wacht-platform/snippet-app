import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/wake_models.dart';

import 'support/wake_fakes.dart';

void main() {
  test('wake schedule view parses every field', () {
    final w = WakeSchedule.fromJson(wakeJson());
    expect(w.owner, 'scout');
    expect(w.scheduleText, 'Weekdays at 09:00');
    expect(w.editableSchedule, 'weekdays 09:00');
    expect(w.quietHours?.label, '22:00 to 07:00');
    expect(w.report.to, 'mission_control');
    expect(w.report.onlyOnChange, isTrue);
    expect(w.maxRunsPerDay, 24);
    expect(w.lastStatus, 'ok');
    expect(w.lastError, isNull);
    expect(w.utcOffsetMinutes, 60);
  });

  test('a sparse wake view falls back to defaults', () {
    final w = WakeSchedule.fromJson({'owner': 'x', 'quiet_hours': null});
    expect(w.quietHours, isNull);
    expect(w.report.to, 'mission_control');
    expect(w.enabled, isTrue);
    expect(w.nextRunAt, 0);
    expect(w.lastRunAt, isNull);
  });

  test('wake list reads limits and tolerates junk', () {
    final l = WakeList.fromJson({
      'wakes': [wakeJson(), 'junk'],
      'limits': {
        'min_interval_secs': {'user': 900, 'agent': 1800},
        'default_max_runs_per_day': 12,
        'max_runs_per_day': {'user': 96, 'agent': 12},
      },
    });
    expect(l.wakes, hasLength(1));
    expect(l.limits.minAgentIntervalSecs, 1800);
    expect(l.limits.maxRunsPerDayUser, 96);
    expect(l.limits.defaultMaxRunsPerDay, 12);
  });

  test('keep-warm list sums the seven day spend and keeps reasons', () {
    final l = KeepWarmList.fromJson({
      'entries': [
        keepWarmJson(
            skipped: 'session is not open',
            provider: 'This provider does not support caching'),
      ],
      'limits': {'min_interval_minutes': 2, 'max_interval_minutes': 30},
      'spend_7d': [
        {'calls': 3, 'cache_read_tokens': 1000},
        {'calls': 2, 'cache_read_tokens': 500},
      ],
    });
    expect(l.entries.single.reason, 'This provider does not support caching');
    expect(l.entries.single.skippedReason, 'session is not open');
    expect(l.limits.minIntervalMinutes, 2);
    expect(l.limits.maxIntervalMinutes, 30);
    expect(l.calls7d, 5);
    expect(l.cacheReadTokens7d, 1500);
  });

  test('token text round trips', () {
    expect(parseTokens('128k'), 128000);
    expect(parseTokens('200,000'), 200000);
    expect(parseTokens('1.5m'), 1500000);
    expect(parseTokens('lots'), isNull);
    expect(tokensLabel(128000), '128k');
    expect(tokensLabel(1000000), '1M');
  });

  test('agent reads max_context_tokens, zero and null mean unset', () {
    expect(
        CoordinationAgent.fromJson({'id': 'a', 'max_context_tokens': 64000})
            .maxContextTokens,
        64000);
    expect(
        CoordinationAgent.fromJson({'id': 'a', 'max_context_tokens': 0})
            .maxContextTokens,
        isNull);
    expect(CoordinationAgent.fromJson({'id': 'a'}).maxContextTokens, isNull);
  });

  test('recurring parser tolerates weekly schedules', () {
    RecurringJob job(Map<String, dynamic> schedule) => RecurringJob.fromJson(
        {'id': 'j', 'schedule': schedule, 'session_id': 's'});
    expect(
        job({'kind': 'weekly', 'days': 0x1F, 'hour': 9, 'minute': 0})
            .scheduleLabel,
        'weekdays 09:00');
    final w = job({'kind': 'weekly', 'days': 0x09, 'hour': 18, 'minute': 5});
    expect(w.scheduleKind, 'weekly');
    expect(w.scheduleLabel, 'mon,thu 18:05');
    expect(job({'kind': 'weekly'}).scheduleLabel, 'weekly 00:00');
    expect(job({'kind': 'mystery'}).scheduleLabel, 'mystery');
  });

  group('client', () {
    late HttpServer server;
    late DaemonClient client;
    final seen = <String>[];
    final bodies = <String>[];

    setUp(() async {
      HttpOverrides.global = null;
      seen.clear();
      bodies.clear();
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        seen.add('${req.method} ${req.uri.path}?${req.uri.query}');
        bodies.add(await utf8.decoder.bind(req).join());
        final p = req.uri.path;
        Object body = {};
        var status = 200;
        if (p == '/wakes') {
          body = {'wakes': [wakeJson()], 'limits': {}};
        } else if (p == '/wake-runs') {
          body = {
            'runs': [
              {'id': 1, 'status': 'ok', 'fired_at': 5}
            ]
          };
        } else if (p == '/wakes/ghost') {
          status = 404;
        } else if (p.startsWith('/wakes/')) {
          body = wakeJson();
        } else if (p == '/keep-warm') {
          body = {'entries': [keepWarmJson()], 'limits': {}, 'spend_7d': []};
        } else if (p.startsWith('/keep-warm/')) {
          body = keepWarmJson();
        } else if (p.endsWith('/context')) {
          body = {'id': 'scout', 'max_context_tokens': null};
        }
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      client = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
    });

    tearDown(() => server.close(force: true));

    test('wake calls use the documented routes and bodies', () async {
      expect((await client.wakes()).wakes.single.owner, 'scout');
      expect(await client.wake('ghost'), isNull);
      await client.setWake('scout', {'schedule': 'daily 09:00'});
      await client.clearWake('scout');
      final runs = await client.wakeRuns(owner: 'scout', limit: 5);
      expect(runs.single.status, 'ok');
      expect(seen, contains('GET /wakes?token=tok'));
      expect(seen, contains('PUT /wakes/scout?token=tok'));
      expect(seen, contains('DELETE /wakes/scout?token=tok'));
      expect(seen, contains('GET /wake-runs?token=tok&owner=scout&limit=5'));
      expect(jsonDecode(bodies[seen.indexOf('PUT /wakes/scout?token=tok')]),
          {'schedule': 'daily 09:00'});
    });

    test('keep-warm and context calls', () async {
      expect((await client.keepWarm()).entries, hasLength(1));
      await client.setKeepWarm('scout', enabled: true, intervalMinutes: 5);
      await client.setAgentContext('scout', 0);
      await client.setAgentContext('scout', 128000);
      final put = seen.indexOf('PUT /keep-warm/scout?token=tok');
      expect(jsonDecode(bodies[put]),
          {'enabled': true, 'interval_minutes': 5});
      final ctx = [
        for (var i = 0; i < seen.length; i++)
          if (seen[i].startsWith('POST /agents/scout/context')) bodies[i]
      ];
      expect(jsonDecode(ctx[0]), {'max_context_tokens': null});
      expect(jsonDecode(ctx[1]), {'max_context_tokens': 128000});
    });
  });
}
