import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';

/// Proves the test bootstrap actually applies real fonts to the app's own
/// helpers. The control line (bare `TextStyle`) must stay as blocks — if the
/// controls render text too, the registration is leaking and the others prove
/// nothing.
void main() {
  testWidgets('font probe', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1600, 1100);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('sans 400 Body weight 0123456789 Wg',
                  style: sans(26)),
              Text('sans 500 Label weight 0123456789 Wg',
                  style: sans(26, weight: W.label)),
              Text('sans 600 Strong weight 0123456789 Wg',
                  style: sans(26, weight: W.strong)),
              Text('mono 26 0123456789 Wg', style: mono(26)),
              Text('display 26 0123456789 Wg', style: display(26)),
              const Text('CONTROL (no family) 0123456789 Wg',
                  style: TextStyle(fontSize: 26)),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/font_probe.png'));
  });
}
