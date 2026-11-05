import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';

Map<String, dynamic> _input(String text) => {'kind': 'user_input', 'text': text};
Map<String, dynamic> _reply(String text) => {'kind': 'assistant_text', 'text': text};
Map<String, dynamic> _wake(String time, {String extra = ''}) =>
    _input('[automated_wake]\ntime: Thu 05 Nov $time (UTC+05:30)\nlast wake: 1h ago\n$extra');

String _report(String status, String summary, {String id = 'task-1'}) =>
    '[mission_task_report]\ntask_id: $id\ntitle: Quarry post\nstatus: $status\n'
    'summary: $summary\n[/mission_task_report]\nWorkflow W3 instructions.';

void main() {
  group('quietWakeRuns', () {
    test('folds adjacent quiet wakes, including a rescheduled look', () {
      final runs = quietWakeRuns([
        _wake('09:58'),
        _reply('Nothing new, boss.'),
        _wake('10:58'),
        {'kind': 'tool_call', 'tool_name': 'schedule_wake'},
        {'kind': 'tool_result', 'tool_name': 'schedule_wake'},
        _reply('Still quiet, boss. Nothing needs you.'),
        {'kind': 'turn_changes'},
      ]);
      expect(runs.keys, [0]);
      expect(runs[0]!.end, 6);
      expect(runs[0]!.wakes.map((w) => w.time), ['Thu 09:58', 'Thu 10:58']);
    });

    test('never folds a wake that carries news or did work', () {
      final apify = 'One thing worth noting, boss: the sync hit an Apify 403.';
      final runs = quietWakeRuns([
        _wake('09:58'),
        _reply('Nothing new, boss.'),
        _wake('10:58'),
        _reply(apify),
        _wake('11:58'),
        _reply('Nothing new except one thing is stuck, boss.'),
        _wake('12:58'),
        {'kind': 'tool_call', 'tool_name': 'deliver_to_session'},
        _reply('Nothing new, boss.'),
        _wake('13:58', extra: '## Wake-ups due now\n- check the sync\n'),
        _reply('Nothing new, boss.'),
        _wake('14:58'),
      ]);
      expect(runs.keys, [0]);
      expect(runs[0]!.end, 1);
    });

    test('a user message splits a run', () {
      final runs = quietWakeRuns([
        _wake('09:58'),
        _reply('Nothing new.'),
        _input('status?'),
        _reply('All quiet.'),
        _wake('10:58'),
        _reply('Nothing new.'),
      ]);
      expect(runs.keys, [0, 4]);
    });
  });

  group('report summaries', () {
    test('keep every line and stop before the artifacts block', () {
      final e = parseMissionEnvelope(
          '[mission_task_report]\ntask_id: t\ntitle: T\nstatus: done\n'
          'summary: First line.\n\nSecond line.\nartifacts:\n- a.png\n[/mission_task_report]')!;
      expect(e.summary, 'First line.\n\nSecond line.');
    });

    test('an idle stall reads plainly and keeps the last message', () {
      final e = parseMissionEnvelope(_report('stalled',
          'stalled 18 min: no progress since 2026-11-02T14:00:48.182818546+00:00; '
          'its session went idle without reporting; its last message was:\n'
          'The shim is hung.\nIf that asks for something, answer_worker (session_id x) '
          'if you can settle it, otherwise ask the user; if it just stopped, retry_mission_task.'))!;
      expect(e.summary,
          'No progress for 18 min. Its session went idle without reporting.\n\n'
          'Its last message:\n\nThe shim is hung.');
    });

    test('a waiting stall drops the instructions meant for Mission Control', () {
      final e = parseMissionEnvelope(_report('stalled',
          'stalled 20 min: no progress since 2026-11-04T04:52:56+00:00; its session is '
          'waiting_for_input; check it with inspect_session, then retry_mission_task, answer it or cancel.'))!;
      expect(e.summary, 'No progress for 20 min. Its session is waiting for input.');
    });
  });

  test('only stalls overtaken by a later report on the same task go stale', () {
    final stale = supersededStalls([
      _input(_report('stalled', 'a')),
      _input(_report('stalled', 'b', id: 'other')),
      _input(_report('stalled', 'c')),
      _input(_report('done', 'd')),
    ]);
    expect(stale, {0, 2});
  });

  testWidgets('the quiet row summarises and opens to the replies', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: QuietWakesRow(
          run: QuietWakeRun(end: 3, wakes: [
            QuietWake(time: 'Thu 09:58', reply: 'Nothing new, boss.'),
            QuietWake(time: 'Thu 18:58', reply: 'Still quiet.'),
          ]),
        ),
      ),
    ));
    expect(find.text('2 quiet wakes'), findsOneWidget);
    expect(find.text('Thu 09:58 to 18:58'), findsOneWidget);
    expect(find.text('Still quiet.'), findsNothing);
    await tester.tap(find.text('2 quiet wakes'));
    await tester.pump();
    expect(find.text('Still quiet.'), findsOneWidget);
  });
}
