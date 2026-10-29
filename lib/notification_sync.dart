import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'call_tracking.dart';
import 'device_events.dart';
import 'macos_notch.dart';
import 'models.dart';
import 'notification_inbox.dart';
import 'notifications.dart';
import 'store.dart';
import 'platform.dart';

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
        notificationSessionKey(
            payload['url'] as String, payload['session'] as String);
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
    if (!background) unawaited(callTracker.refresh(key, client));
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
  received = await _takeCallEvents(instance, received, background);
  if (received.isEmpty) return;
  if (!background && (notificationAppForeground || kMacOS)) {
    for (final event in received) {
      final payload = notificationDestination(instance.url, event);
      if (kMacOS) {
        final content = notificationContent(instance, event);
        MacosNotch.showNotification(
          title: payload['title']?.toString() ?? content.head,
          subtitle: payload['body']?.toString() ?? content.body,
          kind: payload['kind']?.toString() ?? '',
          payload: payload,
        );
      }
      if (!suppressVisibleNotification(payload)) {
        foregroundNotifications.add(payload);
      }
    }
    // The notch banner is transient; a waiting request also persists here.
    if (kMacOS && !notificationAppForeground) {
      await _postMacCentre(instance, inbox, received);
    }
    return;
  }
  if (!kMobile) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final enabled = prefs.getBool('notif_enabled') ?? false;
  if (!enabled || (background && await inbox.foregroundActive())) return;
  for (final event in received) {
    await prefs.reload();
    if (!(prefs.getBool('notif_enabled') ?? false) ||
        (background && await inbox.foregroundActive())) {
      return;
    }
    final payload = notificationDestination(instance.url, event);
    if (suppressVisibleNotification(payload)) continue;
    final content = notificationContent(instance, event);
    try {
      await notifySessionEvent(
          notificationId:
              await inbox.alertId(event['notification_id'] as String),
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

Future<void> _postMacCentre(Instance instance, NotificationInbox inbox,
    List<Map<String, dynamic>> received) async {
  for (final event in received) {
    final kind = event['kind']?.toString() ?? '';
    if (kind != 'waiting' && kind != 'error') continue;
    final payload = notificationDestination(instance.url, event);
    final content = notificationContent(instance, event);
    try {
      await notifySessionEvent(
          notificationId:
              await inbox.alertId(event['notification_id'] as String),
          title: content.head,
          body: content.body,
          payload: jsonEncode(payload),
          kind: kind);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'notification presentation'));
    }
  }
}

/// Peels call_prompt / call_state events off the batch and returns the rest.
Future<List<Map<String, dynamic>>> _takeCallEvents(Instance instance,
    List<Map<String, dynamic>> received, bool background) async {
  final rest = <Map<String, dynamic>>[];
  for (final event in received) {
    final call = parseCallEvent(event);
    if (call == null) {
      rest.add(event);
      continue;
    }
    await presentCallEvent(instance, call, background: background);
  }
  return rest;
}

Future<void> presentCallEvent(Instance instance, CallEvent call,
    {bool background = false}) async {
  if (!call.isPrompt) {
    callTracker.apply(instance.url, call);
    await cancelCallPrompt(call.callId);
    return;
  }
  final inApp = !background && (notificationAppForeground || kMacOS);
  if (inApp) {
    callTracker.apply(instance.url, call);
    return;
  }
  if (!kMobile) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!(prefs.getBool('notif_enabled') ?? false)) return;
  try {
    await notifyCallPrompt(url: instance.url, event: call);
  } catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
        exception: error, stack: stack, library: 'call prompt'));
  }
}
