import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/settled_sessions.dart';

SessionInfo _s(String id, {bool settled = false, int? at, int active = 0}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Chat $id',
      'last_active': active,
      'settled': settled,
      if (at != null) 'settled_at': at,
    });

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
  final woken = <String>[];

  @override
  Future<void> unsettleSession(String id) async => woken.add(id);
}

void main() {
  testWidgets('phone list keeps settled sessions in a collapsed group',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: Sidebar(
          instances: const [],
          active: null,
          client: _Client(),
          selectedSessionId: null,
          sessions: [
            _s('a', active: now),
            _s('b', settled: true, at: now - 86400),
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
      expect(find.text('Chat a'), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
      expect(find.text('Chat b'), findsNothing);
      await tester.tap(find.text('Settled'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Chat b'), findsOneWidget);
      expect(find.textContaining('deleted in 14 days'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('parses settled fields and tolerates absence', () {
    final a = SessionInfo.fromJson({
      'id': 'a',
      'settled': true,
      'settled_at': 1000,
      'idle_secs': 42,
      'cache': 'cold',
    });
    expect(a.settled, isTrue);
    expect(a.settledAt, 1000);
    expect(a.idleSecs, 42);
    expect(a.cache, 'cold');
    final b = SessionInfo.fromJson({'id': 'b', 'settled_at': null});
    expect(b.settled, isFalse);
    expect(b.settledAt, isNull);
    expect(b.idleSecs, 0);
    expect(b.cache, 'warm');
  });

  test('parses keep_awake and labels the menu item', () {
    final on = SessionInfo.fromJson({'id': 'a', 'keep_awake': true});
    final off = SessionInfo.fromJson({'id': 'b'});
    expect(on.keepAwake, isTrue);
    expect(off.keepAwake, isFalse);
    expect(keepAwakeLabel(off), "Don't auto-settle");
    expect(keepAwakeLabel(on), 'Allow auto-settle');
    expect(
        splitSettled([
          SessionInfo.fromJson(
              {'id': 'k', 'keep_awake': true, 'settled': true})
        ]).settled.length,
        1);
  });

  test('splitSettled separates and orders settled by settle time', () {
    final r = splitSettled([
      _s('m1', active: 5),
      _s('s1', settled: true, at: 100),
      _s('m2', active: 9),
      _s('s2', settled: true, at: 200),
    ]);
    expect(r.main.map((s) => s.id), ['m1', 'm2']);
    expect(r.settled.map((s) => s.id), ['s2', 's1']);
  });

  test('settledMeta counts days to deletion', () {
    const day = 86400;
    final s = _s('x', settled: true, at: 1000);
    expect(settledMeta(s, nowSecs: 1000 + day), 'Settled · deleted in 14 days');
    expect(settledMeta(s, nowSecs: 1000 + 14 * day + 1),
        'Settled · deleted in 1 day');
    expect(settledMeta(s, nowSecs: 1000 + 16 * day), 'Settled · deleted today');
    expect(settledMeta(_s('y', settled: true), nowSecs: 5), 'Settled');
  });
}
