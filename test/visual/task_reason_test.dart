import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_common.dart';
import 'package:snippet/screens/tasks/task_list.dart';
import 'package:snippet/task_reason.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

Map<String, dynamic> _t(String id, String title, String status,
        [Map<String, dynamic> extra = const {}]) =>
    {'id': id, 'title': title, 'status': status, ...extra};

final _all = [
  _t('a', 'Ship the migration', 'todo',
      {'status_reason': 'awaiting_dependency(b)', 'waiting_on': ['b']}),
  _t('b', 'Write the schema', 'in_progress',
      {'status_reason': null, 'current_step': 'Running the tests'}),
  _t('c', 'Old plan', 'cancelled', {'superseded_by': 'b'}),
  _t('d', 'Review copy', 'in_review'),
  _t('e', 'Quiet', 'todo', {'status_reason': 'stalled'}),
  _t('f', 'Legacy', 'todo'),
].map(TaskItem.fromJson).toList();

void main() {
  test('parses additive fields and tolerates absence', () {
    expect(_all[0].waitingOn, ['b']);
    expect(_all[0].statusReason, 'awaiting_dependency(b)');
    expect(_all[1].currentStep, 'Running the tests');
    expect(_all[1].statusReason, isNull);
    expect(_all[2].supersededBy, 'b');
    expect(_all[5].waitingOn, isEmpty);
    expect(_all[5].statusReason, isNull);
    final mc = MissionControlTask.fromJson(
        {'id': 'x', 'status': 'blocked', 'status_reason': 'offered'});
    expect(mc.statusReason, 'offered');
    expect(mc.waitingOn, isEmpty);
  });

  test('in_review parses, labels and sorts between progress and done', () {
    expect(TaskStatus.parse('in_review'), TaskStatus.inReview);
    expect(TaskStatus.inReview.label, 'In review');
    final v = TaskStatus.values;
    expect(v.indexOf(TaskStatus.inReview), greaterThan(v.indexOf(TaskStatus.inProgress)));
    expect(v.indexOf(TaskStatus.inReview), lessThan(v.indexOf(TaskStatus.done)));
  });

  test('notes read plainly', () {
    expect(noteForTask(_all[0], _all).reason, 'Waiting on Write the schema');
    expect(noteForTask(_all[1], _all).step, 'Running the tests');
    expect(noteForTask(_all[2], _all).replacedBy, 'Replaced by Write the schema');
    expect(noteForTask(_all[4], _all).reason, 'Stalled, no recent activity');
    expect(noteForTask(_all[5], _all).isEmpty, isTrue);
    expect(noteForTask(_all[0], const []).reason, 'Waiting on another task');
  });

  Widget host(double w) => MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(w, 700)),
          child: Scaffold(
            backgroundColor: AppColors.bg,
            body: RepaintBoundary(
              key: const ValueKey('shot'),
              child: ColoredBox(
                color: AppColors.bg,
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  for (final t in _all)
                    TaskRow(
                        task: t, note: noteForTask(t, _all), onTap: () {}),
                ]),
              ),
            ),
          ),
        ),
      );

  for (final w in [390.0, 1000.0]) {
    testWidgets('reason rendering at ${w.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(w, 700);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(w));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Waiting on Write the schema'), findsOneWidget);
      expect(find.text('Running the tests'), findsOneWidget);
      expect(find.text('Replaced by Write the schema'), findsOneWidget);
      expect(find.text('Stalled, no recent activity'), findsOneWidget);
      await expectGolden(tester, find.byKey(const ValueKey('shot')),
          'goldens/task_reasons_${w.toInt()}.png');
    });
  }
}
