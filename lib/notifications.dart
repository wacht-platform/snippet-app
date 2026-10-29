import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_reconciliation.dart';
import 'call_tracking.dart';
import 'notification_sync.dart';
import 'notification_inbox.dart';
import 'file_actions.dart';
import 'models.dart';
import 'platform.dart';
import 'session_quick_send.dart';

const _alertChannel = 'snippet_updates';
const _needsInputChannel = 'snippet_needs_input';
const _summaryId = 2147483600;
const _actionApprove = 'approve';
const _actionDeny = 'deny';
const _actionReply = 'reply';
const _actionCallTrack = 'call_track';
const _actionCallIgnore = 'call_ignore';
const _callChannel = 'snippet_call';
const _androidGroupPrefix = 'snippet_machine_';
final Map<String, int> _machineSummaryIds = {};
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
  if ((!kMobile && !kMacOS) || (!kCanNotify && !kMacOS)) return;
  final data = jsonDecode(payload) as Map<String, dynamic>;
  final notifier = plugin ?? _mainNotif;
  final session = _sessionOf(data);
  if (session.isNotEmpty) {
    notificationId = sessionNotificationId(_machineOf(data), session);
  }
  MessagingStyleInformation? priorStyle;
  if (kMobile && _sessionOf(data).isNotEmpty) {
    try {
      priorStyle = await notifier
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getActiveNotificationMessagingStyle(id: notificationId);
    } catch (_) {}
  }
  final details = sessionNotificationDetails(
      payload: data,
      title: title,
      body: body,
      kind: kind,
      previous: priorStyle);
  await notifier.show(
      id: notificationId,
      title: title,
      body: plainNotificationText(body),
      notificationDetails: details,
      payload: payload);
  if (kMobile) {
    final group = details.android!.groupKey!;
    final summaryId = _machineSummaryIds.putIfAbsent(
        group, () => _summaryId - _machineSummaryIds.length - 1);
    await notifier.show(
        id: summaryId,
        title: data['name']?.toString() ?? 'Snippet',
        body: 'Session updates',
        notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(_alertChannel, 'Updates',
                groupKey: group,
                setAsGroupSummary: true,
                onlyAlertOnce: true)));
  }
}

/// Stable across launches (unlike String.hashCode) so a chat keeps one
/// notification that accumulates messages.
int sessionNotificationId(String machine, String session) {
  var h = 0x811c9dc5;
  for (final c in '$machine|$session'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return 0x40000000 | (h & 0x3fffffff);
}

String _sessionOf(Map<String, dynamic> data) {
  final dest = data['destination'];
  return '${data['session'] ?? (dest is Map ? dest['session'] ?? dest['id'] : '') ?? ''}';
}

String _machineOf(Map<String, dynamic> data) =>
    '${data['url'] ?? data['name'] ?? 'snippet'}';

String plainNotificationText(String value) {
  var text = value.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1] ?? '');
  text = text.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  text = text
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'[*_~>#]'), '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

NotificationDetails sessionNotificationDetails(
    {required Map<String, dynamic> payload,
    required String title,
    required String body,
    required String kind,
    MessagingStyleInformation? previous}) {
  final attn = payload['attention'];
  final type = attn is Map ? attn['type'] : null;
  final waiting = kind == 'waiting';
  final actions = <AndroidNotificationAction>[];
  if (waiting && type == 'approval') {
    actions.addAll(const [
      AndroidNotificationAction(_actionApprove, 'Approve',
          cancelNotification: false),
      AndroidNotificationAction(_actionDeny, 'Deny', cancelNotification: false)
    ]);
  } else if (waiting || kind == 'message') {
    actions.add(const AndroidNotificationAction(_actionReply, 'Reply',
        cancelNotification: false,
        inputs: [AndroidNotificationActionInput(label: 'Reply')]));
  }
  final group = '$_androidGroupPrefix${_machineOf(payload)}';
  final session = _sessionOf(payload);
  final lines = plainNotificationText(body).split('\n');
  final preview = lines.take(2).join(' ');
  final channel = waiting ? _needsInputChannel : _alertChannel;
  final category = waiting && type == 'approval'
      ? 'approval'
      : waiting && type == 'question'
          ? 'question'
          : 'message';
  return NotificationDetails(
    android: AndroidNotificationDetails(
        channel, waiting ? 'Needs input' : 'Updates',
        channelDescription:
            waiting ? 'Sessions waiting for your input' : 'Session activity',
        importance: waiting ? Importance.high : Importance.defaultImportance,
        priority: waiting ? Priority.high : Priority.defaultPriority,
        category: AndroidNotificationCategory.message,
        groupKey: group,
        onlyAlertOnce: true,
        actions: actions,
        styleInformation: MessagingStyleInformation(_snippetPerson,
            conversationTitle: title,
            groupConversation: false,
            messages: [
              ...?previous?.messages,
              Message(preview, DateTime.now(), _snippetPerson)
            ].take(10).toList())),
    macOS: DarwinNotificationDetails(
        threadIdentifier: session.isEmpty ? null : session,
        categoryIdentifier: category,
        interruptionLevel: waiting
            ? InterruptionLevel.timeSensitive
            : (kind == 'done' || kind == 'idle'
                ? InterruptionLevel.passive
                : InterruptionLevel.active)),
  );
}

