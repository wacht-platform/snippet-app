import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

const _approval = {
  'title': 'Fix login redirect',
  'kind': 'waiting',
  'session': 's-1',
  'body': 'Run `pnpm test:auth`? It hits the **staging** database.',
  'attention': {'type': 'approval', 'id': '4:x'},
};
const _question = {
  'title': 'Release notes draft',
  'kind': 'waiting',
  'session': 's-2',
  'body': 'Which version should the notes cover?',
  'attention': {'type': 'question', 'id': '9:y'},
};
const _done = {
  'title': 'Coordination review',
  'kind': 'done',
  'session': 's-3',
  'body': '## Summary\n- Merged the **review** queue fix',
};

void main() {
  Widget frame(Widget child, {double width = 390}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
                width: width,
                child: Padding(
                    padding: const EdgeInsets.all(12), child: child)),
          ),
        ),
      );

  NotificationMessageCard card(Map<String, dynamic> p,
          {List<Map<String, dynamic>> rest = const [],
          List<QuickAction>? sent,
          VoidCallback? onSent,
          bool ok = true}) =>
      NotificationMessageCard(
        payload: p,
        rest: rest,
        onOpen: () {},
        onDismiss: () {},
        onClearAll: () {},
        onHold: (_) {},
        onSent: onSent ?? () {},
        send: (_, a) async {
          sent?.add(a);
          return ok;
        },
      );

  test('preview strips markdown', () {
    expect(plainPreview('## Hi\n- **bold** and `code` [link](http://x)'),
        'Hi · bold and code link');
  });

  test('action follows kind and attention', () {
    expect(cardActionFor(_approval), CardAction.approval);
    expect(cardActionFor(_question), CardAction.answer);
    expect(cardActionFor(_done), CardAction.view);
    expect(
        cardActionFor({
          'kind': 'message',
          'destination': {'type': 'conversation', 'id': 'c'}
        }),
        CardAction.reply);
    expect(cardActionFor({'kind': 'waiting'}), CardAction.none);
  });

  testWidgets('approval sends approve and reports sent', (tester) async {
    final sent = <QuickAction>[];
    var done = false;
    await tester.pumpWidget(
        frame(card(_approval, sent: sent, onSent: () => done = true)));
    expect(find.text('Needs input'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(sent.single, isA<QuickApprove>());
    expect(done, isTrue);
  });

  testWidgets('question answers with typed text; failure shows fallback',
      (tester) async {
    final sent = <QuickAction>[];
    await tester.pumpWidget(frame(card(_question, sent: sent, ok: false)));
    await tester.enterText(find.byType(TextField), '1.4');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect((sent.single as QuickAnswer).text, '1.4');
    expect(find.text("Couldn't send. Open chat"), findsOneWidget);
  });

  testWidgets('groups the rest by chat', (tester) async {
    await tester.pumpWidget(frame(card(_done, rest: [
      {..._approval, 'url': 'u'},
      {..._question, 'url': 'u'},
    ])));
    expect(find.text('+2 more from 2 chats'), findsOneWidget);
  });

  for (final (name, platform, width) in [
    ('mobile', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.macOS, 444.0),
  ]) {
    testWidgets('message cards render ($name)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.binding.setSurfaceSize(Size(width, 560));
        await tester.pumpWidget(frame(
            Column(children: [
              card(_approval, rest: [_question, _done]),
              const SizedBox(height: 12),
              card(_question),
              const SizedBox(height: 12),
              card(_done),
            ]),
            width: width));
        await expectGolden(tester, find.byType(Scaffold),
            'goldens/notification_cards_$name.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });
  }
}
