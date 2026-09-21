import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/mission_control/widgets/activity_feed.dart';
import 'package:snippet/screens/mission_control/widgets/mission_composer.dart';
import 'package:snippet/screens/mission_control/widgets/mission_control_header.dart';
import 'package:snippet/screens/mission_control/widgets/notification_inbox.dart';
import 'package:snippet/screens/mission_control/widgets/task_detail_sheet.dart';
import 'package:snippet/screens/mission_control/widgets/task_inspector.dart';
import 'package:snippet/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'golden.dart';

/// Mission Control's own widgets, rendered with real content.
///
/// These take a `MissionControlState` rather than a client, so the harness
/// builds the state directly and fills its public fields. Nothing calls
/// `start()`, so the poll timer and the socket are never armed — the state is
/// pure data here and there is no timer to outlive the test.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon(this._tasks) : super('https://daemon.invalid', 'test-token');

  final List<Map<String, dynamic>> _tasks;

  @override
  Future<MissionControlOverview> mcOverview() async =>
      MissionControlOverview.fromJson(const {});

  @override
  Future<List<MissionControlTask>> mcTasks({bool? archived}) async =>
      _tasks.map(MissionControlTask.fromJson).toList();

  @override
  Future<List<ManagedSession>> mcSessions({bool? archived}) async =>
      const [];

  /// Mission Control watches two sockets: its own, and the shell stream. A fake
  /// has no server, so throwing is the honest stand-in — each caller's own
  /// `try`/`catch` handles it, which is the path a device with a dead daemon
  /// takes too. Neither is armed here, but stub them so an accidental
  /// `start()` cannot open a real connection.
  @override
  WebSocketChannel events() => throw UnimplementedError('no live events');

  @override
  WebSocketChannel attach(String sessionId) =>
      throw UnimplementedError('no live socket');
}

Map<String, dynamic> _task(String id, String title, String status,
        {String description = '',
        bool archived = false,
        List<Map<String, dynamic>> notifications = const []}) =>
    {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'created_at': 1757000000,
      'updated_at': 1757003600,
      'archived': archived,
      'notifications': notifications,
    };

Map<String, dynamic> _note(String kind, String message) => {
      'target': 'mission-control',
      'kind': kind,
      'message': message,
      'delivered': false,
    };

/// A state loaded through the REAL path.
///
/// `_feed` is private and only `_reconcileFeed()` fills it, deriving task events
/// from `tasks`. Assigning `tasks` directly leaves the feed empty and the feed
/// is unmodifiable from outside, so the fake serves them and `refresh()` builds
/// both.
Future<MissionControlState> _state(List<Map<String, dynamic>> tasks) async {
  final s = MissionControlState(client: _FakeDaemon(tasks));
  await s.refresh();
  s.agent = const AgentSnapshot(
    state: AgentState.working,
    detail: 'Reviewing the task board',
    activeCount: 3,
    blockedCount: 1,
    unreadNotifications: 2,
  );
  return s;
}

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
    );

/// A panel needs a `Material` ancestor for its InkWells, and LOOSE width
/// constraints — under a Navigator they are tight, so a bare `SizedBox` would be
/// forced full-screen.
Widget _panel(Widget child, {double width = 390, double height = 700}) =>
    Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    );

Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    void sized(WidgetTester tester) {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(430, 860) * 2.0;
      addTearDown(tester.view.reset);
    }

    final tasks = [
      _task('t1', 'Normalise the type scale', 'in_progress',
          description: '255 literals onto the nine-step ladder.'),
      _task('t2', 'Migrate legacy sidecars', 'blocked',
          description: 'The session it targets no longer exists.',
          notifications: [_note('blocked', 'Waiting on the sidecar lock.')]),
      _task('t3', 'Add the review APK', 'done',
          notifications: [_note('failed', 'Upload timed out once.')]),
      _task('t4', 'Old duplicate-send report', 'cancelled', archived: true),
    ];

    // --- The header: agent state, counts, and the MC controls.
    testWidgets('mc header ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(
            _app(_panel(MissionControlHeader.full(state: (await _state(tasks))), height: 200)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_header_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- The activity feed: task events and user messages interleaved.
    testWidgets('mc activity feed ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final state = (await _state(tasks));

        await tester.pumpWidget(_app(_panel(ActivityFeed(
          state: state,
          onTapTask: (_) {},
          onTapQuestion: (_) {},
        ))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_activity_feed_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- The notification inbox: unresolved markers, by kind.
    testWidgets('mc notification inbox ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(
            _app(_panel(NotificationInbox(state: (await _state(tasks))))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_notification_inbox_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- The composer: the one input MC is driven from.
    testWidgets('mc composer ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(
            _app(_panel(MissionComposer(state: (await _state(tasks))), height: 220)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_composer_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Task detail sheet and inspector: one task, opened.
    testWidgets('mc task detail sheet ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(_app(_panel(TaskDetailSheet(
          task: MissionControlTask.fromJson(tasks[1]),
          state: (await _state(tasks)),
        ))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_task_detail_sheet_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('mc task inspector ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(_app(_panel(TaskInspector(
          task: MissionControlTask.fromJson(tasks[1]),
          state: (await _state(tasks)),
        ))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mc_task_inspector_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
