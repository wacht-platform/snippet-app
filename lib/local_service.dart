import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';
import 'platform.dart';

const enableCommand = 'snippet serve --enable';
const installCommand = 'curl -fsSL https://snippet.wacht.dev/install.sh | sh';

/// The macOS sandbox gives the app a private HOME and blocks writing outside it.
bool get sandboxedApp =>
    (Platform.environment['HOME'] ?? '').contains('/Library/Containers/');

/// The installer ships Linux x86_64 and macOS Apple Silicon only, and cannot run in the sandbox.
bool get canInstallLocalService =>
    !kIsWeb && !kMobile && !kWindows && !sandboxedApp;

String get _home {
  final h = Platform.environment['HOME'] ?? '';
  final i = h.indexOf('/Library/Containers/');
  return i < 0 ? h : h.substring(0, i);
}

/// True when something answers snippet's health check on this machine, token or not.
Future<bool> localServiceUp(
    {Duration timeout = const Duration(milliseconds: 900)}) async {
  try {
    final r = await http
        .get(Uri.parse('http://127.0.0.1:8787/health'))
        .timeout(timeout);
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

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

enum InstallStage { download, install, start, connect }

class InstallResult {
  final Instance? instance;
  final String? error;

  /// False when the OS service could not be enabled, so the daemon will not survive a restart.
  final bool autoStart;
  const InstallResult.ok(Instance this.instance, {this.autoStart = true})
      : error = null;
  const InstallResult.failed(String this.error)
      : instance = null,
        autoStart = false;
}

/// Installs the binary if missing, starts the daemon and waits for it to answer.
Future<InstallResult> installLocalService(
    void Function(InstallStage stage, String detail) onStage) async {
  if (!localBinaryInstalled()) {
    onStage(InstallStage.download, 'Fetching the latest release');
    final p = await Process.start('sh', ['-c', installCommand],
        environment: {'SNIPPET_INSTALL_DEPS': 'no'});
    final tail = <String>[];
    void take(String s) {
      for (final l in const LineSplitter().convert(s)) {
        final t = l.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').trim();
        if (t.isEmpty) continue;
        tail.add(t);
        onStage(
            RegExp(r'verifying|extracting|installing', caseSensitive: false)
                    .hasMatch(t)
                ? InstallStage.install
                : InstallStage.download,
            t);
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
  onStage(InstallStage.start, 'Starting the service');
  final enabled = await Process.run(localBinaryPath, ['serve', '--enable']);
  var autoStart = enabled.exitCode == 0;
  onStage(InstallStage.connect, 'Waiting for it to answer');
  var inst = await _waitForLocal(const Duration(seconds: 15));
  if (inst == null) {
    autoStart = false;
    await Process.run(localBinaryPath, ['serve']);
    inst = await _waitForLocal(const Duration(seconds: 15));
  }
  if (inst == null) {
    return const InstallResult.failed(
        'Installed, but the service did not start. Run snippet serve in a terminal to see why.');
  }
  return InstallResult.ok(inst, autoStart: autoStart);
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
