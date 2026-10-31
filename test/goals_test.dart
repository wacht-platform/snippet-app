import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/goals/goal_detail_screen.dart';
import 'package:snippet/screens/goals/goal_widgets.dart';
import 'package:snippet/screens/tasks/task_detail_screen.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Map<String, dynamic> _row(String id, String title,
        {int done = 0,
        int total = 0,
        int have = 0,
        int ev = 0,
        String? attention}) =>
    {
      'id': id,
      'title': title,
      'outcome': 'Ship it',
      'status': 'open',
      'requester': 'boss',
      'created_at': '2026-10-30T10:00:00Z',
      'closed_at': null,
      'progress': {'done': done, 'total': total},
      'evidence': {'have': have, 'total': ev},
      'attention': attention,
    };

final _detailJson = {
  ..._row('g1', 'Launch goals',
      done: 1, total: 3, have: 1, ev: 2, attention: 'stalled'),
  'acceptance': [
    {
      'criterion': 'List shows progress',
      'method': 'widget test',
      'evidence': 'test passes'
    },
    {'criterion': 'Detail shows plan', 'method': 'golden', 'evidence': null},
  ],
  'plan': [
    {
      'n': 2,
      'task_id': 't2',
      'title': 'Detail view',
      'depends_on': [1]
    },
    {'n': 1, 'task_id': 't1', 'title': 'API models', 'depends_on': []},
    {
      'n': 3,
      'task_id': 't3',
      'title': 'Wire board',
      'depends_on': [1, 2]
    },
  ],
  'tasks': [
    {
      'id': 't1',
      'slice': 1,
      'title': 'API models',
      'status': 'done',
      'agent': 'alice'
    },
    {
      'id': 't2',
      'slice': 2,
      'title': 'Detail view',
      'status': 'blocked',
      'agent': 'bob',
      'status_reason': 'awaiting_dependency',
      'waiting_on': ['t1'],
    },
  ],
  'blockers': [
    {
      'task_id': 't2',
      'title': 'Detail view',
      'status': 'blocked',
      'reason': 'Needs review',
      'waiting_on': ['t1']
    },
  ],
};

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> detail = _detailJson;
  Map<String, dynamic> taskJson = {};

  @override
  Future<List<Goal>> goals({String status = 'open'}) async =>
      rows.map(Goal.fromJson).toList();

  @override
  Future<GoalDetail> goal(String id) async => GoalDetail.fromJson(detail);

  @override
  Future<TaskItem> getTask(String id) async => TaskItem.fromJson(taskJson);

  @override
  Future<List<TaskAgent>> taskAgents(String id) async => const [];

  @override
  Future<TaskLinks> taskLinks(String id) async => const TaskLinks();

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      const [];
}

