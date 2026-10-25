import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

class AmbientHold {
  static int _count = 0;
  static DateTime? _remoteUntil;

  static bool get local => _count > 0;

  static bool get active {
    if (_count > 0) return true;
    final until = _remoteUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _remoteUntil = null;
      return false;
    }
    return true;
  }

  static void _add() {
    _count++;
    if (_count == 1) _publish(true);
  }

  static void _drop() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) _publish(false);
  }

  static void publishCurrent() => _publish(local);

  static void _publish(bool on) {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      FlutterForegroundTask.sendDataToTask({'ambient_hold': on});
    } catch (_) {}
  }

  static bool receive(Object data) {
    if (data is! Map || !data.containsKey('ambient_hold')) return false;
    _remoteUntil = data['ambient_hold'] == true
        ? DateTime.now().add(const Duration(minutes: 15))
        : null;
    return true;
  }
}

class HeldRecorder extends AudioRecorder {
  bool _held = false;

  void _on() {
    if (_held) return;
    _held = true;
    AmbientHold._add();
  }

  void _off() {
    if (!_held) return;
    _held = false;
    AmbientHold._drop();
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _on();
    try {
      await super.start(config, path: path);
    } catch (_) {
      _off();
      rethrow;
    }
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    _on();
    try {
      return await super.startStream(config);
    } catch (_) {
      _off();
      rethrow;
    }
  }

  @override
  Future<String?> stop() async {
    try {
      return await super.stop();
    } finally {
      _off();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await super.cancel();
    } finally {
      _off();
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await super.dispose();
    } finally {
      _off();
    }
  }
}
