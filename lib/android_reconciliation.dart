import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_sync.dart';
import 'notifications.dart';

const androidReconciliationTask = 'snippet.android.deferred_reconciliation';
const _reconciliationWorkName = 'snippet_android_deferred_reconciliation';
const androidReconciliationInterval = Duration(minutes: 15);

@pragma('vm:entry-point')
void androidReconciliationCallback() {
  Workmanager().executeTask((task, _) async {
    if (task != androidReconciliationTask) return true;
    try {
      await reconcileAndroidNotificationState();
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> scheduleAndroidReconciliation() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await Workmanager().initialize(androidReconciliationCallback);
  if (!await notificationsEnabled()) {
    await Workmanager().cancelByUniqueName(_reconciliationWorkName);
    return;
  }
  await Workmanager().registerPeriodicTask(
      _reconciliationWorkName, androidReconciliationTask,
      frequency: androidReconciliationInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update);
}

Future<void> reconcileAndroidNotificationState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!(prefs.getBool('notif_enabled') ?? false)) return;
  await initializeNotificationBackgroundIsolate();
  await syncSavedNotifications(background: true);
}

Set<String> newlyObservedSessionIds(
    Iterable<String> previous, Iterable<String> current) {
  final old = previous.toSet();
  return current.where((id) => !old.contains(id)).toSet();
}
