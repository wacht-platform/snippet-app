import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/notifications.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('messages come from Snippet and a chat keeps one stable id', () {
    final details = sessionNotificationDetails(
        payload: {'session': 's', 'url': 'u'},
        title: 'Chat',
        body: 'Hello',
        kind: 'message');
    final style =
        details.android!.styleInformation as MessagingStyleInformation;
    expect(style.messages!.single.person?.name, 'Snippet');
    expect(sessionNotificationId('u', 's'), sessionNotificationId('u', 's'));
    expect(sessionNotificationId('u', 's'),
        isNot(sessionNotificationId('u', 't')));
    expect(sessionNotificationId('u', 's'), greaterThanOrEqualTo(0x40000000));
  });

  test('maps durable events to grouped Android and threaded Darwin details',
      () {
    final payload = <String, dynamic>{
      'url': 'https://machine',
      'session': 'session-1',
      'kind': 'waiting',
      'attention': {'type': 'approval'},
    };
    final previous = MessagingStyleInformation(const Person(name: 'Snippet'),
        messages: [Message('prior', DateTime(2024), null)]);
    final details = sessionNotificationDetails(
        payload: payload,
        title: 'Run',
        body: '**One**\n`two`\nthree',
        kind: 'waiting',
        previous: previous);
    expect(details.android!.channelId, 'snippet_needs_input');
    expect(details.android!.importance, Importance.high);
    expect(details.android!.groupKey, 'snippet_machine_https://machine');
    expect(details.android!.actions!.map((a) => a.title), ['Approve', 'Deny']);
    expect(details.macOS!.threadIdentifier, 'session-1');
    expect(details.macOS!.categoryIdentifier, 'approval');
    final style =
        details.android!.styleInformation as MessagingStyleInformation;
    expect(style.messages!.map((m) => m.text), ['prior', 'One two three']);
  });

  test('question and message reply actions; passive status details', () {
    final question = sessionNotificationDetails(payload: {
      'session': 's',
      'attention': {'type': 'question'}
    }, title: 'Q', body: 'answer', kind: 'waiting');
    expect(question.android!.actions!.single.inputs, isNotEmpty);
    expect(question.macOS!.categoryIdentifier, 'question');
    expect(question.macOS!.interruptionLevel, InterruptionLevel.timeSensitive);
    final done = sessionNotificationDetails(
        payload: {'session': 's'}, title: 'Done', body: 'ok', kind: 'done');
    expect(done.android!.channelId, 'snippet_updates');
    expect(done.android!.actions, isEmpty);
    expect(done.macOS!.interruptionLevel, InterruptionLevel.passive);
    expect(
        plainNotificationText(
            '**Bold** and `code` [link](https://example.test)'),
        'Bold and code link');
  });

  test('routes approve, deny, question answer and message reply', () async {
    SharedPreferences.setMockInitialValues({
      'instances': jsonEncode([
        {'name': 'Local', 'url': 'http://127.0.0.1:9090', 'token': 'tok'}
      ])
    });
    final ch = _Channel();
    final sentKinds = <String>[];
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
      Timer(const Duration(milliseconds: 10), () => ch.incoming.add('{}'));
      return ch;
    };
    addTearDown(() => DaemonClient.wsConnector = null);
    Future<void> route(String action,
        {String? input, String? attention}) async {
      final payload = jsonEncode({
        'url': 'http://127.0.0.1:9090',
        'session': 's',
        if (attention != null) 'attention': {'type': attention}
      });
      expect(
          await routeNotificationAction(
              actionId: action, input: input, payload: payload),
          isTrue);
      sentKinds
          .add((jsonDecode(ch.sent.last as String) as Map)['kind'] as String);
    }

    await route('approve');
    await route('deny');
    await route('reply', input: 'answer', attention: 'question');
    await route('reply', input: 'reply', attention: 'message');
    expect(sentKinds, ['approve', 'deny', 'answer', 'user_message']);
  });
}

class _Channel extends StreamChannelMixin implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  @override
  Stream get stream => incoming.stream;
  @override
  late final WebSocketSink sink = _Sink(this);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _Sink implements WebSocketSink {
  _Sink(this.channel);
  final _Channel channel;
  @override
  void add(dynamic data) => channel.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}
