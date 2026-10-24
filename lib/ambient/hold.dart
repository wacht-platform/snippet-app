import 'dart:typed_data';

import 'package:record/record.dart';

class AmbientHold {
  static int _count = 0;
  static bool get active => _count > 0;
  static void _add() => _count++;
  static void _drop() {
    if (_count > 0) _count--;
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
