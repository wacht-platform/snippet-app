import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:snippet/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:snippet/notification_inbox.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/notifications.dart';
import 'package:snippet/android_reconciliation.dart';

void main() {
  late Database db;
  late NotificationInbox inbox;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE cursors (instance TEXT PRIMARY KEY, cursor INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE inbox (id TEXT PRIMARY KEY, instance TEXT NOT NULL, event TEXT NOT NULL, created INTEGER NOT NULL, read INTEGER NOT NULL DEFAULT 0)');
    await NotificationInbox.createAlertIds(db);
    inbox = NotificationInbox(db);
  });
  tearDown(() async {
    await db.close();
    onNotifTap = null;
  });
  String uuid(String id) => id.contains('-')
      ? id
      : '00000000-0000-0000-0000-${utf8.encode(id).fold<int>(0, (value, byte) => (value * 31 + byte) & 0xffffffffffff).toRadixString(16).padLeft(12, '0')}';
  Map<String, dynamic> event(int seq, String id) => {
        'event_id': seq,
        'notification_id': uuid(id),
        'created_at': 100,
        'expires_at': 1000,
        'kind': 'session.completed',
        'destination': {'type': 'session', 'id': 'worker'}
      };
  Map<String, dynamic> page(int next, List<Map<String, dynamic>> events) =>
      {'next_cursor': next, 'events': events, 'has_more': false};

  Map<String, dynamic> liveEvent(int seq) => {
        ...event(seq, '12345678-1234-1234-1234-123456789abc'),
        'kind': 'session.completed',
        'title': 'Live receipt',
        'destination': {'type': 'session', 'id': 'worker'}
      };

  test('live receipt and delayed recovery preserve cursor and popup dedup',
      () async {
    const instance = Instance(name: 'a', url: 'a', token: 'unused');
    final displayed = <Map<String, dynamic>>[];
    final sub = foregroundNotifications.stream.listen(displayed.add);
    addTearDown(sub.cancel);
    await receiveLiveNotification(instance,
        jsonEncode({'kind': 'notification', 'notification': liveEvent(9)}),
        inbox: inbox, now: 200);
    expect(await inbox.cursor('a'), 0);
    expect(await inbox.entries(), hasLength(1));
    expect(displayed, hasLength(1));
    expect(displayed.single['session'], 'worker');
    await receiveLiveNotification(
        instance, {'kind': 'notification', 'notification': liveEvent(9)},
        inbox: inbox, now: 200);
    final recovered = await inbox
        .ingest('a', 0, page(9, [event(3, 'earlier'), liveEvent(9)]), now: 200);
    expect(recovered.map((e) => e['notification_id']), [uuid('earlier')]);
    await presentNotifications(instance, inbox, recovered);
    expect(displayed, hasLength(2));
    expect(await inbox.entries(), hasLength(2));
    expect(await inbox.cursor('a'), 9);
    expect(await inbox.ingestLive('other', liveEvent(20), now: 200), isEmpty);
    expect(await inbox.cursor('other'), 0);
  });

  test('live rejects malformed events and ignores expired receipts', () async {
    for (final patch in <Map<String, dynamic>>[
      {'notification_id': 'not-a-uuid'},
      {'event_id': 1.5},
      {'created_at': null},
      {'expires_at': 'later'},
      {'kind': ''},
      {
        'destination': {'type': 'session'}
      },
    ]) {
      await expectLater(
          inbox.ingestLive('a', {...liveEvent(9), ...patch}, now: 200),
          throwsFormatException);
    }
    expect(
        await inbox.ingestLive('a', {...liveEvent(9), 'expires_at': 200},
            now: 200),
        isEmpty);
    expect(await inbox.entries(), isEmpty);
    expect(await inbox.cursor('a'), 0);
  });

  test('live and replay share validation and replay rolls back all writes', () async {
    for (final patch in <Map<String, dynamic>>[
      {'notification_id': 'invalid'},
      {'event_id': 0},
      {'kind': '   '},
      {'created_at': -1},
      {'expires_at': 100},
      {'destination': {'type': 'unknown', 'id': 'target'}},
      {'destination': {'type': 'task', 'id': 'target', 'session': 4}},
    ]) {
      final invalid = {...event(2, 'bad'), ...patch};
      await expectLater(inbox.ingestLive('a', invalid, now: 200), throwsFormatException);
      await expectLater(inbox.ingest('a', 0, page(2, [event(1, 'good'), invalid]), now: 200), throwsFormatException);
      expect(await inbox.cursor('a'), 0);
      expect(await inbox.entries(), isEmpty);
      expect(await db.query('alert_ids'), isEmpty);
    }
  });

  test('alert IDs are unique and stable across replay and reopened wrappers', () async {
    await inbox.ingestLive('a', event(2, 'two'), now: 200);
    final first = await inbox.alertId(uuid('two'));
    await inbox.ingest('a', 0, page(2, [event(1, 'one'), event(2, 'two')]), now: 200);
    final reopened = NotificationInbox(db);
    expect(await reopened.alertId(uuid('two')), first);
    expect(await reopened.alertId(uuid('one')), isNot(first));
    expect(first, greaterThan(0));
    expect(await db.query('alert_ids'), hasLength(2));
  });

  test('alert ID migration backfills existing inbox entries', () async {
    await db.execute('DROP TABLE alert_ids');
    await db.insert('inbox', {'id': uuid('old'), 'instance': 'a', 'event': jsonEncode(event(1, 'old')), 'created': 100});
    await NotificationInbox.createAlertIds(db);
    final id = await inbox.alertId(uuid('old'));
    await inbox.ingestLive('a', event(2, 'new'), now: 200);
    expect(await inbox.alertId(uuid('new')), greaterThan(id));
  });

  test('live handler ignores old signals and malformed envelopes', () async {
    const instance = Instance(name: 'a', url: 'a', token: 'unused');
    for (final message in <Object?>[
      {'kind': 'notification_available', 'cursor': 9},
      {'kind': 'notification'},
      {'kind': 'notification', 'notification': 'bad'},
      'invalid json',
    ]) {
      await receiveLiveNotification(instance, message, inbox: inbox, now: 200);
    }
    expect(await inbox.entries(), isEmpty);
    expect(await inbox.cursor('a'), 0);
  });

  test('gaps and empty filtered pages advance only fetched cursor', () async {
    await inbox.ingest('a', 0, page(9, [event(3, 'uuid')]), now: 200);
    expect(await inbox.cursor('a'), 9);
    await inbox.ingest('a', 9, page(15, []), now: 200);
    expect(await inbox.cursor('a'), 15);
    await inbox.ingest('a', 0, page(20, [event(20, 'stale')]), now: 200);
    expect(await inbox.cursor('a'), 15);
    expect(await inbox.entries(), hasLength(1));
  });
  test('empty raw500 page with has_more advances and malformed pages roll back',
      () async {
    await inbox.ingest(
        'a', 0, {'next_cursor': 500, 'events': [], 'has_more': true},
        now: 200);
    expect(await inbox.cursor('a'), 500);
    for (final invalid in <Map<String, dynamic>>[
      {'next_cursor': 500, 'events': [], 'has_more': true},
      {'next_cursor': 501.5, 'events': [], 'has_more': false},
      {'next_cursor': 501, 'events': [], 'has_more': 'yes'},
      page(501, [
        {...event(501, 'bad'), 'event_id': 501.5}
      ]),
      page(501, [
        {...event(501, 'bad'), 'created_at': null}
      ]),
    ]) {
      await expectLater(
          inbox.ingest('a', 500, invalid, now: 200), throwsFormatException);
      expect(await inbox.cursor('a'), 500);
      expect(await inbox.entries(), isEmpty);
    }
    await inbox.ingest('a', 500, page(501, [event(501, 'valid')]), now: 200);
    expect(await inbox.cursor('a'), 501);
  });

  test('global UUID dedup and durable read distinct from receipt', () async {
    await inbox.ingest('a', 0, page(1, [event(1, 'uuid')]), now: 200);
    await inbox.markRead(uuid('uuid'));
    await inbox.ingest('b', 0, page(7, [event(7, 'uuid')]), now: 200);
    expect(await inbox.entries(), hasLength(1));
    expect((await inbox.entries()).single['read'], 1);
    expect(await inbox.cursor('b'), 7);
  });
  test('unordered page rolls back inbox and cursor', () async {
    await expectLater(
        inbox.ingest('a', 0, page(8, [event(7, 'one'), event(3, 'two')]),
            now: 200),
        throwsFormatException);
    expect(await inbox.cursor('a'), 0);
    expect(await inbox.entries(), isEmpty);
  });
  test('disabled background polling does not initialize native notifications',
      () async {
    SharedPreferences.setMockInitialValues({'notif_enabled': false});
    await reconcileAndroidNotificationState();
  });
  test('shared foreground lease suppresses background alerts', () async {
    await inbox.setForeground(true);
    expect(await inbox.foregroundActive(), true);
    await inbox.setForeground(false);
    expect(await inbox.foregroundActive(), false);
  });
  testWidgets('startup popover survives until subscriber mounts',
      (tester) async {
    foregroundNotifications.add({'title': 'Queued at startup'});
    await tester.pumpWidget(
        const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    expect(find.text('Queued at startup'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Queued at startup'), findsNothing);
  });
  testWidgets('mounted inbox refreshes and tap pops back to destination',
      (tester) async {
    Map<String, dynamic>? opened;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => NotificationInboxScreen(
                                  inbox: inbox,
                                  onOpen: (payload) => opened = payload))),
                      child: const Text('Inbox')),
                ))));
    await tester.tap(find.text('Inbox'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() => inbox.ingest(
        'a',
        0,
        page(1, [
          {
            ...event(1, 'live'),
            'title': 'Arrived live',
            'destination': {'type': 'session', 'id': 'actual'}
          }
        ]),
        now: 200));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Arrived live'), findsOneWidget);
    await tester.tap(find.text('Arrived live'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(opened?['session'], 'actual');
    final rows = await tester.runAsync(() => inbox.entries());
    expect(rows!.single['read'], 1);
  });
  testWidgets('unread badge responds to receipt and read', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationUnreadBadge(inbox: inbox))));
    await tester.runAsync(
        () => inbox.ingest('a', 0, page(1, [event(1, 'badge')]), now: 200));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, true);
    await tester.runAsync(() => inbox.markRead(uuid('badge')));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, false);
  });
  for (final type in ['session', 'task', 'conversation']) {
    testWidgets('foreground popover taps $type destination', (tester) async {
      Map<String, dynamic>? opened;
      onNotifTap = (payload) => opened = payload;
      await tester.pumpWidget(
          const MaterialApp(home: NotificationPopovers(child: Scaffold())));
      final payload = notificationDestination('machine', {
        'title': 'Hello',
        'notification_id': 'id',
        'destination': {'type': type, 'id': 'target', 'session': 'recipient'}
      });
      foregroundNotifications.add(payload);
      await tester.pump();
      await tester.tap(find.text('Hello'));
      await tester.pump();
      expect(opened?['destination']['id'], 'target');
      expect(opened?['session'], type == 'session' ? 'target' : 'recipient');
      expect(find.text('Hello'), findsNothing);
    });
  }
}