const _snippetPerson = Person(
    name: 'Snippet',
    key: 'snippet',
    bot: true,
    icon: DrawableResourceAndroidIcon('notification_avatar'));

Future<bool> routeNotificationAction(
    {required String? actionId,
    required String? input,
    required String? payload}) async {
  if (actionId == null || payload == null) return false;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return false;
  }
  if (data['type'] == callPromptType) {
    return switch (actionId) {
      _actionCallTrack => callActionForPayload(data, callActionTrack),
      _actionCallIgnore => callActionForPayload(data, callActionIgnore),
      _ => Future.value(false),
    };
  }
  final attn = data['attention'];
  final question = attn is Map && attn['type'] == 'question';
  final text = input?.trim() ?? '';
  final QuickAction? action = switch (actionId) {
    _actionApprove => const QuickApprove(),
    _actionDeny => const QuickDeny(),
    _actionReply when text.isNotEmpty =>
      question ? QuickAnswer(text) : QuickReply(text),
    _ => null,
  };
  return action == null ? false : quickSendForPayload(data, action);
}

bool _isQuickActionId(String? id) => const {
      _actionApprove,
      _actionDeny,
      _actionReply,
      _actionCallTrack,
      _actionCallIgnore,
    }.contains(id);

/// Heads-up prompt that vanishes when the daemon's 120 s window closes.
Future<void> notifyCallPrompt({
  required String url,
  required CallEvent event,
  int? nowMs,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  if (!kMobile || !kCanNotify) return;
  final remaining = event.expiresAtMs -
      (nowMs ?? DateTime.now().millisecondsSinceEpoch);
  if (event.expiresAtMs > 0 && remaining <= 0) return;
  await (plugin ?? _mainNotif).show(
    id: callNotificationId(event.callId),
    title: event.title,
    body: event.body,
    notificationDetails: callPromptDetails(timeoutMs: remaining),
    payload: jsonEncode({
      'type': callPromptType,
      'url': url,
      'call_id': event.callId,
      'expires_at': event.expiresAtMs,
    }),
  );
}

NotificationDetails callPromptDetails({required int timeoutMs}) =>
    NotificationDetails(
      android: AndroidNotificationDetails(_callChannel, 'Calls',
          channelDescription: 'Asks before Snippet takes notes on a call',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          timeoutAfter: timeoutMs > 0 ? timeoutMs : null,
          autoCancel: false,
          actions: const [
            AndroidNotificationAction(_actionCallTrack, 'Track',
                cancelNotification: false),
            AndroidNotificationAction(_actionCallIgnore, 'Ignore',
                cancelNotification: false),
          ]),
    );

Future<void> cancelCallPrompt(String callId,
    {FlutterLocalNotificationsPlugin? plugin}) async {
  if (!kMobile || !kCanNotify) return;
  try {
    await (plugin ?? _mainNotif).cancel(id: callNotificationId(callId));
  } catch (_) {}
}

@pragma('vm:entry-point')
void notificationBackgroundResponse(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();
  if (await routeNotificationAction(
      actionId: response.actionId,
      input: response.input,
      payload: response.payload)) {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    if (response.id != null) await plugin.cancel(id: response.id!);
  }
}

/// Routed from a tapped notification (set by main with a navigator).
void Function(Map<String, dynamic> payload)? onNotifTap;

final _darwinCategories = <DarwinNotificationCategory>[
  DarwinNotificationCategory('approval', actions: [
    DarwinNotificationAction.plain(_actionApprove, 'Approve'),
    DarwinNotificationAction.plain(_actionDeny, 'Deny')
  ]),
  DarwinNotificationCategory('question', actions: [
    DarwinNotificationAction.text(_actionReply, 'Reply',
        buttonTitle: 'Send', placeholder: 'Answer')
  ]),
  DarwinNotificationCategory('message', actions: [
    DarwinNotificationAction.text(_actionReply, 'Reply',
        buttonTitle: 'Send', placeholder: 'Reply')
  ]),
];
final FlutterLocalNotificationsPlugin _mainNotif =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeAndroidNotifications(
    FlutterLocalNotificationsPlugin plugin) async {
  await plugin.initialize(
    settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
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
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundResponse,
      onDidReceiveNotificationResponse: (resp) async {
        if (resp.actionId == _cancelDownloadAction) {
          _downloadCancels[resp.id]?.call();
          return;
        }
        if (_isQuickActionId(resp.actionId)) {
          if (await routeNotificationAction(
                  actionId: resp.actionId,
                  input: resp.input,
                  payload: resp.payload) &&
              resp.id != null) {
            await _mainNotif.cancel(id: resp.id!);
          }
          return;
        }
        final p = resp.payload;
        if (p != null) _route(p);
      },
    );
    String? shownCall;
    callTracker.state.addListener(() {
      final c = callTracker.state.value;
      if (c != null && c.phase == CallPhase.pending) {
        shownCall = c.callId;
      } else if (shownCall != null) {
        unawaited(cancelCallPrompt(shownCall!));
        shownCall = null;
      }
    });
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
    settings: InitializationSettings(
      macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: _darwinCategories),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    ),
    onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
    onDidReceiveNotificationResponse: (resp) async {
      if (_isQuickActionId(resp.actionId)) {
        if (await routeNotificationAction(
                actionId: resp.actionId,
                input: resp.input,
                payload: resp.payload) &&
            resp.id != null) {
          await _mainNotif.cancel(id: resp.id!);
        }
      } else if (resp.payload != null) {
        _route(resp.payload!);
      }
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
    'idle' => (title.isEmpty ? 'Session' : title, stoppedSummary(e['lanes_running'])),
    'ping' => (title.isEmpty ? 'Mission Control' : title, message),
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
    'title': title,
    'kind': e['kind'],
    'attention': e['attention'],
    'notification_id': e['notification_id'],
    'destination': e['destination'],
    'message': message,
  });
  return (head: head, body: body, payload: payload);
}

