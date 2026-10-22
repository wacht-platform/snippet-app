import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'segmenter.dart';
import 'wav.dart';

String newSegmentId() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$hex';
}

class AmbientUploader {
  AmbientUploader({
    required this.baseUrl,
    required this.token,
    required this.device,
    Directory? directory,
  }) : _dir = directory;

  final String baseUrl;
  final String token;
  final String device;

  static const _maxQueueBytes = 500 * 1024 * 1024;

  final ValueNotifier<int> pending = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  Directory? _dir;
  bool _draining = false;
  bool _closed = false;
  int _failures = 0;

  Future<Directory> _queueDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/ambient/queue');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<void> start() async {
    await _refreshCount();
    unawaited(_drain());
  }

  Future<void> _writes = Future.value();

  Future<void> enqueue(AmbientSegment segment) {
    final next = _writes.then((_) => _write(segment)).catchError((Object e) {
      lastError.value = 'Could not save a segment: $e';
    });
    _writes = next;
    return next;
  }

  Future<void> _write(AmbientSegment segment) async {
    final dir = await _queueDir();
    final id = newSegmentId();
    await File('${dir.path}/$id.wav').writeAsBytes(pcm16ToWav(segment.pcm), flush: true);
    await File('${dir.path}/$id.json').writeAsString(jsonEncode({
      'id': id,
      'started_at': segment.startedAt.toUtc().toIso8601String(),
      'duration_ms': segment.duration.inMilliseconds,
    }), flush: true);
    await _trim(dir);
    await _refreshCount();
    unawaited(_drain());
  }

  Future<void> _trim(Directory dir) async {
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.wav')).cast<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final sizes = <File, int>{};
    var total = 0;
    for (final f in files) {
      try {
        final n = await f.length();
        sizes[f] = n;
        total += n;
      } on FileSystemException {
        continue;
      }
    }
    if (total <= _maxQueueBytes) return;
    for (final f in files) {
      if (total <= _maxQueueBytes) break;
      total -= sizes[f] ?? 0;
      await _remove(f.path.substring(0, f.path.length - 4));
    }
  }

  Future<void> _remove(String stem) async {
    for (final ext in ['json', 'wav']) {
      try {
        await File('$stem.$ext').delete();
      } on FileSystemException {
        continue;
      }
    }
  }

  Future<List<File>> _metas() async {
    final dir = await _queueDir();
    final metas = await dir.list().where((e) => e is File && e.path.endsWith('.json')).cast<File>().toList();
    metas.sort((a, b) => a.path.compareTo(b.path));
    return metas;
  }

  Future<void> _refreshCount() async {
    pending.value = (await _metas()).length;
  }

  Future<void> _drain() async {
    if (_draining || _closed) return;
    _draining = true;
    try {
      while (!_closed) {
        final metas = await _metas();
        pending.value = metas.length;
        if (metas.isEmpty) {
          _failures = 0;
          break;
        }
        final ok = await _upload(metas.first);
        if (ok) {
          _failures = 0;
          lastError.value = null;
          continue;
        }
        _failures++;
        final wait = min(300, 2 << min(_failures, 8));
        await Future<void>.delayed(Duration(seconds: wait));
      }
    } finally {
      _draining = false;
    }
  }

  Future<bool> _upload(File meta) async {
    final stem = meta.path.substring(0, meta.path.length - 5);
    final audio = File('$stem.wav');
    try {
      if (!await audio.exists()) {
        await _remove(stem);
        return true;
      }
      final info = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final uri = Uri.parse(baseUrl).replace(path: '/ambient/events', queryParameters: {
        'token': token,
        'id': info['id'] as String,
        'device': device,
        'started_at': info['started_at'] as String,
        'duration_ms': '${info['duration_ms']}',
      });
      final response = await http
          .post(uri, headers: {'content-type': 'audio/wav'}, body: await audio.readAsBytes())
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        await _remove(stem);
        return true;
      }
      if (response.statusCode == 400 || response.statusCode == 413) {
        lastError.value = 'Server rejected a segment (${response.statusCode}); dropped it';
        await _remove(stem);
        return true;
      }
      lastError.value = response.statusCode == 403
          ? 'Ambient listening is turned off on the server'
          : 'Upload failed (${response.statusCode})';
      return false;
    } catch (e) {
      lastError.value = 'Upload failed: $e';
      return false;
    }
  }

  void close() {
    _closed = true;
  }
}
