import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class NotificationCursor implements Comparable<NotificationCursor> {
  const NotificationCursor(this.createdAt, this.eventId);
  final int createdAt;
  final int eventId;
  static NotificationCursor parse(Object? raw) {
    if (raw is! Map || raw['created_at'] is! int || raw['event_id'] is! int ||
        (raw['created_at'] as int) < 0 || (raw['event_id'] as int) < 0) {
      throw const FormatException('Malformed notification cursor');
    }
    return NotificationCursor(raw['created_at'] as int, raw['event_id'] as int);
  }
  @override
  int compareTo(NotificationCursor other) => createdAt == other.createdAt
      ? eventId.compareTo(other.eventId) : createdAt.compareTo(other.createdAt);
  NotificationCursor get overlap => NotificationCursor(createdAt > 10800 ? createdAt - 10800 : 0, 0);
}

class NotificationInbox {
  NotificationInbox(this.db);
  final Database db;
  static Future<NotificationInbox>? _opening;
  static Future<NotificationInbox> open() => _opening ??= _open();
  static Future<NotificationInbox> _open() async {
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }
    final db = await factory.openDatabase(
        '${await factory.getDatabasesPath()}/notification_inbox.db',
        options: OpenDatabaseOptions(
        version: 3, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE cursors (instance TEXT PRIMARY KEY, cursor INTEGER NOT NULL, created_at INTEGER NOT NULL DEFAULT 0)');
      await db.execute(
          'CREATE TABLE inbox (id TEXT PRIMARY KEY, instance TEXT NOT NULL, event TEXT NOT NULL, created INTEGER NOT NULL, read INTEGER NOT NULL DEFAULT 0)');
      await createAlertIds(db);
    }, onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2) await createAlertIds(db);
      if (oldVersion < 3) await migrateTimeCursor(db);
    }));
    return NotificationInbox(db);
  }

  static Future<void> migrateTimeCursor(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE cursors ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
    // ID-only checkpoints cannot prove a time boundary; replay retained history.
    await db.update('cursors', {'cursor': 0, 'created_at': 0});
  }

  static Future<void> createAlertIds(DatabaseExecutor db) async {
    await db.execute(
        'CREATE TABLE alert_ids (alert_id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(alert_id <= 2147483647), notification_id TEXT NOT NULL UNIQUE)');
    await db.execute('INSERT INTO alert_ids (notification_id) SELECT id FROM inbox ORDER BY created, id');
  }

  Future<int> alertId(String notificationId) async {
    final rows = await db.query('alert_ids',
        where: 'notification_id = ?', whereArgs: [notificationId]);
    if (rows.isEmpty) throw StateError('Notification is not in the inbox');
    return rows.single['alert_id'] as int;
  }

  static void validateEvent(Map<String, dynamic> event) {
    final id = event['notification_id'];
    final destination = event['destination'];
    if (id is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(id) ||
        event['event_id'] is! int ||
        (event['event_id'] as int) <= 0 ||
        event['created_at'] is! int ||
        (event['created_at'] as int) < 0 ||
        event['expires_at'] is! int ||
        (event['expires_at'] as int) <= (event['created_at'] as int) ||
        event['kind'] is! String ||
        (event['kind'] as String).trim().isEmpty ||
        destination is! Map ||
        !['session', 'task', 'conversation'].contains(destination['type']) ||
        destination['id'] is! String ||
        (destination['id'] as String).trim().isEmpty ||
        (destination.containsKey('session') &&
            (destination['session'] is! String ||
                (destination['session'] as String).trim().isEmpty))) {
      throw const FormatException('Malformed notification');
    }
  }

  Future<NotificationCursor> cursor(String instance) => _cursor(db, instance);

  static Future<NotificationCursor> _cursor(DatabaseExecutor tx, String instance) async {
    final rows = await tx.query('cursors', where: 'instance = ?', whereArgs: [instance]);
    return rows.isEmpty ? const NotificationCursor(0, 0)
        : NotificationCursor(rows.first['created_at'] as int, rows.first['cursor'] as int);
  }

  static Future<NotificationCursor> _advance(DatabaseExecutor tx, String instance, NotificationCursor next) async {
    final current = await _cursor(tx, instance);
    final high = next.compareTo(current) > 0 ? next : current;
    await tx.insert('cursors', {'instance': instance, 'cursor': high.eventId, 'created_at': high.createdAt}, conflictAlgorithm: ConflictAlgorithm.replace);
    return high;
  }

  static Future<void> _prune(DatabaseExecutor tx, String instance, NotificationCursor high) async {
    final rows = await tx.query('inbox', columns: ['id'], where: 'instance = ? AND created < ?', whereArgs: [instance, high.overlap.createdAt], limit: 500);
    for (final row in rows) {
      await tx.delete('alert_ids', where: 'notification_id = ?', whereArgs: [row['id']]);
      await tx.delete('inbox', where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  static Future<bool> _insert(DatabaseExecutor tx, String instance, Map<String, dynamic> event, int now) async {
    if ((event['expires_at'] as int) <= now) return false;
    final id = event['notification_id'] as String;
    final exists = await tx.query('inbox', columns: ['id'], where: 'id = ? OR (instance = ? AND json_extract(event, \'\$.event_id\') = ?)', whereArgs: [id, instance, event['event_id']]);
    if (exists.isNotEmpty) return false;
    await tx.insert('inbox', {'id': id, 'instance': instance, 'event': jsonEncode(event), 'created': event['created_at']});
    await tx.insert('alert_ids', {'notification_id': id});
    return true;
  }

  Future<List<Map<String, dynamic>>> ingest(
          String instance, NotificationCursor since, Map<String, dynamic> page,
          {int? now}) =>
      db.transaction<List<Map<String, dynamic>>>((tx) async {
        final next = NotificationCursor.parse(page['next_cursor']);
        final events = page['events'];
        if (next.compareTo(since) < 0 ||
            events is! List ||
            page['has_more'] is! bool ||
            (page['has_more'] == true && next.compareTo(since) <= 0)) {
          throw const FormatException('Malformed notification page');
        }
        var previous = since;
        final received = <Map<String, dynamic>>[];
        for (final raw in events) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('Malformed notification');
          }
          final event = raw;
          validateEvent(event);
          final seq = NotificationCursor.parse(event);
          if (seq.compareTo(previous) <= 0 || seq.compareTo(next) > 0) {
            throw const FormatException('Unordered notification page');
          }
          previous = seq;
          if (await _insert(tx, instance, event,
              now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
            received.add(event);
          }
        }
        await _advance(tx, instance, next);
        return received;
      });

  Future<List<Map<String, dynamic>>> ingestLive(
      String instance, Map<String, dynamic> event,
      {int? now}) async {
    validateEvent(event);
    if ((event['expires_at'] as int) <=
        (now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      return [];
    }
    final received =
        await db.transaction<List<Map<String, dynamic>>>((tx) async {
      final current = await _cursor(tx, instance);
      if ((event['created_at'] as int) < current.overlap.createdAt) return [];
      final inserted = await _insert(tx, instance, event,
          now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final high = await _advance(tx, instance, NotificationCursor.parse(event));
      await _prune(tx, instance, high);
      return inserted ? [event] : [];
    });
    return received;
  }

  Future<void> prune(String instance) => db.transaction((tx) async {
    await _prune(tx, instance, await _cursor(tx, instance));
  });

  Future<List<Map<String, Object?>>> entries() =>
      db.query('inbox', orderBy: 'created DESC');
  Future<void> setForeground(bool value, {String? visibleKey}) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY, until_sec INTEGER NOT NULL)');
    final columns = await db.rawQuery('PRAGMA table_info(app_state)');
    if (!columns.any((column) => column['name'] == 'visible_key')) {
      await db.execute('ALTER TABLE app_state ADD COLUMN visible_key TEXT');
    }
    await db.insert(
        'app_state',
        {
          'id': 1,
          'visible_key': value ? visibleKey : null,
          'until_sec':
              value ? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60 : 0
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> foregroundActive() async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY, until_sec INTEGER NOT NULL)');
    final rows = await db.query('app_state');
    return rows.isNotEmpty &&
        (rows.first['until_sec'] as int) >
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> markRead(String id) async {
    await db.update('inbox', {'read': 1}, where: 'id = ?', whereArgs: [id]);
  }
}

Map<String, dynamic> notificationDestination(
    String url, Map<String, dynamic> event) {
  final destination =
      (event['destination'] as Map?)?.cast<String, dynamic>() ?? {};
  return {
    'url': url,
    'notification_id': event['notification_id'],
    'title': event['title'],
    'kind': event['kind'],
    'body': event['body'] ?? event['message'],
    'destination': destination,
    'session': destination['type'] == 'session'
        ? destination['id']
        : destination['session'] ?? event['session']
  };
}
