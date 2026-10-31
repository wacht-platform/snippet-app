import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
}

final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

SessionInfo _s(String id, String title, String status,
        {String folder = '/code/snippet-mobile',
        String? branch,
        Map<String, dynamic>? changes,
        int? since}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'last_active': _now - 600,
      'folder': folder,
      if (branch != null) 'branch': branch,
      if (changes != null) 'changes': changes,
      if (since != null) 'running_since': since,
    });

Future<void> _pump(WidgetTester tester, Size size, TargetPlatform p) async {
  debugDefaultTargetPlatformOverride = p;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
        body: Sidebar(
      instances: const [],
      active: null,
      client: _Client(),
      selectedSessionId: 'b',
      sessions: [
        _s('a', 'Redo voice settings subpage', 'waiting_for_input',
            branch: 'main', changes: {'files': 4, 'added': 120, 'removed': 31}),
        _s('b', 'Richer session cards', 'running',
            branch: 'cards', since: _now - 260,
            changes: {'files': 2, 'added': 88, 'removed': 12}),
        _s('c', 'Release pipeline fix', 'idle',
            folder: '/code/snippet-service', branch: 'main'),
        _s('d', 'Notes', 'idle', folder: ''),
      ],
      sessionsLoading: false,
      onRefreshSessions: () {},
      onNewSession: () {},
      onSelectInstance: (_) {},
      onOpenMissionControl: () {},
      onOpenSession: (_, __, ___) {},
      onAddInstance: () {},
      onRenameInstance: (_, name) {},
      onRemoveInstance: (_) {},
      onSessionDeleted: (_) {},
      health: const {},
      onRefreshHealth: () {},
      topInset: false,
      mobileHome: MobileHome.chats,
      onMobileHome: (_) {},
      settingsSection: null,
      onSettingsSection: (_) {},
      agent: null,
      onAgent: (_) {},
    )),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('phone cards show project, status, branch and diff',
      (tester) async {
    try {
      await _pump(tester, const Size(390, 700), TargetPlatform.android);
      expect(find.text('snippet-mobile'), findsNWidgets(2));
      expect(find.text('Input'), findsOneWidget);
      expect(find.text('Working 4m'), findsOneWidget);
      expect(find.text('+88'), findsOneWidget);
      expect(find.text('-12'), findsOneWidget);
      await expectLater(find.byType(Sidebar),
          matchesGoldenFile('visual/goldens/session_cards_mobile.png'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop cards are one flat list with the same detail',
      (tester) async {
    try {
      await _pump(tester, const Size(300, 520), TargetPlatform.macOS);
      expect(find.text('SNIPPET-MOBILE'), findsNothing);
      expect(find.text('Working 4m'), findsOneWidget);
      expect(find.text('+120'), findsOneWidget);
      await expectLater(find.byType(Sidebar),
          matchesGoldenFile('visual/goldens/session_cards_desktop.png'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
