import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/tasks/task_kanban.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'golden.dart';

/// The phone tabs and the desktop board, rendered with realistic data for
/// review.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int limit = 200}) async =>
      _tasks.map(TaskItem.fromJson).toList();

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];
}

final _now = DateTime.now().toUtc();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

final _tasks = [
  _task('1', 'Slate accent and press feedback', 'in_progress',
      'Replace the blue accent and add press states to every button.',
      priority: 1, age: const Duration(minutes: 12)),
  _task('2', 'TUI gets stuck listing sessions', 'blocked',
      'The store is reopened per directory; waiting on the store refactor.',
      age: const Duration(hours: 3)),
  _task('3', 'Add an APK review build', 'todo', 'Cut a release build for review.',
      age: const Duration(hours: 5)),
  _task('4', 'Remove legacy session sidecars', 'todo', '',
      age: const Duration(days: 1)),
  _task('5', 'Kanban board for desktop', 'todo',
      'Columns per status with drag between them.',
      priority: 2, age: const Duration(minutes: 40)),
  _task('6', 'Verify fork persistence', 'done',
      'Store-backed fork with a regression test.',
      age: const Duration(days: 2)),
  _task('7', 'Old duplicate-send report', 'cancelled', '',
      age: const Duration(days: 6)),
  _task('8', 'Migrate usage ledger', 'failed',
      'Rollup table was locked during migration.',
      age: const Duration(hours: 20)),
];

Map<String, dynamic> _task(String id, String title, String status, String desc,
        {int priority = 0, required Duration age}) =>
    {
      'id': id,
      'title': title,
      'description': desc,
      'status': status,
      'priority': priority,
      'created_at': _ago(age),
      'updated_at': _ago(age),
    };

Widget _sidebar(DaemonClient client, MobileHome home) => Sidebar(
      client: client,
      active: null,
      instances: const [],
      health: const {},
      sessions: [
        SessionInfo.fromJson({
          'id': 'mission-control',
          'title': 'Mission Control',
          'folder': 'mission-control',
          'last_active': _now.millisecondsSinceEpoch ~/ 1000,
        }),
        for (final (i, title, folder) in [
          (1, 'Fix the login redirect', 'snippet-app'),
          (2, 'Coordination review', 'snippet-service'),
          (3, 'Release notes draft', 'docs'),
        ])
          SessionInfo.fromJson({
            'id': 's$i',
            'title': title,
            'folder': folder,
            'last_active': _now.millisecondsSinceEpoch ~/ 1000 - i * 1800,
          }),
      ],
      sessionsLoading: false,
      onRefreshSessions: () {},
      selectedSessionId: null,
      onOpenSession: (_, __, ___) {},
      onNewSession: () {},
      onSelectInstance: (_) {},
      onAddInstance: () {},
      onRenameInstance: (_, __) {},
      onRemoveInstance: (_) {},
      onSessionDeleted: (_) {},
      onRefreshHealth: () {},
      topInset: false,
      onOpenMissionControl: () {},
      mobileHome: home,
      onMobileHome: (_) {},
      settingsSection: null,
      onSettingsSection: (_) {},
      agent: null,
      onAgent: (_) {},
    );

void main() {
  for (final home in [MobileHome.chats, MobileHome.tasks]) {
    testWidgets('phone ${home.name} tab', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(390, 844) * 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: SafeArea(child: _sidebar(_FakeDaemon(), home)),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/redesign_phone_${home.name}.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('desktop task board', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(1440, 720) * 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(body: TaskKanban(client: _FakeDaemon())),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await expectGolden(
          tester, find.byType(MaterialApp), 'goldens/redesign_board.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
