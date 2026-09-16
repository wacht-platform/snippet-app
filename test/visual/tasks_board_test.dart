import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/task_board_screen.dart';
import 'package:snippet/theme.dart';
import 'golden.dart';

/// The Tasks board as it actually renders, with real rows.
///
/// Same fake-client shape the behaviour tests use, so the golden shows the
/// composed screen rather than a hand-built approximation. Screen-level review
/// is where density and hierarchy problems show: five rows stacked as cards read
/// very differently from five rows in a list, and only the full screen reveals
/// which one you are looking at.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');
  List<Map<String, dynamic>> items = [];

  @override
  Future<List<TaskItem>> tasks(
      {String? status, String? agentId, int limit = 200}) async {
    return items.map((e) => TaskItem.fromJson(e)).toList();
  }
}

Map<String, dynamic> _task(String id, String title, String status,
        {int priority = 0, String description = '', String by = 'human'}) =>
    {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'created_by_kind': by,
      'created_by_id': by == 'human' ? 'you' : 'snippet',
      'created_at': '2026-09-15T10:00:00Z',
      'updated_at': '2026-09-15T11:30:00Z',
    };

void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    testWidgets('tasks board ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..items = [
            _task('1', 'Slate accent and press feedback', 'in_progress',
                priority: 1,
                description: 'Replace the blue accent and add press states.'),
            _task('2', 'TUI gets stuck listing sessions', 'blocked',
                description: 'Store is reopened per directory.'),
            _task('3', 'Add APK review build', 'todo',
                by: 'agent', description: 'Cut a release for review.'),
            _task('4', 'Remove legacy session sidecars', 'todo'),
            _task('5', 'Verify fork persistence', 'done',
                description: 'Store-backed fork with a regression test.'),
            _task('6', 'Old duplicate-send report', 'cancelled'),
          ];

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: TaskBoardScreen(client: client),
        ));
        // Fixed pump, not pumpAndSettle: the board runs a periodic refresh
        // timer, so the tree never goes fully quiet.
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/tasks_board_$density.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
