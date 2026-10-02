import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledFonts();
  await testMain();
}

Future<void> _loadBundledFonts() async {
  const families = {'Manrope': 'Manrope', 'GeistMono': 'GeistMono'};
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final weight in const [400, 500, 600, 700]) {
      final file = File('assets/fonts/${entry.value}-$weight.ttf');
      if (!file.existsSync()) continue;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
