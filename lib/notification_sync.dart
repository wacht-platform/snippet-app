import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'device_events.dart';
import 'models.dart';
import 'notification_inbox.dart';
import 'notifications.dart';
import 'store.dart';

class ForegroundNotificationQueue {
  final _controller =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _pending = <Map<String, dynamic>>[];
  Stream<Map<String, dynamic>> get stream => _controller.stream;
  void add(Map<String, dynamic> payload) {
    if (_controller.hasListener) {
      _controller.add(payload);
    } else {
      _pending.add(payload);
    }
  }

  List<Map<String, dynamic>> drain() {
    final result = List<Map<String, dynamic>>.of(_pending);
    _pending.clear();
    return result;
  }
}

final foregroundNotifications = ForegroundNotificationQueue();
bool notificationAppForeground = true;
final visibleNotificationSession = ValueNotifier<String?>(null);

String notificationSessionKey(String instance, String session) =>
    jsonEncode([instance, session]);

bool suppressVisibleNotification(Map<String, dynamic> payload) =>
    notificationAppForeground &&
    payload['url'] is String &&
    payload['session'] is String &&
    visibleNotificationSession.value ==
        notificationSessionKey(payload['url'] as String, payload['session'] as String);
final Map<String, Future<void>> _fetches = {};

Future<void> syncNotificationInstance(Instance instance,
    {bool background = false}) {
  final key = instance.url;
  final next = (_fetches[key] ?? Future<void>.value())
      .catchError((Object _) {})
      .then((_) async {
    final inbox = await NotificationInbox.open();
    final client = DaemonClient(instance.url, instance.token);
    var since = (await inbox.cursor(key)).overlap;
    while (true) {
      final page = await client.notificationsPage(
          sinceCreatedAt: since.createdAt, sinceEventId: since.eventId);
      final received = await inbox.ingest(key, since, page);
      await presentNotifications(instance, inbox, received,
          background: background);
      if (page['has_more'] != true) break;
      since = NotificationCursor.parse(page['next_cursor']);
    }
    await inbox.prune(key);
  });
  _fetches[key] = next;
  return next;
}

Future<void> receiveLiveNotification(Instance instance, Object? message,
    {NotificationInbox? inbox, int? now}) async {
  final event = DeviceEvent.decode(message);
  if (event?.kind != 'notification' || event?.notification == null) return;
  final store = inbox ?? await NotificationInbox.open();
  final received =
      await store.ingestLive(instance.url, event!.notification!, now: now);
  await presentNotifications(instance, store, received);
}

Future<void> presentNotifications(Instance instance, NotificationInbox inbox,
    List<Map<String, dynamic>> received,
    {bool background = false}) async {
  if (received.isEmpty) return;
  if (!background && notificationAppForeground) {
    for (final event in received) {
      final payload = notificationDestination(instance.url, event);
      if (!suppressVisibleNotification(payload)) {
        foregroundNotifications.add(payload);
      }
    }
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final enabled = prefs.getBool('notif_enabled') ?? false;
  if (!enabled || (background && await inbox.foregroundActive())) return;
  for (final event in received) {
    await prefs.reload();
    if (!(prefs.getBool('notif_enabled') ?? false) ||
        (background && await inbox.foregroundActive())) return;
    final payload = notificationDestination(instance.url, event);
    if (suppressVisibleNotification(payload)) continue;
    final content = notificationContent(instance, event);
    try {
      await notifySessionEvent(
          notificationId: await inbox.alertId(event['notification_id'] as String),
          title: content.head,
          body: content.body,
          payload: jsonEncode(payload),
          kind: event['kind']?.toString() ?? '');
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'notification presentation'));
    }
  }
}

Future<void> syncSavedNotifications({bool background = false}) async {
  Object? failure;
  StackTrace? trace;
  for (final instance in await InstanceStore().load()) {
    try {
      await syncNotificationInstance(instance, background: background);
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, trace!);
}
