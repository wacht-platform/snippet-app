import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';

void main() {
  test('direct message envelope carries kind and urgency', () {
    final m = parseDirectMessage(
        '[direct_message]\nthread_id: t\nfrom: agent:a\nkind: blocker\nurgency: urgent (deal with it first)\nbody: stuck\n[/direct_message]');
    expect(m!.messageKind, 'blocker');
    expect(m.urgent, isTrue);
    expect(m.body, 'stuck');
  });

  test('untyped envelope stays plain', () {
    final m = parseDirectMessage('[direct_message]\nthread_id: t\nfrom: agent:a\nbody: hi\n[/direct_message]');
    expect(m!.messageKind, '');
    expect(m.urgent, isFalse);
  });

  test('a question notification leads with the question itself', () {
    expect(
        userQuestionLead({
          'questions': {
            'questions': [
              {'text': 'Ship the APK now?'},
              {'text': 'Which build?'}
            ]
          }
        }),
        'Ship the APK now? (+1 more)');
    expect(userQuestionLead({'questions': [{'text': 'Merge it?'}]}), 'Merge it?');
    expect(userQuestionLead({}), 'Needs your input');
  });
}
