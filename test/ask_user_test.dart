import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('ask_user: recommended preselected, multi-choice, review, answer text',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionBar(
              question: const {
                'questions': [
                  {
                    'id': 'targets',
                    'header': 'Targets',
                    'text': 'Which builds?',
                    'answer_kind': {
                      'kind': 'multi_choice',
                      'choices': [
                        {'value': 'macos', 'label': 'macOS'},
                        {'value': 'android', 'label': 'Android', 'recommended': true},
                      ]
                    }
                  },
                  {
                    'id': 'ship',
                    'header': 'Ship',
                    'text': 'Publish now?',
                    'answer_kind': {'kind': 'confirm', 'confirm_label': 'Publish', 'cancel_label': 'Hold'}
                  }
                ]
              },
              onSend: (m) => sent = m,
            ),
          ),
        ),
      ));
      await tester.pump();

      // The recommended option is ticked already, so Next is enabled.
      expect(find.text('Recommended'), findsOneWidget);
      await tester.tap(find.text('macOS'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();

      // Confirm uses the agent's labels.
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Hold'), findsOneWidget);
      await tester.tap(find.text('Publish'));
      await tester.pump();
      await tester.tap(find.text('Review').last);
      await tester.pump();

      expect(find.text('Check your answers'), findsOneWidget);
      expect(find.text('Android, macOS'), findsOneWidget);
      await tester.tap(find.text('Submit'));
      await tester.pump();

      expect(sent?['kind'], 'answer');
      expect(sent?['value'],
          'Which builds?\n→ Android, macOS\n\nPublish now?\n→ Publish (confirm)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
