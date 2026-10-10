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
        'CREATE TABLE cursors (instance TEXT PRIMARY KEY, cursor INTEGER NOT NULL, created_at INTEGER NOT NULL DEFAULT 0)');
    await db.execute(
        'CREATE TABLE inbox (id TEXT PRIMARY KEY, instance TEXT NOT NULL, event TEXT NOT NULL, created INTEGER NOT NULL, read INTEGER NOT NULL DEFAULT 0)');
    await NotificationInbox.createAlertIds(db);
    inbox = NotificationInbox(db);
    notificationAppForeground = true;
    visibleNotificationSession.value = null;
    foregroundNotifications.drain();
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
      {'next_cursor': {'created_at': 100, 'event_id': next}, 'events': events, 'has_more': false};
  Future<int> cursor(String instance) async => (await inbox.cursor(instance)).eventId;
  Future<List<Map<String, dynamic>>> ingest(String instance, int since, Map<String, dynamic> page, {int? now}) =>
      inbox.ingest(instance, NotificationCursor(since == 0 ? 0 : 100, since), page, now: now);

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
    expect(await cursor('a'), 9);
    expect(await inbox.entries(), hasLength(1));
    expect(displayed, hasLength(1));
    expect(displayed.single['session'], 'worker');
    await receiveLiveNotification(
        instance, {'kind': 'notification', 'notification': liveEvent(9)},
        inbox: inbox, now: 200);
    final recovered = await ingest('a', 0, page(9, [event(3, 'earlier'), liveEvent(9)]), now: 200);
    expect(recovered.map((e) => e['notification_id']), [uuid('earlier')]);
    await presentNotifications(instance, inbox, recovered);
    expect(displayed, hasLength(2));
    expect(await inbox.entries(), hasLength(2));
    expect(await cursor('a'), 9);
    expect(await inbox.ingestLive('other', liveEvent(20), now: 200), isEmpty);
    expect(await cursor('other'), 20);
  });

  test('visible session suppresses live and replay but preserves receipt', () async {
    const instance = Instance(name: 'a', url: 'a', token: 'unused');
    final displayed = <Map<String, dynamic>>[];
    final sub = foregroundNotifications.stream.listen(displayed.add);
    addTearDown(sub.cancel);
    visibleNotificationSession.value = notificationSessionKey('a', 'worker');
    await receiveLiveNotification(instance,
        {'kind': 'notification', 'notification': liveEvent(9)},
        inbox: inbox, now: 200);
    final recovered = await ingest('a', 0,
        page(9, [event(3, 'earlier'), liveEvent(9)]), now: 200);
    await presentNotifications(instance, inbox, recovered);
    expect(displayed, isEmpty);
    expect(await inbox.entries(), hasLength(2));
    expect(await cursor('a'), 9);
    expect(await inbox.ingestLive('a', liveEvent(9), now: 200), isEmpty);
    await presentNotifications(instance, inbox, [
      {...event(10, 'other'), 'destination': {'type': 'session', 'id': 'other'}}
    ]);
    expect(displayed, hasLength(1));
    await presentNotifications(
        const Instance(name: 'b', url: 'b', token: 'unused'), inbox, [event(11, 'instance')]);
    expect(displayed, hasLength(2));
    visibleNotificationSession.value = null;
    await presentNotifications(instance, inbox, [event(12, 'chats')]);
    expect(displayed, hasLength(3));
  });

  test('background never suppresses merely last-open session', () async {
    visibleNotificationSession.value = notificationSessionKey('a', 'worker');
    notificationAppForeground = false;
    expect(suppressVisibleNotification({'url': 'a', 'session': 'worker'}), false);
    await inbox.setForeground(true, visibleKey: notificationSessionKey('a', 'worker'));
    expect((await db.query('app_state')).single['visible_key'], notificationSessionKey('a', 'worker'));
    await inbox.setForeground(false, visibleKey: notificationSessionKey('a', 'worker'));
    expect(await inbox.foregroundActive(), false);
    expect((await db.query('app_state')).single['visible_key'], isNull);
  });

  testWidgets('queued popover rechecks visible session and instance', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    foregroundNotifications.add({'title': 'First', 'url': 'a', 'session': 'other'});
    foregroundNotifications.add({'title': 'Queued', 'url': 'a', 'session': 'worker'});
    foregroundNotifications.add({'title': 'Other instance', 'url': 'b', 'session': 'worker'});
    await tester.pump();
    visibleNotificationSession.value = notificationSessionKey('a', 'worker');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Queued'), findsNothing);
    expect(find.text('Other instance'), findsOneWidget);
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
    expect(await cursor('a'), 0);
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
      await expectLater(ingest('a', 0, page(2, [event(1, 'good'), invalid]), now: 200), throwsFormatException);
      expect(await cursor('a'), 0);
      expect(await inbox.entries(), isEmpty);
      expect(await db.query('alert_ids'), isEmpty);
    }
  });

  test('alert IDs are unique and stable across replay and reopened wrappers', () async {
    await inbox.ingestLive('a', event(2, 'two'), now: 200);
    final first = await inbox.alertId(uuid('two'));
    await ingest('a', 0, page(2, [event(1, 'one'), event(2, 'two')]), now: 200);
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
    expect(await cursor('a'), 0);
  });

  test('gaps and empty filtered pages advance only fetched cursor', () async {
    await ingest('a', 0, page(9, [event(3, 'uuid')]), now: 200);
    expect(await cursor('a'), 9);
    await ingest('a', 9, page(15, []), now: 200);
    expect(await cursor('a'), 15);
    await ingest('a', 0, page(20, [event(20, 'stale')]), now: 200);
    expect(await cursor('a'), 20);
    expect(await inbox.entries(), hasLength(2));
  });
  test('empty raw500 page with has_more advances and malformed pages roll back',
      () async {
    await ingest(
        'a', 0, {'next_cursor': {'created_at': 100, 'event_id': 500}, 'events': [], 'has_more': true},
        now: 200);
    expect(await cursor('a'), 500);
    for (final invalid in <Map<String, dynamic>>[
      {'next_cursor': {'created_at': 100, 'event_id': 500}, 'events': [], 'has_more': true},
      {'next_cursor': {'created_at': 100, 'event_id': 501.5}, 'events': [], 'has_more': false},
      {'next_cursor': {'created_at': 100, 'event_id': 501}, 'events': [], 'has_more': 'yes'},
      page(501, [
        {...event(501, 'bad'), 'event_id': 501.5}
      ]),
      page(501, [
        {...event(501, 'bad'), 'created_at': null}
      ]),
    ]) {
      await expectLater(
          ingest('a', 500, invalid, now: 200), throwsFormatException);
      expect(await cursor('a'), 500);
      expect(await inbox.entries(), isEmpty);
    }
    await ingest('a', 500, page(501, [event(501, 'valid')]), now: 200);
    expect(await cursor('a'), 501);
  });

  test('global UUID dedup and durable read distinct from receipt', () async {
    await ingest('a', 0, page(1, [event(1, 'uuid')]), now: 200);
    await inbox.markRead(uuid('uuid'));
    await ingest('b', 0, page(7, [event(7, 'uuid')]), now: 200);
    expect(await inbox.entries(), hasLength(1));
    expect((await inbox.entries()).single['read'], 1);
    expect(await cursor('b'), 7);
  });
  test('unordered page rolls back inbox and cursor', () async {
    await expectLater(
        ingest('a', 0, page(8, [event(7, 'one'), event(3, 'two')]),
            now: 200),
        throwsFormatException);
    expect(await cursor('a'), 0);
    expect(await inbox.entries(), isEmpty);
  });
  test('time overlap, stale live, source dedup and alert IDs survive pruning', () async {
    Map<String, dynamic> timed(int seq, String id, int time) => {
      ...event(seq, id), 'created_at': time, 'expires_at': 200000
    };
    await inbox.ingestLive('a', timed(1, 'old', 100), now: 200);
    final oldId = await inbox.alertId(uuid('old'));
    await inbox.ingestLive('a', timed(2, 'edge', 1000), now: 200);
    final edgeId = await inbox.alertId(uuid('edge'));
    await inbox.ingestLive('a', timed(3, 'ahead', 11800), now: 200);
    expect((await inbox.cursor('a')).overlap.createdAt, 1000);
    expect(await inbox.ingestLive('a', timed(4, 'stale', 999), now: 200), isEmpty);
    expect(await db.query('alert_ids', where: 'notification_id = ?', whereArgs: [uuid('old')]), isEmpty);
    expect(await inbox.alertId(uuid('edge')), edgeId);
    expect(await inbox.ingestLive('a', timed(3, 'alias', 11800), now: 200), isEmpty);
    await inbox.ingestLive('a', timed(5, 'tie', 11800), now: 200);
    expect((await inbox.cursor('a')).eventId, 5);
    expect(await inbox.alertId(uuid('tie')), greaterThan(oldId));
    expect((await NotificationInbox(db).cursor('a')).eventId, 5);
  });

  test('offline recovery uses saved time not wall clock and accepts stale scan', () async {
    Map<String, dynamic> timed(int seq, String id, int time) => {
      ...event(seq, id), 'created_at': time, 'expires_at': 200000
    };
    await inbox.ingestLive('a', timed(1, 'saved', 10000), now: 10001);
    final scan = (await inbox.cursor('a')).overlap;
    await inbox.ingestLive('a', timed(9, 'aheadws', 96000), now: 96001);
    final recovered = await inbox.ingest('a', scan, {
      'next_cursor': {'created_at': 20000, 'event_id': 2},
      'events': [timed(2, 'missed', 20000)], 'has_more': true
    }, now: 96001);
    expect(recovered, hasLength(1));
    expect((await inbox.cursor('a')).createdAt, 96000);
    await inbox.ingest('a', const NotificationCursor(20000, 2), {
      'next_cursor': {'created_at': 30000, 'event_id': 4},
      'events': [], 'has_more': true
    }, now: 96001);
    expect((await inbox.cursor('a')).eventId, 9);
    await inbox.prune('a');
    expect((await inbox.entries()).map((e) => e['id']), [uuid('aheadws')]);
  });

  test('legacy migration resets safely without changing existing alert IDs', () async {
    await inbox.ingestLive('a', event(9, 'saved'), now: 200);
    final id = await inbox.alertId(uuid('saved'));
    await db.execute('DROP TABLE cursors');
    await db.execute('CREATE TABLE cursors (instance TEXT PRIMARY KEY, cursor INTEGER NOT NULL)');
    await db.insert('cursors', {'instance': 'a', 'cursor': 999});
    await NotificationInbox.migrateTimeCursor(db);
    final reopened = NotificationInbox(db);
    expect((await reopened.cursor('a')).createdAt, 0);
    expect((await reopened.cursor('a')).eventId, 0);
    expect(await reopened.alertId(uuid('saved')), id);
    expect(await ingest('a', 0, page(9, [event(9, 'saved')]), now: 200), isEmpty);
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
    await tester.pumpAndSettle();
    expect(find.text('Queued at startup'), findsNothing);
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