Future<void> _phone(WidgetTester tester, Widget child) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  addTearDown(() => DaemonClient.wsConnector = null);
  tester.view.physicalSize = const Size(390, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  group('parsing', () {
    test('goal row', () {
      final g = Goal.fromJson(_row('g', 'T',
          done: 2, total: 4, have: 1, ev: 3, attention: 'ready_to_close'));
      expect(g.progress.done, 2);
      expect(g.progress.fraction, 0.5);
      expect(g.evidence.done, 1);
      expect(g.evidence.total, 3);
      expect(g.attention, GoalAttention.readyToClose);
      expect(g.isOpen, isTrue);
    });

    test('tolerates missing and odd fields', () {
      final g =
          Goal.fromJson({'id': 'x', 'attention': 'unknown', 'progress': 3});
      expect(g.title, '');
      expect(g.progress.total, 0);
      expect(g.progress.fraction, 0);
      expect(g.attention, isNull);
      final d = GoalDetail.fromJson({
        'id': 'x',
        'plan': [1, null],
        'tasks': 'no'
      });
      expect(d.plan, isEmpty);
      expect(d.tasks, isEmpty);
      expect(d.blockers, isEmpty);
    });

    test('detail resolves plan order, tasks and dependencies', () {
      final d = GoalDetail.fromJson(_detailJson);
      expect(d.plan.map((s) => s.n), [1, 2, 3]);
      expect(d.acceptance[0].hasEvidence, isTrue);
      expect(d.acceptance[1].hasEvidence, isFalse);
      expect(d.taskFor(d.plan[1])!.status, 'blocked');
      expect(d.taskFor(d.plan[2]), isNull);
      expect(d.dependencyTitles(d.plan[2]), ['API models', 'Detail view']);
      expect(d.blockers.single.reason, 'Needs review');
    });

    test('task carries goal fields', () {
      final t = TaskItem.fromJson(
          {'id': 'a', 'goal_id': 'g1', 'goal_title': 'Launch goals'});
      expect(t.goalId, 'g1');
      expect(t.goalTitle, 'Launch goals');
      expect(t.movedTo(TaskStatus.done).goalTitle, 'Launch goals');
      expect(TaskItem.fromJson({'id': 'b'}).goalTitle, isNull);
    });
  });

  group('widgets', () {
    phoneTest('list shows title, progress, evidence and attention chip',
        (tester) async {
      final c = _Daemon()
        ..rows = [
          _row('g1', 'Launch goals',
              done: 1, total: 3, have: 1, ev: 2, attention: 'stalled'),
          _row('g2', 'Tidy settings',
              done: 4, total: 4, have: 2, ev: 2, attention: 'ready_to_close'),
          _row('g3', 'Quiet one', done: 0, total: 2),
        ];
      await _phone(tester,
          Scaffold(backgroundColor: AppColors.bg, body: GoalsList(client: c)));
      expect(find.text('Launch goals'), findsOneWidget);
      expect(find.text('1 of 3 slices'), findsOneWidget);
      expect(find.text('1 of 2 evidenced'), findsOneWidget);
      expect(find.text('Stalled'), findsOneWidget);
      expect(find.text('Ready to close'), findsOneWidget);
      expect(find.text('Quiet one'), findsOneWidget);
      await expectLater(find.byType(GoalsList),
          matchesGoldenFile('visual/goldens/goals_list_mobile.png'));
    });

    phoneTest('list empty state', (tester) async {
      await _phone(tester, Scaffold(body: GoalsList(client: _Daemon())));
      expect(find.text('No open goals'), findsOneWidget);
    });

    phoneTest('detail shows criteria, plan, waiting and blockers',
        (tester) async {
      final c = _Daemon();
      await _phone(tester, GoalDetailScreen(client: c, goalId: 'g1'));
      expect(find.text('Ship it'), findsOneWidget);
      expect(find.text('Stalled'), findsOneWidget);
      expect(find.text('List shows progress'), findsOneWidget);
      expect(find.text('API models'), findsWidgets);
      expect(find.textContaining('Blocked  ·  bob'), findsOneWidget);
      expect(find.text('Waiting on API models'), findsOneWidget);
      expect(find.text('After API models, Detail view'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('Needs review. Waiting on 1 task'), findsOneWidget);
      await expectLater(find.byType(GoalDetailScreen),
          matchesGoldenFile('visual/goldens/goal_detail_mobile.png'));
    });

    phoneTest('criterion expands to show method and evidence', (tester) async {
      await _phone(tester, GoalDetailScreen(client: _Daemon(), goalId: 'g1'));
      expect(
          find.textContaining('test passes', findRichText: true), findsNothing);
      await tester.tap(find.text('List shows progress'));
      await tester.pumpAndSettle();
      expect(find.textContaining('test passes', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('widget test', findRichText: true),
          findsOneWidget);
    });

    phoneTest('tapping a slice opens the task detail', (tester) async {
      final c = _Daemon()
        ..taskJson = {'id': 't1', 'title': 'API models', 'status': 'done'};
      await _phone(tester, GoalDetailScreen(client: c, goalId: 'g1'));
      await tester.tap(find.byKey(const ValueKey('slice-1')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailScreen), findsOneWidget);
    });

    phoneTest('task header shows its goal', (tester) async {
      final c = _Daemon()
        ..taskJson = {
          'id': 't1',
          'title': 'API models',
          'status': 'in_progress',
          'goal_id': 'g1',
          'goal_title': 'Launch goals',
        };
      await _phone(tester, TaskDetailScreen(client: c, taskId: 't1'));
      expect(find.textContaining('Goal: Launch goals'), findsOneWidget);
    });

    phoneTest('task header omits goal when absent', (tester) async {
      final c = _Daemon()
        ..taskJson = {'id': 't1', 'title': 'Solo', 'status': 'todo'};
      await _phone(tester, TaskDetailScreen(client: c, taskId: 't1'));
      expect(find.textContaining('Goal:'), findsNothing);
    });
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _Sink implements WebSocketSink {
  final StreamSink _sink;
  _Sink(this._sink);
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
  @override
  Future get done => _sink.done;
}