String stoppedSummary(Object? lanes) {
  final names = lanes is List
      ? lanes.map((l) => l.toString().trim()).where((l) => l.isNotEmpty).toList()
      : const <String>[];
  if (names.isEmpty) return 'Done for now';
  if (names.length == 1) return 'Paused while a lane works: ${names.first}';
  final shown = names.take(2).join(', ');
  final rest = names.length > 2 ? ' +${names.length - 2}' : '';
  return 'Paused while ${names.length} lanes work: $shown$rest';
}

void _route(String payload) {
  try {
    final m = jsonDecode(payload) as Map<String, dynamic>;
    if (m['type'] == callPromptType) return;
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
    if (await android?.requestNotificationsPermission() == false) {
      return 'Notification permission denied.';
    }
    await android?.createNotificationChannel(const AndroidNotificationChannel(
        _needsInputChannel, 'Needs input',
        description: 'Sessions waiting for input',
        importance: Importance.high));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
        _callChannel, 'Calls',
        description: 'Asks before Snippet takes notes on a call',
        importance: Importance.high));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
        _alertChannel, 'Updates',
        description: 'Session activity',
        importance: Importance.defaultImportance));
    unawaited(syncSavedNotifications().catchError((Object _) {}));
    return null;
  }
  if (kMacOS) {
    final darwin = _mainNotif.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await darwin?.requestPermissions(alert: true, badge: true, sound: true);
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
      (_) async =>
          (await NotificationInbox.open()).setForeground(fg, visibleKey: key));
  unawaited(_foregroundWrites.catchError((Object _) {}));
}

void reportVisibleNotificationSession(String? instance, String? session) {
  final key = notificationAppForeground && instance != null && session != null
      ? notificationSessionKey(instance, session)
      : null;
  if (visibleNotificationSession.value == key) return;
  visibleNotificationSession.value = key;
  if (kMobile) _writeForegroundLease();
  if ((kMobile || kMacOS) && session != null) {
    unawaited(_cancelSessionNotification(instance, session));
  }
}

Future<void> _cancelSessionNotification(
    String? instance, String session) async {
  try {
    final plugin = _mainNotif;
    final active = await plugin.getActiveNotifications();
    for (final item in active) {
      final raw = item.payload;
      if (raw == null) continue;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (_sessionOf(data) == session &&
          (instance == null || data['url'] == instance)) {
        if (item.id != null) await plugin.cancel(id: item.id!);
      }
    }
  } catch (_) {}
}

void reportForeground(bool fg) {
  notificationAppForeground = fg;
  if (!fg) visibleNotificationSession.value = null;
  if (kMobile) {
    _foregroundHeartbeat?.cancel();
    _writeForegroundLease();
    if (fg) {
      _foregroundHeartbeat = Timer.periodic(
          const Duration(seconds: 20), (_) => _writeForegroundLease());
    }
  }
  if (fg) unawaited(syncSavedNotifications().catchError((Object _) {}));
}
