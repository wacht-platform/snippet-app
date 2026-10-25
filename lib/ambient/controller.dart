import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import 'capture.dart';
import 'voice.dart';
import 'diagnostics.dart';
import 'hold.dart';
import 'uploader.dart';

@pragma('vm:entry-point')
void ambientServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_AmbientTaskHandler());
}

class _AmbientTaskHandler extends TaskHandler {
  AmbientCapture? _capture;
  StreamSubscription<AmbientStatus>? _sub;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await AmbientDiagnostics.log('service started (${starter.name})');
    try {
      final url = await FlutterForegroundTask.getData<String>(key: 'ambient_url');
      final token = await FlutterForegroundTask.getData<String>(key: 'ambient_token');
      final device = await FlutterForegroundTask.getData<String>(key: 'ambient_device');
      final label = await FlutterForegroundTask.getData<String>(key: 'ambient_label');
      if (url == null || token == null) {
        await AmbientDiagnostics.log('service has no server details, stopping');
        await FlutterForegroundTask.stopService();
        return;
      }
      final capture = AmbientCapture(
          AmbientUploader(
              baseUrl: url, token: token, device: device ?? 'android', label: label ?? ''));
      _capture = capture;
      _sub = capture.status.listen((status) {
        FlutterForegroundTask.sendDataToMain(status.toMap());
        if (status.displaced) {
          unawaited(FlutterForegroundTask.stopService());
          return;
        }
        if (status.error != null) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'Snippet is listening',
            notificationText: status.error!,
          );
        }
      });
      await AmbientDiagnostics.log('starting capture');
      await capture.start();
      await AmbientDiagnostics.log('capture running');
    } catch (e, st) {
      await AmbientDiagnostics.log('service failed to start: $e\n$st');
      FlutterForegroundTask.sendDataToMain(
          AmbientStatus(error: 'Could not start listening: $e').toMap());
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onReceiveData(Object data) {
    AmbientHold.receive(data);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _sub?.cancel();
    await _capture?.dispose();
    _capture = null;
  }
}

class AmbientController extends ChangeNotifier {
  AmbientController._();
  static final AmbientController instance = AmbientController._();

  static bool get _android => !kIsWeb && Platform.isAndroid;

  AmbientStatus status = const AmbientStatus();
  AmbientCapture? _local;
  StreamSubscription<AmbientStatus>? _localSub;
  bool _bound = false;
  bool _initialised = false;
  static final ValueNotifier<AmbientVoice?> _emptyVoice = ValueNotifier(null);

  bool get running => status.running;

  ValueListenable<AmbientVoice?> get voice => _local?.voiceListenable ?? _emptyVoice;

  Future<String> get deviceId async => (await _identity).$1;

  Future<(String, String)> get _identity async =>
      kIsWeb ? ('web', 'Browser') : await ambientDeviceIdentity();

  void _init() {
    if (_initialised) return;
    _initialised = true;
    if (_android) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'ambient_listening',
          channelName: 'Ambient listening',
          channelDescription: 'Shown while Snippet listens in the background.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
          allowAutoRestart: false,
        ),
      );
      FlutterForegroundTask.initCommunicationPort();
    }
  }

  Future<void> bind() async {
    _init();
    if (_bound) return;
    _bound = true;
    if (_android) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      if (await FlutterForegroundTask.isRunningService) {
        status = AmbientStatus(
            running: true,
            segments: status.segments,
            pending: status.pending);
        notifyListeners();
      }
    }
  }

  void _onTaskData(Object data) {
    if (data is Map) {
      status = AmbientStatus.fromMap(data.cast<Object?, Object?>());
      notifyListeners();
    }
  }

  Future<String?> start(DaemonClient client) async {
    _init();
    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : true;
    if (!granted) return 'Microphone permission is required.';
    final (deviceId, deviceLabel) = await _identity;
    try {
      await client.claimAmbientLease(deviceId, deviceLabel);
    } catch (e) {
      return 'Could not claim listening: $e';
    }
    if (_android) {
      final notifications = await FlutterForegroundTask.checkNotificationPermission();
      if (notifications != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await AmbientDiagnostics.log('start requested');
      await FlutterForegroundTask.saveData(key: 'ambient_url', value: client.baseUrl);
      await FlutterForegroundTask.saveData(key: 'ambient_token', value: client.token);
      await FlutterForegroundTask.saveData(key: 'ambient_device', value: deviceId);
      await FlutterForegroundTask.saveData(key: 'ambient_label', value: deviceLabel);
      final result = await FlutterForegroundTask.startService(
        serviceId: 4711,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: 'Snippet is listening',
        notificationText: 'Ambient listening is on',
        callback: ambientServiceEntry,
      );
      if (result is ServiceRequestFailure) return '${result.error}';
      if (AmbientHold.local) AmbientHold.publishCurrent();
      status = const AmbientStatus(running: true);
      notifyListeners();
      return null;
    }
    try {
      final capture = AmbientCapture(AmbientUploader(
          baseUrl: client.baseUrl,
          token: client.token,
          device: deviceId,
          label: deviceLabel));
      _local = capture;
      _localSub = capture.status.listen((s) {
        status = s;
        notifyListeners();
      });
      await capture.start();
      return null;
    } catch (e) {
      await _localSub?.cancel();
      await _local?.dispose();
      _local = null;
      return 'Could not start listening: $e';
    }
  }

  Future<void> stop() async {
    if (_android) {
      await FlutterForegroundTask.stopService();
    } else {
      await _localSub?.cancel();
      await _local?.dispose();
      _local = null;
    }
    status = AmbientStatus(segments: status.segments, pending: status.pending);
    notifyListeners();
  }

  Future<bool> get ignoringBattery async =>
      !_android || await FlutterForegroundTask.isIgnoringBatteryOptimizations;

  Future<void> requestBatteryExemption() async {
    if (_android) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  Future<(AmbientSettings?, String?)> setEnabled(DaemonClient client, bool on) async {
    try {
      if (on) {
        var saved = await client.setAmbientSettings(enabled: true);
        final error = await start(client);
        if (error != null) {
          saved = await client.setAmbientSettings(enabled: false);
          return (saved, error);
        }
        return (saved, null);
      }
      await stop();
      return (await client.setAmbientSettings(enabled: false), null);
    } catch (e) {
      return (null, '$e');
    }
  }
}
