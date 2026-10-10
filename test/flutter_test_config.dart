import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _stubMediaPlugins();
  await _loadBundledFonts();
  await testMain();
}

void _stubMediaPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers.global/events',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

Future<void> _loadBundledFonts() async {
  const families = {
    'JetBrainsMono': 'JetBrainsMono',
    'Geist': 'Geist',
    'Literata': 'Literata',
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final weight in const [400, 500, 600, 700]) {
      for (final suffix in const ['', '-italic']) {
        final file = File('assets/fonts/${entry.value}-$weight$suffix.ttf');
        if (!file.existsSync()) continue;
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}
