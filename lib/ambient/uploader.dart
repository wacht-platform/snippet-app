import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics.dart';

import 'segment.dart';
import 'stream.dart';
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
  final http.Client _client = http.Client();
  late final AmbientStream _stream =
      AmbientStream(baseUrl: baseUrl, token: token, device: device);

  AmbientStream get stream => _stream;
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
  int _seqCounter = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<Directory> _queueDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/ambient/queue');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ambient_seq_$device';
    _seqCounter = max(
        prefs.getInt(key) ?? 0, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await _refreshCount();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _beat());
    _wire();
    _stream.keepAlive();
    unawaited(_drain(backlog: displaced.value));
  }

  Future<int> _nextSeq() {
    final next =
        max(_seqCounter, DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;
    _seqCounter = next;
    final key = 'ambient_seq_$device';
    unawaited(SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(key, next)));
    return Future.value(next);
  }

  void stat(Map<String, Object> values) => _stream.stat(values);

  int? _gate;
  bool _gateLive = false;
  DateTime? _heldAt;
  final List<Uint8List> _held = [];
  int _heldBytes = 0;
  static const _maxHeldBytes = 30 * 32000;

  void _wire() {
    _stream.onLink = (open) {
      if (!open) {
        _gateLive = false;
      } else if (_gate != null) {
        _reopen();
      }
    };
    _stream.onStreamError = (h, code) {
      if (h != _gate) return;
      _gateLive = false;
      if (code == 409) {
        unawaited(_giveUp());
      } else if (code == 403) {
        lastError.value = 'Ambient listening is turned off on the server';
      } else {
        lastError.value = 'Live transcription unavailable ($code)';
      }
    };
  }

  void gateOpen(DateTime startedAt, List<Uint8List> preRoll) {
    if (displaced.value) return;
    _gate = _stream.nextHandle();
    _gateLive = _stream.openStream(_gate!, startedAt);
    if (_gateLive) {
      for (final f in preRoll) {
        _stream.chunk(_gate!, f);
      }
    } else {
      _heldAt = startedAt;
      for (final f in preRoll) {
        _hold(f);
      }
    }
  }

  void gateFrame(Uint8List frame) {
    final h = _gate;
    if (h == null) return;
    if (_gateLive && _stream.open) {
      _stream.chunk(h, frame);
    } else {
      _gateLive = false;
      _heldAt ??= DateTime.now().subtract(const Duration(milliseconds: 32));
      _hold(frame);
    }
  }

  void gateClose() {
    final h = _gate;
    _gate = null;
    if (h == null) return;
    if (_gateLive) _stream.closeStream(h);
    _gateLive = false;
    _spill();
  }

  void flag(String kind, bool on) => _stream.flag(kind, on);

  void _hold(Uint8List frame) {
    _held.add(frame);
    _heldBytes += frame.length;
    if (_heldBytes >= _maxHeldBytes) _spill();
  }

  void _spill() {
    final at = _heldAt;
    if (_held.isEmpty || at == null) {
      _held.clear();
      _heldBytes = 0;
      _heldAt = null;
      return;
    }
    final b = BytesBuilder(copy: false);
    for (final f in _held) {
      b.add(f);
    }
    final pcm = b.takeBytes();
    _held.clear();
    _heldBytes = 0;
    _heldAt = null;
    unawaited(enqueue(AmbientSegment(at, pcm)));
  }

  void _reopen() {
    final at = _heldAt;
    _gate = _stream.nextHandle();
    _gateLive = _stream.openStream(_gate!, at ?? DateTime.now());
    if (!_gateLive) return;
    for (final f in _held) {
      _stream.chunk(_gate!, f);
    }
    _held.clear();
    _heldBytes = 0;
    _heldAt = null;
  }

  Future<void> _beat() async {
    if (_closed || displaced.value) return;
    try {
      final uri = Uri.parse(baseUrl)
          .replace(path: '/ambient/lease', queryParameters: {'token': token});
      final response = await _client
          .post(uri,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'device': device, 'label': label}))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 &&
          (jsonDecode(response.body) as Map<String, dynamic>)['held'] ==
              false) {
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
      lastError.value =
          'Could not save a segment: ${AmbientDiagnostics.redact('$e')}';
    });
    _writes = next;
    return next;
  }

  Future<void> _write(AmbientSegment segment) async {
    final id = newSegmentId();
    final seq = await _nextSeq();
    final dir = await _queueDir();
    await File('${dir.path}/$id.wav')
        .writeAsBytes(pcm16ToWav(segment.pcm), flush: true);
    await File('${dir.path}/$id.json').writeAsString(
        jsonEncode({
          'id': id,
          'started_at': segment.startedAt.toUtc().toIso8601String(),
          'duration_ms': segment.duration.inMilliseconds,
          'seq': seq,
        }),
        flush: true);
    await _trim(dir);
    await _refreshCount();
    unawaited(_drain(backlog: displaced.value));
  }

  Future<void> _trim(Directory dir) async {
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.wav'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final sizes = <int>[];
    var total = 0;
    for (final f in files) {
      try {
        sizes.add(await f.length());
      } on FileSystemException {
        sizes.add(0);
      }
      total += sizes.last;
    }
    for (var i = 0; i < files.length && total > _maxQueueBytes; i++) {
      total -= sizes[i];
      await _remove(files[i].path.substring(0, files[i].path.length - 4));
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
    final metas = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
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
        final next =
            metas.where((m) => !_inFlight.contains(m.path)).firstOrNull;
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
      final info =
          jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final wav = await audio.readAsBytes();
      final pcm =
          wav.length > 44 ? Uint8List.sublistView(wav, 44) : Uint8List(0);
      final h = _stream.nextHandle();
      final id = info['id'] as String;
      final started =
          DateTime.tryParse(info['started_at'] as String) ?? DateTime.now();
      final opened = await _stream.start(
          h, id, (info['seq'] as num).toInt(), started,
          backlog: backlog);
      if (!opened) {
        lastError.value = 'Upload failed: no connection';
        return false;
      }
      for (var i = 0; i < pcm.length; i += 16384) {
        _stream.chunk(
            h, Uint8List.sublistView(pcm, i, min(i + 16384, pcm.length)));
      }
      final response = await _stream.end(h, id,
          durationMs: (info['duration_ms'] as num).toInt(), bytes: pcm.length);
      if (response.code == 200) {
        await _remove(stem);
        return true;
      }
      if (response.code == 409) {
        if (backlog) {
          await _remove(stem);
          return true;
        }
        await _giveUp();
        final retry = await _upload(meta, backlog: true);
        return retry;
      }
      if (response.code == 400 || response.code == 413) {
        lastError.value =
            'Server rejected a segment (${response.code}); dropped it';
        await _remove(stem);
        return true;
      }
      lastError.value = response.code == 403
          ? 'Ambient listening is turned off on the server'
          : 'Upload failed (${response.code})';
      return false;
    } catch (e) {
      lastError.value = 'Upload failed: ${AmbientDiagnostics.redact('$e')}';
      return false;
    }
  }

  void close() {
    _closed = true;
    _heartbeat?.cancel();
    _stream.close();
  }
}
