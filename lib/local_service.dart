import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';
import 'platform.dart';

const installCommand = 'curl -fsSL https://snippet.wacht.dev/install.sh | sh';

/// The installer ships Linux x86_64 and macOS Apple Silicon only.
bool get canInstallLocalService => !kIsWeb && !kMobile && !kWindows;

String get _home => Platform.environment['HOME'] ?? '';

String get localBinaryPath => '$_home/.local/bin/snippet';

bool localBinaryInstalled() => File(localBinaryPath).existsSync();

/// Reads the running daemon's loopback address and token, or null if it is not up.
Future<Instance?> localInstance(
    {Duration timeout = const Duration(seconds: 2)}) async {
  try {
    final f = File('$_home/.snippet/serve.json');
    if (!f.existsSync()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final url = j['api_url'] as String? ?? '';
    final token = j['token'] as String? ?? '';
    if (url.isEmpty || token.isEmpty) return null;
    final r = await http.get(Uri.parse('$url/health')).timeout(timeout);
    if (r.statusCode != 200) return null;
    final cfg = await DaemonClient(url, token).getConfig();
    return Instance(
        name: cfg.hostname.isNotEmpty ? cfg.hostname : 'This computer',
        url: url,
        token: token);
  } catch (_) {
    return null;
  }
}

class InstallResult {
  final Instance? instance;
  final String? error;
  const InstallResult.ok(Instance this.instance) : error = null;
  const InstallResult.failed(String this.error) : instance = null;
}

/// Installs the binary if missing, starts the daemon and waits for it to answer.
Future<InstallResult> installLocalService(
    void Function(String line) onLine) async {
  if (!localBinaryInstalled()) {
    onLine('Downloading snippet');
    final p = await Process.start('sh', ['-c', installCommand],
        environment: {'SNIPPET_INSTALL_DEPS': 'no'});
    final tail = <String>[];
    void take(String s) {
      for (final l in const LineSplitter().convert(s)) {
        final t = l.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').trim();
        if (t.isEmpty) continue;
        tail.add(t);
        onLine(t);
      }
    }

    final done = Future.wait([
      p.stdout.transform(utf8.decoder).forEach(take),
      p.stderr.transform(utf8.decoder).forEach(take),
    ]);
    final code = await p.exitCode;
    await done;
    if (code != 0 || !localBinaryInstalled()) {
      final last =
          tail.isEmpty ? 'the installer exited with code $code' : tail.last;
      return InstallResult.failed(last);
    }
  }
  onLine('Starting the service');
  await Process.run(localBinaryPath, ['serve', '--enable']);
  var inst = await _waitForLocal(const Duration(seconds: 15));
  if (inst == null) {
    await Process.run(localBinaryPath, ['serve']);
    inst = await _waitForLocal(const Duration(seconds: 15));
  }
  if (inst == null) {
    return const InstallResult.failed(
        'Installed, but the service did not start. Run snippet serve in a terminal to see why.');
  }
  return InstallResult.ok(inst);
}

Future<Instance?> _waitForLocal(Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    final i = await localInstance();
    if (i != null) return i;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return null;
}
