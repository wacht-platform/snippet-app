import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/call_prompt_card.dart';
import 'package:snippet/call_tracking.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

Widget _frame(CallPhase phase) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: AppColors.windowBg,
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
              key: const ValueKey('card'),
              child: SizedBox(
                width: 380,
                child: CallPromptCard(
                  status: CallStatus(
                      callId: 'c1', phase: phase, url: 'http://m'),
                  onAction: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final phase in CallPhase.values) {
    testWidgets('call card ${phase.name}', (tester) async {
      tester.view.physicalSize = const Size(840, 440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_frame(phase));
      await expectGolden(
          tester, find.byKey(const ValueKey('card')), 'goldens/call_card_${phase.name}.png');
    });
  }
}
