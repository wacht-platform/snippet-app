import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets('voice note with transcript', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 220);
    addTearDown(tester.view.reset);
    final client = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12)),
              child: VoiceNote(
                client: client,
                path: '/tmp/note.m4a',
                transcript: Text(
                    "Your file exchange card doesn't look very good, okay? It needs to look a little bit better, I feel.",
                    style: sans(14, color: AppColors.fg1)),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Voice note'), findsOneWidget);
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('visual/goldens/voice_note_card.png'));
  });
}
