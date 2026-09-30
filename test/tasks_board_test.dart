import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/tasks/task_kanban.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/store.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon(this.items) : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  List<Map<String, dynamic>> items;
  final moves = <String, TaskStatus>{};
  bool refuse = false;

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int limit = 200}) async =>
      items.map(TaskItem.fromJson).toList();

  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async {
    if (refuse) throw Exception('refused');
    moves[id] = status;
    final row = items.firstWhere((t) => t['id'] == id);
    row['status'] = status.wire;
    return TaskItem.fromJson(row);
  }
}

Map<String, dynamic> _task(String id, String title, String status) =>
    {'id': id, 'title': title, 'status': status, 'priority': 0};

Future<void> _pumpBoard(WidgetTester tester, _FakeDaemon client) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1900, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: TaskKanban(client: client)),
  ));
  await tester.pumpAndSettle();
}

Offset _columnCenter(WidgetTester tester, String label) {
  final header = tester.getCenter(find.text(label).first);
  return Offset(header.dx + 40, header.dy + 120);
}

Future<void> _drag(WidgetTester tester, String card, String column) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(card)));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(_columnCenter(tester, column));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dragging a card to another column moves the task',
      (tester) async {
    final client = _FakeDaemon([
      _task('1', 'Write the docs', 'todo'),
      _task('2', 'Ship it', 'in_progress'),
    ]);
    await _pumpBoard(tester, client);

    for (final s in TaskStatus.values) {
      expect(find.text(s.label), findsWidgets);
    }
    expect(find.text('1 open'), findsNothing);
    expect(find.text('2 open'), findsOneWidget);

    await _drag(tester, 'Write the docs', 'Blocked');
    expect(client.moves['1'], TaskStatus.blocked);
  });

  testWidgets('In progress takes no drops: only a dispatch starts work',
      (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')]);
    await _pumpBoard(tester, client);

    await _drag(tester, 'Write the docs', 'In progress');
    expect(client.moves, isEmpty);
  });

  testWidgets('a move the daemon refuses is put back', (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')])
      ..refuse = true;
    await _pumpBoard(tester, client);

    await _drag(tester, 'Write the docs', 'Done');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final todo = tester.getCenter(find.text('To do').first).dx;
    expect((tester.getCenter(find.text('Write the docs')).dx - todo).abs(),
        lessThan(200),
        reason: 'the card must return to its column after a refusal');
  });

  testWidgets('finished columns fold away yet still take drops',
      (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')]);
    await _pumpBoard(tester, client);

    expect(find.byTooltip('Show Cancelled'), findsOneWidget);
    final strip = tester.getCenter(find.byTooltip('Show Cancelled'));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Write the docs')));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(strip);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(client.moves['1'], TaskStatus.cancelled);

    await tester.tap(find.byTooltip('Show Cancelled'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fold Cancelled'), findsOneWidget);
    expect(find.text('Write the docs'), findsOneWidget);
  });

  testWidgets('folded columns are remembered', (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')]);
    await _pumpBoard(tester, client);
    await tester.tap(find.byTooltip('Fold Done'));
    await tester.pumpAndSettle();

    // A fresh board reads the choice back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: TaskKanban(client: client)),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Done'), findsOneWidget);
    expect(find.byTooltip('Show Cancelled'), findsOneWidget);
  });

  testWidgets('the search narrows the tasks panel', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final client = _FakeDaemon([
        _task('1', 'Write the docs', 'todo'),
        _task('2', 'Fix the login bug', 'blocked'),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: TasksPanel(client: client)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Write the docs'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'login');
      await tester.pumpAndSettle();
      expect(find.text('Fix the login bug'), findsOneWidget);
      expect(find.text('Write the docs'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('No matching tasks'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop Tasks has list controls but no board entry',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final client = _FakeDaemon([_task('1', 'Desktop task', 'todo')]);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: TasksPanel(client: client)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('TASKS'), findsOneWidget);
      expect(find.text('Desktop task'), findsOneWidget);
      expect(find.byTooltip('Search tasks'), findsOneWidget);
      expect(find.byTooltip('New task'), findsOneWidget);
      expect(find.byTooltip('Open board'), findsNothing);
      expect(find.byType(TaskKanban), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('desktop shell has no board command or creation callback', () {
    final shell = File('lib/screens/desktop_shell.dart').readAsStringSync();
    final tabs = File('lib/screens/desktop_shell_tabs.dart').readAsStringSync();
    final sidebar = File('lib/screens/shell_sidebar_host.dart').readAsStringSync();
    expect(shell, isNot(contains('Open Task Board')));
    expect(shell, isNot(contains("'kanban'")));
    expect(shell, isNot(contains('_openBoardTab')));
    expect(tabs, isNot(contains('_openBoardTab')));
    expect(sidebar, isNot(contains('onOpenBoard')));
    final panes = File('lib/screens/desktop_shell_panes.dart').readAsStringSync();
    expect(panes, contains('''return kMobile
          ? TaskKanban(key: ValueKey('body-\${t.key}'), client: t.client)
          : TasksPanel(key: ValueKey('body-\${t.key}'), client: t.client);'''));
    expect(tabs, contains('shouldRestoreShellTab(descriptor, mobile: kMobile)'));
  });

  test('legacy board restore is omitted on desktop and retained on mobile', () {
    final legacy = OpenTabDescriptor.fromJson({
      'instanceUrl': 'http://m', 'title': 'Tasks', 'board': true,
      'pane': 'right', 'groupSessionKey': 'http://m|session',
    });
    expect(shouldRestoreShellTab(legacy, mobile: false), isFalse);
    expect(shouldRestoreShellTab(legacy, mobile: true), isTrue);
    final session = OpenTabDescriptor(
      instanceUrl: 'http://m', title: 'Chat', sessionId: 'session',
    );
    expect(shouldRestoreShellTab(session, mobile: false), isTrue);
  });

  test('legacy board descriptor remains readable for mobile restore', () {
    final client = _FakeDaemon(const []);
    final tab = ShellTab.board(client: client, instanceUrl: 'http://m');
    expect(tab.key, 'http://m|tasks-board');
    expect(tab.isMissionControl, isFalse);
    expect(tabIconKind(tab), 'kanban');

    final saved = OpenTabDescriptor(
        instanceUrl: 'http://m', title: tab.title, board: true);
    expect(OpenTabDescriptor.fromJson(saved.toJson()).board, isTrue);
  });
}
