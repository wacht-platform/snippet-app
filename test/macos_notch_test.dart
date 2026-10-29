import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/macos_notch.dart';

Map<String, dynamic> _msg(String role, String text) =>
    {'role': role, 'text': text, 'meta': '', 'type': 'message'};
Map<String, dynamic> _step(String text, {bool live = false}) => {
      'role': 'activity',
      'text': text,
      'meta': '',
      'type': 'activity',
      'live': live
    };

void main() {
  test('keeps only current-turn activity, last two finished plus summary', () {
    final items = finishNotchItems([
      _msg('user', 'old'),
      _step('Old step'),
      _msg('assistant', 'old answer'),
      _msg('user', 'fix it'),
      for (var i = 0; i < 5; i++) _step('Step $i'),
      _step('Editing x', live: true),
    ], running: true);
    final texts = items.map((m) => m['text']).toList();
    expect(texts, [
      'old',
      'old answer',
      'fix it',
      '+3 steps',
      'Step 3',
      'Step 4',
      'Editing x',
    ]);
    expect(items.last['live'], isTrue);
    expect(items.where((m) => m['live'] == true), hasLength(1));
  });

  test('nothing is live once the run stops', () {
    final items = finishNotchItems([
      _msg('user', 'go'),
      _step('Editing x', live: true),
    ]);
    expect(items.last['live'], isFalse);
  });

  test('caps at 40 rows and appends lanes then the pending question', () {
    final items = finishNotchItems(
      [for (var i = 0; i < 50; i++) _msg('assistant', 'm$i')],
      lanes: [
        {'title': 'audit', 'state': 'running', 'activity': 'Reading a.rs', 'id': 'l1'}
      ],
      pendingQuestion: {
        'questions': [
          {
            'id': 'q1',
            'text': 'Which one?',
            'answer_kind': {
              'kind': 'multi_choice',
              'choices': [
                {'value': 'a', 'label': 'Alpha'},
                {'value': 'b', 'label': 'Beta'}
              ]
            }
          }
        ]
      },
    );
    expect(items.where((m) => m['type'] == 'message'), hasLength(40));
    expect(items[items.length - 2]['type'], 'lane');
    expect(items[items.length - 2]['text'], 'Reading a.rs');
    expect(items.last['type'], 'question');
    expect(items.last['choices'], ['Alpha', 'Beta']);
    expect(items.last['answerKind'], 'multi');
  });

  test('approval only when no question is pending', () {
    final withQ = finishNotchItems([],
        pendingQuestion: {
          'questions': [
            {'id': 'q', 'text': 'Ok?', 'answer_kind': {'kind': 'yes_no'}}
          ]
        },
        approval: {'summary': 'Run tests', 'id': 'a'});
    expect(withQ.single['type'], 'question');
    expect(withQ.single['choices'], ['Yes', 'No']);
    final onlyApproval =
        finishNotchItems([], approval: {'summary': 'Run tests', 'id': 'a'});
    expect(onlyApproval.single['type'], 'approval');
    expect(onlyApproval.single['text'], 'Run tests');
  });

  test('several questions defer to the app', () {
    final items = finishNotchItems([], pendingQuestion: {
      'questions': [
        {'id': '1', 'text': 'A?'},
        {'id': '2', 'text': 'B?'}
      ]
    });
    expect(items.single['choices'], isEmpty);
    expect(items.single['text'], contains('2 questions'));
  });

  test('answer text matches the session screen format', () {
    expect(
        notchAnswerText({
          'questions': [
            {'text': 'Which?'}
          ]
        }, 'Alpha'),
        'Which?\n→ Alpha');
    expect(notchAnswerText(null, 'hi'), 'hi');
  });
}
