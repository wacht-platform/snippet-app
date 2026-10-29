import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/transcript.dart';

LaneInfo lane(String status, {String? activity, String? kind, List<LaneActivity> log = const [], String? summary}) => LaneInfo(
      id: 'l1',
      title: 'Audit server barge-in path',
      status: status,
      startedAt: DateTime.now().toUtc().subtract(const Duration(seconds: 141)).toIso8601String(),
      activity: activity,
      activityKind: kind,
      activityLog: log,
      summary: summary,
    );

Future<void> pump(WidgetTester t, LaneInfo l) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SizedBox(
              width: 360,
              child: LaneNotice(title: l.title, live: () => l, onOpen: () {})))));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('running lane shows thinking plus last action', (t) async {
    await pump(t, lane('running', activity: 'Thinking', kind: 'model', log: const [
      LaneActivity(at: '', kind: 'tool_call', text: 'Read listener.rs turn handling'),
      LaneActivity(at: '', kind: 'model', text: 'Thinking'),
    ]));
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.textContaining('Read listener.rs'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('completed lane renders markdown summary', (t) async {
    await pump(t, lane('completed', summary: '## Client audit\n\nRead-only; **no files changed**.'));
    expect(find.textContaining('##'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
