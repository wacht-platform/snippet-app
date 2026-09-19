import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/screens/session.dart';

/// A question with a long body must not overflow its pane.
///
/// The reported defect: the bottom chrome is a NON-FLEX child of the session
/// `Column`, so Flutter lays it out at its natural height before the
/// transcript's `Expanded` claims what is left. A question or approval card
/// carrying a long agent-authored body could therefore exceed the pane outright
/// and push its own actions off the bottom edge — the card's Submit/choices were
/// simply unreachable, and the render flex reported an overflow.
///
/// `RenderFlex` overflow surfaces as a caught exception, not a failed matcher,
/// so these assert `takeException()` explicitly — the same pattern the pane
/// strip tests use, and for the same reason: `flutter analyze` cannot see it.
void main() {
  /// Mount a bar the way the session host does: inside a bounded box, with the
  /// cap it derives from the pane (~60% of a short pane, as on a laptop).
  Future<void> mountCapped(WidgetTester tester, Widget bar,
      {double paneHeight = 320}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: paneHeight * 0.6,
                maxWidth: 700),
            child: bar,
          ),
        ),
      ),
    ));
  }

  /// A long, realistic agent-authored body: prose, not lorem ipsum, with enough
  /// lines that the natural height clearly exceeds any pane.
  String longBody() => List.generate(
        40,
        (i) => 'Line $i of a long agent-authored explanation that would '
            'previously have grown the card past the bottom of the pane.',
      ).join('\n');

  testWidgets('a long question body scrolls instead of overflowing',
      (tester) async {
    await mountCapped(
      tester,
      QuestionBar(
        question: {
          'context': longBody(),
          'questions': [
            {
              'id': 'q1',
              'text': longBody(),
              'answer_kind': {'kind': 'single_choice', 'choices': const []},
            },
          ],
        },
        onSend: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'a long question must be capped and scroll, not overflow');

    // The ACTIONS must still be on screen and reachable — that is the whole
    // point. An overflow that pushes Submit out of the pane is the defect.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    final submit = tester.getRect(find.text('Submit'));
    final pane = tester.getRect(find.byType(Scaffold));
    expect(submit.bottom, lessThanOrEqualTo(pane.bottom + 0.5),
        reason: 'Submit must remain inside the pane it is rendered in');
  });

  testWidgets('a long approval summary keeps its buttons reachable',
      (tester) async {
    await mountCapped(
      tester,
      ApprovalBar(
        events: [
          {
            'kind': 'approval_request',
            'tool_name': 'bash',
            'summary': longBody(),
            'arguments': const {'command': 'rm -rf build'},
            'index': 1,
            'total': 1,
          },
        ],
        onSend: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Approve/Reject are the decision; they must not be pushed off the edge.
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    final reject = tester.getRect(find.text('Reject'));
    final pane = tester.getRect(find.byType(Scaffold));
    expect(reject.bottom, lessThanOrEqualTo(pane.bottom + 0.5));
  });

  testWidgets('a short question is unaffected by the cap', (tester) async {
    await mountCapped(
      tester,
      QuestionBar(
        question: {
          'questions': [
            {
              'id': 'q1',
              'text': 'Pick one.',
              'answer_kind': {
                'kind': 'single_choice',
                'choices': const [
                  {'value': 'a', 'label': 'Alpha'},
                  {'value': 'b', 'label': 'Beta'},
                ],
              },
            },
          ],
        },
        onSend: (_) {},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Ordinary choices still render, and the free-text affordance is intact.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Write your own answer'), findsOneWidget);
  });
}
