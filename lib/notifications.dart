import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_reconciliation.dart';
import 'notification_sync.dart';
import 'notification_inbox.dart';
import 'file_actions.dart';
import 'models.dart';
import 'platform.dart';

const _alertChannel = 'snippet_alerts';
const _downloadChannel = 'snippet_downloads';
const _prefEnabled = 'notif_enabled';

int _downloadNotifId = 0;
const _cancelDownloadAction = 'cancel_download';
final Map<int, VoidCallback> _downloadCancels = {};

void registerDownloadCancel(int? id, VoidCallback cancel) {
  if (id != null) _downloadCancels[id] = cancel;
}

void unregisterDownloadCancel(int? id) {
  if (id != null) _downloadCancels.remove(id);
}

// The download stream reports progress synchronously, but each native
// notification update is asynchronous. Serialize updates so a final
// "complete" or "failed" state cannot be overwritten by a late progress
// update for the same notification id.
Future<void> _downloadNotifQueue = Future<void>.value();

Future<T> _enqueueDownloadNotification<T>(Future<T> Function() action) {
  final next = _downloadNotifQueue.then((_) => action());
  // Keep the queue usable after a platform notification error while still
  // returning that error to the current caller.
  _downloadNotifQueue = next.then<void>(
    (_) {},
    onError: (Object error, StackTrace stack) {},
  );
  return next;
}

Future<void> _ensureDownloadPermission() async {
  if (!kMobile) return;
  final android = _mainNotif.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    await android?.requestNotificationsPermission();
  } catch (_) {}
}

/// Start a native download-progress notification. Returns its stable id.
Future<int?> notifyDownloadStarted(String name,
    {VoidCallback? onCancel}) async {
  if (!kCanNotify || !kMobile) return null;
  await _ensureDownloadPermission();
  final id = -1 - (_downloadNotifId++ & 0x7fffffff);
  if (onCancel != null) registerDownloadCancel(id, onCancel);
  await _enqueueDownloadNotification(() => _mainNotif.show(
        id: id,
        title: 'Downloading',
        body: name,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _downloadChannel,
            'Downloads',
            channelDescription: 'Files saved from a session',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: true,
            showProgress: true,
            maxProgress: 100,
            progress: 0,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                _cancelDownloadAction,
                'Cancel',
                cancelNotification: true,
              ),
            ],
          ),
        ),
        payload: jsonEncode({'type': 'download_progress', 'name': name}),
      ));
  return id;
}

Future<void> notifyDownloadProgress(int? id, String name, int progress) async {
  if (id == null || !kCanNotify || !kMobile) return;
  await _enqueueDownloadNotification(() => _mainNotif.show(
        id: id,
        title: 'Downloading',
        body: '$name · $progress%',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _downloadChannel,
            'Downloads',
            channelDescription: 'Files saved from a session',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: true,
            showProgress: true,
            maxProgress: 100,
            progress: progress,
            actions: const <AndroidNotificationAction>[
              AndroidNotificationAction(
                _cancelDownloadAction,
                'Cancel',
                cancelNotification: true,
              ),
            ],
          ),
        ),
      ));
}

Future<void> notifyDownloadCancelled(int? id) async {
  if (id == null || !kCanNotify || !kMobile) return;
  await _enqueueDownloadNotification(() => _mainNotif.cancel(id: id));
}

Future<void> notifyDownloadFailure(int? id, String name, Object error) async {
  if (id == null || !kCanNotify || !kMobile) return;
  await _enqueueDownloadNotification(() async {
    await _mainNotif.cancel(id: id);
    await _mainNotif.show(
      id: id,
      title: 'Download failed',
      body: '$name: $error',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannel,
          'Downloads',
          channelDescription: 'Files saved from a session',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          ongoing: false,
          showProgress: false,
        ),
      ),
    );
  });
}

/// Show a native "download complete" notification; tapping it opens the file.
Future<void> notifyDownload(String name, String filePath, {int? id}) async {
  if (!kCanNotify) return;
  await _enqueueDownloadNotification(() async {
    if (id != null) await _mainNotif.cancel(id: id);
    await _mainNotif.show(
      id: id ?? (_downloadNotifId++ & 0x7fffffff),
      title: 'Download complete',
      body: name,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannel,
          'Downloads',
          channelDescription: 'Files saved from a session',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          ongoing: false,
          showProgress: false,
        ),
        macOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode({'type': 'download', 'path': filePath}),
    );
  });
}

Future<void> notifySessionEvent({
  required String title,
  required String body,
  required String payload,
  required String kind,
  required int notificationId,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  if (!kCanNotify || !kMobile) return;
  final important = kind == 'waiting' || kind == 'error';
  await (plugin ?? _mainNotif).show(
    id: notificationId,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannel,
        'Session activity',
        channelDescription: 'Important activity on connected machines',
        importance: important ? Importance.high : Importance.defaultImportance,
        priority: important ? Priority.high : Priority.defaultPriority,
        category: AndroidNotificationCategory.message,
        onlyAlertOnce: true,
      ),
    ),
    payload: payload,
  );
}

/// Routed from a tapped notification (set by main with a navigator).
void Function(Map<String, dynamic> payload)? onNotifTap;

final FlutterLocalNotificationsPlugin _mainNotif =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeAndroidNotifications(
    FlutterLocalNotificationsPlugin plugin) async {
  await plugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
}

