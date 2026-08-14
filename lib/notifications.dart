import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'file_actions.dart';
import 'models.dart';
import 'platform.dart';
import 'store.dart';

const _fgChannel = 'snippet_fg';
const _alertChannel = 'snippet_alerts';
const _downloadChannel = 'snippet_downloads';
const _prefEnabled = 'notif_enabled';

int _downloadNotifId = 7000;
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
Future<int?> notifyDownloadStarted(String name) async {
  if (!kCanNotify || !kMobile) return null;
  await _ensureDownloadPermission();
  final id = _downloadNotifId++ & 0x7fffffff;
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

/// Routed from a tapped notification (set by main with a navigator).
void Function(Map<String, dynamic> payload)? onNotifTap;

final FlutterLocalNotificationsPlugin _mainNotif =
    FlutterLocalNotificationsPlugin();

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
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _fgChannel,
        channelName: 'Background watcher',
        channelDescription: 'Keeps watching your sessions for activity.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
      ),
    );

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
  // The /events watcher runs in-process (see _DesktopWatcher), no service needed.
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

/// Head/body/payload for a /events frame — shared by the mobile task handler and
/// the desktop watcher so they stay in sync.
({String head, String body, String payload}) _notifContent(
    Instance inst, Map<String, dynamic> e) {
  final session = e['session']?.toString() ?? '';
  final title = e['title']?.toString() ?? 'session';
  final (String head, String body) = switch (e['kind']?.toString()) {
    'waiting' => ('${inst.label} needs your input', title),
    'done' => ('${inst.label} finished', title),
    'error' => ('${inst.label} hit an error', title),
    'idle' => ('${inst.label} stopped', title),
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
  await sp.setBool(_prefEnabled, on);
  if (!on) {
    if (kMobile) {
      await FlutterForegroundTask.stopService();
    } else {
      _watcher?.stop();
      _watcher = null;
    }
    return null;
  }
  return startWatching();
}

/// Start the watcher (idempotent). Returns an error string or null.
Future<String?> startWatching() async {
  if (kMobile) {
    var perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      perm = await FlutterForegroundTask.requestNotificationPermission();
      if (perm != NotificationPermission.granted) {
        return 'Notification permission denied.';
      }
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 4317,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'snippet',
        notificationText: 'Watching your sessions',
        callback: startNotificationCallback,
      );
    }
    return null;
  }
  if (!kDesktopNotify) return 'Notifications are not supported here.';
  // macOS asks for permission the first time; Linux needs none.
  final mac = _mainNotif.resolvePlatformSpecificImplementation<
      MacOSFlutterLocalNotificationsPlugin>();
  if (mac != null) {
    final ok = await mac.requestPermissions(alert: true, sound: true);
    if (ok == false) return 'Notification permission denied.';
  }
  _watcher ??= _DesktopWatcher();
  await _watcher!.start();
  return null;
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
void reportForeground(bool fg) {
  if (kMobile) {
    try {
      FlutterForegroundTask.sendDataToTask({'fg': fg});
    } catch (_) {}
    return;
  }
  _watcher?.setForeground(fg);
}

void reportOpenSession(String? key) {
  if (kMobile) {
    try {
      FlutterForegroundTask.sendDataToTask({'open': key ?? ''});
    } catch (_) {}
    return;
  }
  _watcher?.setOpen(key ?? '');
}

// ---------------------------------------------------------------------------
// Desktop (macOS/Linux): in-process /events watcher — one WS per instance,
// raising native local notifications. No background service; the app is running.
// ---------------------------------------------------------------------------
_DesktopWatcher? _watcher;

class _DesktopWatcher {
  final Map<String, WebSocketChannel> _channels = {};
  List<Instance> _instances = const [];
  bool _fg = true;
  String _open = '';
  int _nid = 5000;
  Timer? _reconnect;
  bool _running = false;

