import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics.dart';

import 'segmenter.dart';
import 'wav.dart';

String newSegmentId() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$hex';
}

Future<(String, String)> ambientDeviceIdentity() async {
  final root = await getApplicationSupportDirectory();
  final dir = Directory('${root.path}/ambient');
  await dir.create(recursive: true);
  final file = File('${dir.path}/device_id');
  var id = '';
  try {
    id = (await file.readAsString()).trim();
  } on FileSystemException {
    id = '';
  }
  if (id.isEmpty) {
    id = newSegmentId().split('-').last.substring(0, 8);
    await file.writeAsString(id);
  }
  final os = Platform.operatingSystem;
  final name = switch (os) {
    'android' => 'Android',
    'ios' => 'iPhone',
    'macos' => 'Mac',
    'linux' => 'Linux',
    'windows' => 'Windows',
    _ => os,
  };
  return ('$os-$id', '$name ${id.substring(0, 4)}');
}

class AmbientUploader {
  AmbientUploader({
    required this.baseUrl,
    required this.token,
    required this.device,
    this.label = '',
    Directory? directory,
  }) : _dir = directory;

  final String baseUrl;
  final String token;
  final String device;
  final String label;

  static const _maxQueueBytes = 500 * 1024 * 1024;

  final ValueNotifier<int> pending = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<bool> displaced = ValueNotifier(false);
  Timer? _heartbeat;
  Directory? _dir;
  final Set<String> _inFlight = {};
  int _workers = 0;
  static const _maxWorkers = 2;
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
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _beat());
    unawaited(_drain(backlog: displaced.value));
  }

  Future<int> _nextSeq() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ambient_seq_$device';
    final current = prefs.getInt(key) ?? 0;
    final next = max(current, DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;
    await prefs.setInt(key, next);
    return next;
  }

  Future<int> reserveSequence() => _nextSeq();

  Future<void> activity(DateTime startedAt, int seq) async {
    try {
      final uri = Uri.parse(baseUrl).replace(path: '/ambient/activity', queryParameters: {'token': token});
      await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode({'device': device, 'seq': seq, 'started_at': startedAt.toIso8601String()})).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> _beat() async {
    if (_closed || displaced.value) return;
    try {
      final uri = Uri.parse(baseUrl).replace(path: '/ambient/lease', queryParameters: {'token': token});
      final response = await http
          .post(uri,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'device': device, 'label': label}))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 &&
          (jsonDecode(response.body) as Map<String, dynamic>)['held'] == false) {
        await _giveUp();
      }
    } catch (e) {
      await AmbientDiagnostics.log('heartbeat failed: $e');
    }
  }

  Future<void> _giveUp() async {
    if (displaced.value) return;
    displaced.value = true;
    _heartbeat?.cancel();
    pending.value = await _refreshCount();
    unawaited(_drain(backlog: true));
    lastError.value = 'Another device took over listening';
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
    final seq = await (segment.seq ?? _nextSeq());
    await File('${dir.path}/$id.wav').writeAsBytes(pcm16ToWav(segment.pcm), flush: true);
    await File('${dir.path}/$id.json').writeAsString(jsonEncode({
      'id': id,
      'started_at': segment.startedAt.toUtc().toIso8601String(),
      'duration_ms': segment.duration.inMilliseconds,
      'continued': segment.continued,
      'during_playback': segment.duringPlayback,
      'seq': seq,
    }), flush: true);
    await _trim(dir);
    await _refreshCount();
    unawaited(_drain(backlog: displaced.value));
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

  Future<int> _refreshCount() async {
    final count = (await _metas()).length;
    pending.value = count;
    return count;
  }

  Future<void> _drain({bool backlog = false}) async {
    if (_closed) return;
    while (_workers < _maxWorkers) {
      _workers++;
      unawaited(_worker(backlog: backlog));
    }
  }

  Future<void> _worker({bool backlog = false}) async {
    try {
      while (!_closed) {
        final metas = await _metas();
        pending.value = metas.length;
        final next = metas.where((m) => !_inFlight.contains(m.path)).firstOrNull;
        if (next == null) {
          if (metas.isEmpty) _failures = 0;
          break;
        }
        _inFlight.add(next.path);
        bool ok;
        try {
          ok = await _upload(next, backlog: backlog || displaced.value);
        } finally {
          _inFlight.remove(next.path);
        }
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
      _workers--;
    }
  }

  Future<bool> _upload(File meta, {bool backlog = false}) async {
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
        'seq': '${info['seq']}',
        'continued': '${info['continued'] == true}',
        'during_playback': '${info['during_playback'] == true}',
        if (backlog) 'backlog': '1',
      });
      final response = await http
          .post(uri, headers: {'content-type': 'audio/wav'}, body: await audio.readAsBytes())
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        await _remove(stem);
        return true;
      }
      if (response.statusCode == 409) {
        if (backlog) { await _remove(stem); return true; }
        await _giveUp();
        final retry = await _upload(meta, backlog: true);
        return retry;
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
    _heartbeat?.cancel();
  }
}
