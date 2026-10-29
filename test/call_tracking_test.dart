import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/call_tracking.dart';
import 'package:snippet/notifications.dart';

class _Daemon extends DaemonClient {
  _Daemon(this.status) : super('http://127.0.0.1:9090', 'tok');
  final int status;
  final calls = <String>[];

  @override
  Future<int> ambientCallAction(String callId, String action) async {
    calls.add('$action/$callId');
    return status;
  }
}

CallEvent _prompt(int expires) => CallEvent(
    type: callPromptType, callId: 'c1', expiresAtMs: expires);

void main() {
  const url = 'http://127.0.0.1:9090';
  final far = DateTime.now().millisecondsSinceEpoch + 120000;

  group('payload parsing', () {
    test('top-level contract fields', () {
      final e = parseCallEvent({
        'type': 'call_prompt',
        'call_id': 'c1',
        'expires_at': 1700000120000,
        'title': 'Track this call?',
        'body': 'Sounds like you\'re talking with someone.',
      })!;
      expect(e.isPrompt, isTrue);
      expect(e.callId, 'c1');
      expect(e.expiresAtMs, 1700000120000);
    });

    test('nested payload, kind key and seconds timestamps', () {
      final e = parseCallEvent({
        'kind': 'call_prompt',
        'notification_id': 'n',
        'payload': {'call_id': 'c2', 'expires_at': 1700000120},
      })!;
      expect(e.callId, 'c2');
      expect(e.expiresAtMs, 1700000120000);
      expect(e.title, callPromptTitle);
    });

    test('call_state and non-call events', () {
      final s = parseCallEvent({
        'type': 'call_state',
        'call_id': 'c1',
        'state': 'declined'
      })!;
      expect(s.isPrompt, isFalse);
      expect(s.state, 'declined');
      expect(parseCallEvent({'kind': 'waiting', 'session': 's'}), isNull);
      expect(parseCallEvent({'type': 'call_prompt'}), isNull);
    });
  });

  group('action routing', () {
    test('track, ignore and stop hit their own endpoint', () async {
      final tracker = CallTracker();
      final d = _Daemon(200);
      tracker.apply(url, _prompt(far));
      expect(await tracker.act(d, 'c1', callActionTrack), isTrue);
      expect(tracker.state.value!.phase, CallPhase.tracking);
      expect(await tracker.act(d, 'c1', callActionStop), isTrue);
      expect(tracker.state.value, isNull);
      tracker.apply(url, _prompt(far));
      await tracker.act(d, 'c1', callActionIgnore);
      expect(d.calls, ['track/c1', 'stop/c1', 'ignore/c1']);
      expect(tracker.state.value, isNull);
    });

    test('409 and 404 dismiss, other failures keep the prompt', () async {
      for (final code in [409, 404]) {
        final tracker = CallTracker()..apply(url, _prompt(far));
        expect(await tracker.act(_Daemon(code), 'c1', callActionTrack), isTrue);
        expect(tracker.state.value, isNull);
      }
      final tracker = CallTracker()..apply(url, _prompt(far));
      expect(await tracker.act(_Daemon(500), 'c1', callActionTrack), isFalse);
      expect(tracker.state.value, isNotNull);
    });

    test('android action ids map to the call endpoints', () async {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:1","token":"tok"}]',
      });
      final payload = jsonEncode({
        'type': callPromptType,
        'url': 'http://127.0.0.1:1',
        'call_id': 'c1'
      });
      // Unreachable daemon: routed (not ignored as an unknown action) but fails.
      expect(
          await routeNotificationAction(
              actionId: 'call_track', input: null, payload: payload),
          isFalse);
      expect(
          await routeNotificationAction(
              actionId: 'bogus', input: null, payload: payload),
          isFalse);
    });
  });

  group('prompt lifecycle', () {
    test('call_state cancels the pending prompt', () {
      final tracker = CallTracker()..apply(url, _prompt(far));
      expect(tracker.state.value!.phase, CallPhase.pending);
      final other = CallEvent(
          type: callStateType, callId: 'other', state: 'declined');
      expect(tracker.apply(url, other), isFalse);
      expect(tracker.state.value, isNotNull);
      for (final s in ['declined', 'expired']) {
        tracker.apply(url, _prompt(far));
        tracker.apply(
            url, CallEvent(type: callStateType, callId: 'c1', state: s));
        expect(tracker.state.value, isNull);
      }
    });

    test('expired prompts are ignored and live ones time out', () async {
      final tracker = CallTracker();
      expect(tracker.apply(url, _prompt(1)), isFalse);
      tracker.apply(url, _prompt(DateTime.now().millisecondsSinceEpoch + 50));
      expect(tracker.state.value, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(tracker.state.value, isNull);
    });

    test('snapshot seeds a pending prompt', () {
      final tracker = CallTracker();
      expect(
          tracker.applySnapshot(
              url, {'call_id': 'c9', 'state': 'pending', 'expires_at': far}),
          isTrue);
      expect(tracker.state.value!.callId, 'c9');
      expect(tracker.applySnapshot(url, {'state': 'idle'}), isFalse);
    });

    test('android details: high importance, Track/Ignore, timeout', () {
      final d = callPromptDetails(timeoutMs: 120000).android!;
      expect(d.importance, Importance.high);
      expect(d.timeoutAfter, 120000);
      expect(d.actions!.map((a) => a.title), ['Take notes', 'Ignore']);
      expect(callNotificationId('a'), callNotificationId('a'));
      expect(callNotificationId('a'), isNot(callNotificationId('b')));
    });
  });
}
