import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class NotificationInbox {
  NotificationInbox(this.db);
  final Database db;
  static final changes = ValueNotifier<int>(0);
  static Future<NotificationInbox>? _opening;
  static Future<NotificationInbox> open() => _opening ??= _open();
  static Future<NotificationInbox> _open() async {
    final db = await openDatabase(
        '${await getDatabasesPath()}/notification_inbox.db',
        version: 2, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE cursors (instance TEXT PRIMARY KEY, cursor INTEGER NOT NULL)');
      await db.execute(
          'CREATE TABLE inbox (id TEXT PRIMARY KEY, instance TEXT NOT NULL, event TEXT NOT NULL, created INTEGER NOT NULL, read INTEGER NOT NULL DEFAULT 0)');
      await createAlertIds(db);
    }, onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2) await createAlertIds(db);
    });
    return NotificationInbox(db);
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

  Future<int> cursor(String instance) async {
    final rows =
        await db.query('cursors', where: 'instance = ?', whereArgs: [instance]);
    return rows.isEmpty ? 0 : rows.first['cursor'] as int;
  }

  Future<List<Map<String, dynamic>>> ingest(
          String instance, int since, Map<String, dynamic> page,
          {int? now}) =>
      db.transaction<List<Map<String, dynamic>>>((tx) async {
        final rows = await tx
            .query('cursors', where: 'instance = ?', whereArgs: [instance]);
        final current = rows.isEmpty ? 0 : rows.first['cursor'] as int;
        if (current != since) return [];
        final next = page['next_cursor'];
        final events = page['events'];
        if (next is! int ||
            next < since ||
            events is! List ||
            page['has_more'] is! bool ||
            (page['has_more'] == true && next <= since)) {
          throw const FormatException('Malformed notification page');
        }
        var previous = since;
        final received = <Map<String, dynamic>>[];
        for (final raw in events) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('Malformed notification');
          }
          final event = raw;
          final seq = event['event_id'];
          validateEvent(event);
          if ((seq as int) <= previous || seq > next) {
            throw const FormatException('Unordered notification page');
          }
          previous = seq;
          final id = event['notification_id'] as String;
          final expires = (event['expires_at'] as num?)?.toInt();
          if (expires != null &&
              expires <= (now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000))
            continue;
          final exists = await tx.query('inbox',
              columns: ['id'], where: 'id = ?', whereArgs: [id]);
          if (exists.isNotEmpty) continue;
          await tx.insert('inbox', {
            'id': id,
            'instance': instance,
            'event': jsonEncode(event),
            'created': event['created_at']
          });
          await tx.insert('alert_ids', {'notification_id': id});
          received.add(event);
        }
        await tx.insert('cursors', {'instance': instance, 'cursor': next},
            conflictAlgorithm: ConflictAlgorithm.replace);
        return received;
      }).then((received) {
        changes.value++;
        return received;
      });

  Future<List<Map<String, dynamic>>> ingestLive(
      String instance, Map<String, dynamic> event,
      {int? now}) async {
    final id = event['notification_id'];
    validateEvent(event);
    if ((event['expires_at'] as int) <=
        (now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      return [];
    }
    final received =
        await db.transaction<List<Map<String, dynamic>>>((tx) async {
      final exists = await tx.query('inbox',
          columns: ['id'], where: 'id = ?', whereArgs: [id]);
      if (exists.isNotEmpty) return [];
      await tx.insert('inbox', {
        'id': id,
        'instance': instance,
        'event': jsonEncode(event),
        'created': event['created_at']
      });
      await tx.insert('alert_ids', {'notification_id': id});
      return [event];
    });
    if (received.isNotEmpty) changes.value++;
    return received;
  }

  Future<List<Map<String, Object?>>> entries() =>
      db.query('inbox', orderBy: 'created DESC');
  Future<void> setForeground(bool value) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY, until_sec INTEGER NOT NULL)');
    await db.insert(
        'app_state',
        {
          'id': 1,
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
    changes.value++;
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
    'destination': destination,
    'session': destination['type'] == 'session'
        ? destination['id']
        : destination['session'] ?? event['session']
  };
}

class NotificationUnreadBadge extends StatelessWidget {
  const NotificationUnreadBadge({super.key, this.inbox});
  final NotificationInbox? inbox;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: NotificationInbox.changes,
        builder: (context, _, child) =>
            FutureBuilder<List<Map<String, Object?>>>(
          future: inbox != null
              ? inbox!.entries()
              : NotificationInbox.open().then((store) => store.entries()),
          builder: (context, snapshot) {
            final unread =
                snapshot.data?.where((row) => row['read'] == 0).length ?? 0;
            return Badge(
                label: Text('$unread'),
                isLabelVisible: unread > 0,
                child: const Icon(Icons.notifications_outlined));
          },
        ),
      );
}

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key, required this.onOpen, this.inbox});
  final void Function(Map<String, dynamic>) onOpen;
  final NotificationInbox? inbox;
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  Future<NotificationInbox> _store() async =>
      widget.inbox ?? await NotificationInbox.open();
  Future<List<Map<String, Object?>>> _rows() async =>
      (await _store()).entries();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ValueListenableBuilder<int>(
            valueListenable: NotificationInbox.changes,
            builder: (context, _, child) => FutureBuilder<
                    List<Map<String, Object?>>>(
                future: _rows(),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return const Center(
                        child: Text('Could not load notifications'));
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final rows = snapshot.data!;
                  if (rows.isEmpty)
                    return const Center(child: Text('No notifications yet'));
                  return ListView(
                      children: rows.map((row) {
                    final event = (jsonDecode(row['event'] as String) as Map)
                        .cast<String, dynamic>();
                    return ListTile(
                      leading: Icon(row['read'] == 0
                          ? Icons.mark_email_unread_outlined
                          : Icons.drafts_outlined),
                      title: Text(event['title']?.toString() ??
                          event['kind']?.toString() ??
                          'Notification'),
                      subtitle:
                          Text('${event['workspace'] ?? row['instance']}'),
                      onTap: () async {
                        await (await _store()).markRead(row['id'] as String);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        widget.onOpen(notificationDestination(
                            row['instance'] as String, event));
                      },
                      trailing: row['read'] == 0
                          ? IconButton(
                              tooltip: 'Mark read',
                              icon: const Icon(Icons.done),
                              onPressed: () async {
                                await (await _store())
                                    .markRead(row['id'] as String);
                                if (mounted) setState(() {});
                              })
                          : null,
                    );
                  }).toList());
                })),
      );
}
