import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets('a file link in a reply is handled in the app, not sent to the OS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final launched = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      launched.add(call);
      return true;
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: Bubble(
          mine: false,
          text: 'File: [clip.mp4](clip.mp4)',
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.textContaining('clip.mp4', findRichText: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(launched, isEmpty);
    expect(find.textContaining('Connect to the machine'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });
}
