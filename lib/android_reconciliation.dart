import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'models.dart';
import 'notifications.dart';
import 'store.dart';

final _backgroundNotifications = FlutterLocalNotificationsPlugin();

const androidReconciliationTask = 'snippet.android.deferred_reconciliation';
const _reconciliationWorkName = 'snippet_android_deferred_reconciliation';
const _snapshotPrefix = 'android_reconciliation_snapshot:';
const _cursorPrefix = 'android_reconciliation_cursor:';

String notificationCursorKey(String instanceUrl) =>
    '$_cursorPrefix$instanceUrl';

Future<void> advanceNotificationCursor(
    SharedPreferences prefs, String instanceUrl, int eventId) async {
  if (eventId <= 0) return;
  final key = notificationCursorKey(instanceUrl);
  final current = prefs.getInt(key) ?? 0;
  if (eventId > current) await prefs.setInt(key, eventId);
}

/// WorkManager's minimum periodic interval is 15 minutes. Thirty minutes is
/// deliberate: this is a deferred catch-up path, not a replacement for the
/// foreground/event watcher, and it avoids keeping a socket or foreground
/// service alive solely for notifications.
const androidReconciliationInterval = Duration(minutes: 30);

@pragma('vm:entry-point')
void androidReconciliationCallback() {
  Workmanager().executeTask((task, _) async {
    if (task != androidReconciliationTask) return true;
    try {
      await reconcileAndroidNotificationState();
      return true;
    } catch (_) {
      // Returning false lets WorkManager apply its normal retry policy.
      return false;
    }
  });
}

/// Register idempotently. This is intentionally Android-only; callers should
/// invoke it from Android startup, never from desktop notification setup.
Future<void> scheduleAndroidReconciliation() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await Workmanager().initialize(androidReconciliationCallback);
  await Workmanager().registerPeriodicTask(
    _reconciliationWorkName,
    androidReconciliationTask,
    frequency: androidReconciliationInterval,
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Read each saved daemon's current session list and persist a compact id
/// snapshot. Notification delivery/diff policy is deliberately left to the
/// next layer; this gives it a process-independent, retryable reconciliation
/// boundary without FCM or daemon changes.
Future<void> reconcileAndroidNotificationState() async {
  await initializeNotificationBackgroundIsolate(_backgroundNotifications);
  final instances = await InstanceStore().load();
  final prefs = await SharedPreferences.getInstance();
  for (final instance in instances) {
    final client = DaemonClient(instance.url, instance.token);
    final cursorKey = notificationCursorKey(instance.url);
    final since = prefs.getInt(cursorKey) ?? 0;
    final events = await client.notificationReplay(since: since);
    for (final event in events) {
      final eventId = (event['event_id'] as num?)?.toInt() ?? 0;
      if (eventId <= 0) continue;
      final kind = event['kind']?.toString() ?? '';
      final content = notificationContent(instance, event);
      await notifySessionEvent(
        title: content.head,
        body: content.body,
        payload: content.payload,
        kind: kind,
        notificationId: eventId,
        plugin: _backgroundNotifications,
      );
      await advanceNotificationCursor(prefs, instance.url, eventId);
    }
  }
}

/// Pure diff helper for the eventual notification policy and unit tests.
Set<String> newlyObservedSessionIds(
    Iterable<String> previous, Iterable<String> current) {
  final oldIds = previous.toSet();
  return current.where((id) => !oldIds.contains(id)).toSet();
}
