import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/notifications.dart';

void main() {
  const instance = Instance(name: 'Snippet', url: 'u', token: 't');

  test('an agent message notification shows the message, not just the machine name', () {
    final c = notificationContent(instance, {
      'kind': 'direct_message.sent',
      'destination': {'type': 'session', 'id': 's'},
      'payload': {'body': 'Boss reviewed the **cut**. One more change.'},
    });
    expect(c.head, 'Message');
    expect(c.body, 'Boss reviewed the cut. One more change.');
  });
}
