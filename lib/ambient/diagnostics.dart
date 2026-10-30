import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AmbientDiagnostics {
  static const _maxBytes = 256 * 1024;
  static const _keepBytes = 64 * 1024;
  static int _writes = 0;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/diagnostics.txt');
  }

  static String redact(String text) =>
      text.replaceAll(RegExp(r'token=[^&\s,)\]]+'), 'token=…');

  static Future<void> log(String line) async {
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceFirst('T', ' ');
      final file = await _file();
      await file.writeAsString('$stamp ${redact(line)}\n',
          mode: FileMode.append, flush: true);
      if (++_writes % 50 == 0 && await file.length() > _maxBytes) {
        final bytes = await file.readAsBytes();
        await file.writeAsBytes(bytes.sublist(bytes.length - _keepBytes),
            flush: true);
      }
    } catch (_) {}
  }

  static Future<String> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return '';
      final text = await file.readAsString();
      return text.length > 6000 ? text.substring(text.length - 6000) : text;
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
