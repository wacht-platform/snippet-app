import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/task_board_screen.dart';

/// The Tasks board's filter + refresh behaviour.
///
/// `flutter analyze` and a green build cannot see either defect these cover: a
/// background tick that flips `loading` would blank the list on a real device,
/// and a `Set`-based filter that no longer narrows would still compile.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  List<Map<String, dynamic>> items = [];
  bool fail = false;
  int calls = 0;

  @override
  Future<List<TaskItem>> tasks(
      {String? status, String? agentId, int limit = 200}) async {
    calls++;
    if (fail) throw Exception('network down');
    return items.map((e) => TaskItem.fromJson(e)).toList();
  }
}

Map<String, dynamic> _task(String id, String title, String status) => {
      'id': id,
      'title': title,
      'status': status,
      'priority': 0,
    };

Future<void> _pump(WidgetTester tester, _FakeDaemon client) async {
  await tester.pumpWidget(MaterialApp(home: TaskBoardScreen(client: client)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a background tick updates silently — no spinner, no error state',
      (tester) async {
    final client = _FakeDaemon()
      ..items = [_task('1', 'First task', 'todo')];
    await _pump(tester, client);
    expect(find.text('First task'), findsOneWidget);

    // A new task lands between ticks. The silent path must show it WITHOUT
    // flipping `loading` (which would blank the list for a frame).
    client.items = [
      _task('1', 'First task', 'todo'),
      _task('2', 'Second task', 'done'),
    ];
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(find.text('Second task'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a background tick must not set the loading state');

    // Now the daemon refuses the poll. The visible board must survive: a
    // transient failure is not allowed to replace the page with an error.
    client.fail = true;
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(find.text('First task'), findsOneWidget);
    expect(find.text('Second task'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('network down'), findsNothing,
        reason: 'the timer path must not surface transient errors');

    // Unmount so the periodic timer is cancelled in dispose().
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the filter panel selection narrows the visible list',
      (tester) async {
    final client = _FakeDaemon()
      ..items = [
        _task('1', 'Todo thing', 'todo'),
        _task('2', 'Blocked thing', 'blocked'),
      ];
    await _pump(tester, client);
    expect(find.text('Todo thing'), findsOneWidget);
    expect(find.text('Blocked thing'), findsOneWidget);

    // The old chip row is gone; one icon in the bar opens the panel.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    // Selection is multi — pick only Blocked and apply.
    await tester.tap(find.text('Blocked'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked thing'), findsOneWidget);
    expect(find.text('Todo thing'), findsNothing,
        reason: 'a single selected status must hide the other columns');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('no refresh icon remains in the bar', (tester) async {
    final client = _FakeDaemon()..items = [_task('1', 'A task', 'todo')];
    await _pump(tester, client);

    expect(find.byTooltip('Refresh'), findsNothing,
        reason: 'the refresh icon was removed; pull-to-refresh replaces it');
    // Pull-to-refresh is still wired as a gesture.
    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