/// Initialize the notification plugin in whichever isolate is running. Android
/// WorkManager callbacks run in a background isolate and cannot use the main
/// isolate's initialization state.
Future<void> initializeNotificationBackgroundIsolate(
    [FlutterLocalNotificationsPlugin? plugin]) async {
  if (!kMobile) return;
  await _initializeAndroidNotifications(plugin ?? _mainNotif);
}

/// Build the device-wide events WebSocket URI for an instance.
Uri eventsUri(String baseUrl, String token) {
  final u = Uri.parse(baseUrl);
  return u.replace(
    scheme: u.scheme == 'https' ? 'wss' : 'ws',
    path: '/events',
    queryParameters: {'token': token},
  );
}

// ---------------------------------------------------------------------------
// Main-isolate setup: foreground-task config + tap routing + launch handling.
// ---------------------------------------------------------------------------
Future<void> initNotifications() async {
  if (kMobile) {
    await _mainNotif.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.actionId == _cancelDownloadAction) {
          _downloadCancels[resp.id]?.call();
          return;
        }
        final p = resp.payload;
        if (p != null) _route(p);
      },
    );
    // Cold start from a tapped notification.
    final launch = await _mainNotif.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final p = launch!.notificationResponse?.payload;
      if (p != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _route(p));
      }
    }
    return;
  }
  // Desktop (macOS/Linux): just init the local-notifications plugin + tap routing.

  if (!kDesktopNotify) return;
  await _mainNotif.initialize(
    settings: const InitializationSettings(
      macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    ),
    onDidReceiveNotificationResponse: (resp) {
      final p = resp.payload;
      if (p != null) _route(p);
    },
  );
}

/// Display content for a durable notification.
({String head, String body, String payload}) notificationContent(
    Instance inst, Map<String, dynamic> e) {
  final session = e['session']?.toString() ?? '';
  final title = e['title']?.toString() ?? 'session';
  final message = e['message']?.toString() ?? '';
  final (String head, String body) = switch (e['kind']?.toString()) {
    'waiting' => ('${inst.label} needs your input', title),
    'done' => ('${inst.label} finished', title),
    'error' => ('${inst.label} hit an error', title),
    'idle' => ('${inst.label} stopped', title),
    'term' => (
        message.isEmpty ? '${inst.label} · $title' : message,
        message.isEmpty ? 'Terminal' : title,
      ),
    _ => (inst.label, title),
  };
  // No token in the payload: the OS persists notification records and exposes
  // them to listeners — the tap handler re-resolves the token from the store.
  final payload = jsonEncode({
    'url': inst.url,
    'name': inst.label,
    'session': session,
    'title': title
  });
  return (head: head, body: body, payload: payload);
}

void _route(String payload) {
  try {
    final m = jsonDecode(payload) as Map<String, dynamic>;
    // A download notification opens the saved file directly, not a session.
    if (m['type'] == 'download') {
      final path = m['path'] as String?;
      if (path != null) openLocalFile(path);
      return;
    }
    onNotifTap?.call(m);
  } catch (_) {}
}

Future<bool> notificationsEnabled() async {
  if (!kCanNotify) return false;
  final sp = await SharedPreferences.getInstance();
  return sp.getBool(_prefEnabled) ?? false;
}

/// Enable/disable session watching. Returns an error string, or null on success.
Future<String?> setNotificationsEnabled(bool on) async {
  if (!kCanNotify) return 'Notifications are not supported here.';
  final sp = await SharedPreferences.getInstance();
  if (on) {
    final error = await startWatching();
    if (error != null) return error;
  }
  await sp.setBool(_prefEnabled, on);
  await scheduleAndroidReconciliation();
  return null;
}

/// Start the watcher (idempotent). Returns an error string or null.
Future<String?> startWatching() async {
  if (kMobile) {
    final android = _mainNotif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (await android?.requestNotificationsPermission() == false)
      return 'Notification permission denied.';
    unawaited(syncSavedNotifications().catchError((Object _) {}));
    return null;
  }
  return 'Notifications are not supported here.';
}

/// Resume the watcher on app launch if the user had it enabled.
Future<void> resumeWatchingIfEnabled() async {
  if (!kCanNotify) return;
  if (await notificationsEnabled()) {
    await startWatching();
  }
}

// Tell the watcher whether the app is foreground and which session is open, so it
// can suppress a notification the user is already looking at.
Timer? _foregroundHeartbeat;
Future<void> _foregroundWrites = Future<void>.value();

void _writeForegroundLease() {
  final fg = notificationAppForeground;
  final key = fg ? visibleNotificationSession.value : null;
  _foregroundWrites = _foregroundWrites.catchError((Object _) {}).then(
      (_) async => (await NotificationInbox.open()).setForeground(fg, visibleKey: key));
  unawaited(_foregroundWrites.catchError((Object _) {}));
}

void reportVisibleNotificationSession(String? instance, String? session) {
  final key = notificationAppForeground && instance != null && session != null
      ? notificationSessionKey(instance, session)
      : null;
  if (visibleNotificationSession.value == key) return;
  visibleNotificationSession.value = key;
  if (kMobile) _writeForegroundLease();
}

void reportForeground(bool fg) {
  notificationAppForeground = fg;
  if (!fg) visibleNotificationSession.value = null;
  if (kMobile) {
    _foregroundHeartbeat?.cancel();
    _writeForegroundLease();
    if (fg) {
      _foregroundHeartbeat = Timer.periodic(const Duration(seconds: 20),
          (_) => _writeForegroundLease());
    }
  }
  if (fg) unawaited(syncSavedNotifications().catchError((Object _) {}));
}
