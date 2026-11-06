import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_text.dart';

void main() {
  final t0 = DateTime(2026, 11, 6, 12);

  group('NotificationDedupe', () {
    test('the same event from two paths shows once', () {
      final d = NotificationDedupe();
      expect(d.admit(id: 'n1', session: 's', text: 'Finished the fix', now: t0),
          isTrue);
      expect(
          d.admit(
              id: 'n1',
              session: 's',
              text: 'Release · Finished the fix',
              now: t0),
          isFalse);
    });

    test('the chat message and its stopped notification collapse', () {
      final d = NotificationDedupe();
      expect(
          d.admit(
              id: '', session: 's', text: 'Both **pipelines** pass.', now: t0),
          isTrue);
      expect(
          d.admit(id: 'n2', session: 's', text: 'Both pipelines pass', now: t0),
          isFalse);
    });

    test('a later copy with buttons still gets through', () {
      final d = NotificationDedupe();
      expect(
          d.admit(id: '', session: 's', text: 'Which one?', now: t0), isTrue);
      expect(
          d.admit(
              id: 'n3',
              session: 's',
              text: 'Which one?',
              actionable: true,
              now: t0),
          isTrue);
      expect(
          d.admit(
              id: 'n3',
              session: 's',
              text: 'Which one?',
              actionable: true,
              now: t0),
          isFalse);
    });

    test('other sessions and later repeats are kept', () {
      final d = NotificationDedupe();
      expect(d.admit(id: '', session: 'a', text: 'Done', now: t0), isTrue);
      expect(d.admit(id: '', session: 'b', text: 'Done', now: t0), isTrue);
      expect(
          d.admit(
              id: '',
              session: 'a',
              text: 'Done',
              now: t0.add(const Duration(minutes: 2))),
          isTrue);
    });
  });

  test('a newer session state replaces the older toast, messages stay', () {
    Map<String, dynamic> p(String kind, String session) =>
        {'kind': kind, 'session': session, 'url': 'u'};
    expect(toastSuperseded(p('waiting', 's'), p('idle', 's')), isTrue);
    expect(toastSuperseded(p('waiting', 's'), p('idle', 'other')), isFalse);
    expect(toastSuperseded(p('direct_message.sent', 's'), p('idle', 's')),
        isFalse);
  });
}
