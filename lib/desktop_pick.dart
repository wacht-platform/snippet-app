import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

class PickedLocalFile {
  final String name;
  final String path;
  const PickedLocalFile({required this.name, required this.path});

  Future<Uint8List> readAsBytes() => File(path).readAsBytes();
}

/// Desktop FilePicker 12 can throw MissingPluginException when the federated
/// Linux/macOS implementation never registered (stale runner or Linux host).
/// Fall back to a portal/zenity/osascript chooser so attach still works.
Future<List<PickedLocalFile>> pickLocalFiles() async {
  try {
    final files = await FilePicker.pickFiles(type: FileType.any);
    return [
      for (final f in files)
        if ((f.path ?? '').isNotEmpty)
          PickedLocalFile(name: f.name, path: f.path!),
    ];
  } on MissingPluginException {
    if (kMobile) rethrow;
    return _desktopChooser();
  } on UnimplementedError {
    if (kMobile) rethrow;
    return _desktopChooser();
  }
}

Future<List<PickedLocalFile>> _desktopChooser() async {
  final paths = kMacOS ? await _osascriptFiles() : await _linuxFiles();
  final out = <PickedLocalFile>[];
  for (final path in paths) {
    if (!await File(path).exists()) continue;
    out.add(PickedLocalFile(
      name: path.split(Platform.pathSeparator).last,
      path: path,
    ));
  }
  return out;
}

Future<List<String>> _osascriptFiles() async {
  final result = await Process.run('osascript', [
    '-e',
    'POSIX path of (choose file with multiple selections allowed)',
  ]);
  if (result.exitCode != 0) return const [];
  return _splitChooserOutput(result.stdout.toString());
}

Future<List<String>> _linuxFiles() async {
  for (final cmd in [
    [
      'zenity',
      '--file-selection',
      '--multiple',
      '--separator=\\n',
      '--title=Add context',
    ],
    ['kdialog', '--getopenfilename', '--multiple'],
  ]) {
    try {
      final result = await Process.run(cmd.first, cmd.sublist(1));
      if (result.exitCode == 0) {
        return _splitChooserOutput(result.stdout.toString());
      }
    } catch (_) {}
  }
  throw StateError(
      'No file picker available. Install zenity or rebuild the desktop app.');
}

List<String> _splitChooserOutput(String raw) {
  return raw
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