  Future<void> start() async {
    _running = true;
    _instances = await InstanceStore().load();
    _connectAll();
    // Reload the instance list each cycle — machines added after start must
    // notify, removed ones must stop (their stale channels are pruned).
    _reconnect ??= Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_running) return;
      _instances = await InstanceStore().load();
      if (!_running) return;
      _pruneRemoved();
      _connectAll();
    });
  }

  void _pruneRemoved() {
    final live = _instances.map((i) => i.url).toSet();
    _channels.removeWhere((url, ch) {
      if (live.contains(url)) return false;
      ch.sink.close();
      return true;
    });
  }

  void stop() {
    _running = false;
    _reconnect?.cancel();
    _reconnect = null;
    for (final c in _channels.values) {
      c.sink.close();
    }
    _channels.clear();
  }

  void setForeground(bool fg) => _fg = fg;
  void setOpen(String key) => _open = key;

  void _connectAll() {
    for (final inst in _instances) {
      if (_channels.containsKey(inst.url)) continue;
      try {
        final ch = WebSocketChannel.connect(eventsUri(inst.url, inst.token));
        _channels[inst.url] = ch;
        ch.stream.listen(
          (msg) => _onEvent(inst, msg),
          onDone: () => _channels.remove(inst.url),
          onError: (_) => _channels.remove(inst.url),
          cancelOnError: true,
        );
      } catch (_) {}
    }
  }

  void _onEvent(Instance inst, dynamic msg) {
    Map<String, dynamic> e;
    try {
      e = jsonDecode(msg as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final session = e['session']?.toString() ?? '';
    if (_fg && '${inst.url}|$session' == _open) return; // already on screen
    final c = _notifContent(inst, e);
    _mainNotif.show(
      id: _nid++,
      title: c.head,
      body: c.body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      payload: c.payload,
    );
  }
}

// ---------------------------------------------------------------------------
// Task isolate: hold one /events WS per instance, raise local notifications.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
void startNotificationCallback() =>
    FlutterForegroundTask.setTaskHandler(_NotifTaskHandler());

class _NotifTaskHandler extends TaskHandler {
  final _notif = FlutterLocalNotificationsPlugin();
  final Map<String, WebSocketChannel> _channels = {};
  List<Instance> _instances = const [];
  bool _fg = false;
  String _open = '';
  int _nid = 1000;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notif.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _instances = await InstanceStore().load();
    _connectAll();
  }

  void _connectAll() {
    for (final inst in _instances) {
      if (_channels.containsKey(inst.url)) continue;
      try {
        final ch = WebSocketChannel.connect(eventsUri(inst.url, inst.token));
        _channels[inst.url] = ch;
        ch.stream.listen(
          (msg) => _onEvent(inst, msg),
          onDone: () => _channels.remove(inst.url),
          onError: (_) => _channels.remove(inst.url),
          cancelOnError: true,
        );
      } catch (_) {}
    }
  }

  void _onEvent(Instance inst, dynamic msg) {
    Map<String, dynamic> e;
    try {
      e = jsonDecode(msg as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final session = e['session']?.toString() ?? '';
    if (_fg && '${inst.url}|$session' == _open) return; // already on screen
    final title = e['title']?.toString() ?? 'session';
    final (String head, String body) = switch (e['kind']?.toString()) {
      'waiting' => ('${inst.label} needs your input', title),
      'done' => ('${inst.label} finished', title),
      'error' => ('${inst.label} hit an error', title),
      'idle' => ('${inst.label} stopped', title),
      _ => (inst.label, title),
    };
    _notif.show(
      id: _nid++,
      title: head,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannel,
          'Session activity',
          channelDescription: 'Activity on your connected machines',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // No token here — see _notifContent; the tap handler resolves it from the store.
      payload: jsonEncode({
        'url': inst.url,
        'name': inst.label,
        'session': session,
        'title': title,
      }),
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final fg = data['fg'];
      final open = data['open'];
      if (fg is bool) _fg = fg;
      if (open is String) _open = open;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Reload instances each cycle (added machines start notifying, removed ones
    // stop), then reconnect any dropped channels.
    InstanceStore().load().then((items) {
      _instances = items;
      final live = _instances.map((i) => i.url).toSet();
      _channels.removeWhere((url, ch) {
        if (live.contains(url)) return false;
        ch.sink.close();
        return true;
      });
      _connectAll();
    }).catchError((_) {
      _connectAll();
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    for (final ch in _channels.values) {
      ch.sink.close();
    }
    _channels.clear();
  }
}
