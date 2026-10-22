import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AmbientDiagnostics {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/diagnostics.txt');
  }

  static Future<void> log(String line) async {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      await (await _file()).writeAsString('$stamp $line\n', mode: FileMode.append, flush: true);
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
