import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/notification_conversation.dart';
import 'package:snippet/screens/agent_messaging.dart';

class ThreadClient extends DaemonClient {
  ThreadClient() : super('http://localhost:1', 'test');
  @override
  WebSocketChannel events() {
    return FakeChannel();
  }

  @override
  Future<List<DirectThreadSummary>> directThreads(
          {String actorKind = 'human', String actorId = 'local'}) async =>
      [
        DirectThreadSummary.fromJson({
          'thread_id': 'persisted',
          'peer_kind': 'agent',
          'peer_id': 'actual-agent',
          'title': 'Actual thread'
        }),
      ];
  @override
  Future<List<CoordinationEvent>> agentThread(
          {required String peerId,
          String actorKind = 'human',
          String actorId = 'local',
          int afterSequence = 0,
          int limit = 100}) async =>
      [];
  @override
  Future<void> markAgentThreadRead(
      {required String peerId,
      String actorKind = 'human',
      String actorId = 'local'}) async {}
}

class FakeChannel extends StreamChannelMixin implements WebSocketChannel {
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = FakeSink(controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class FakeSink implements WebSocketSink {
  FakeSink(this.sink);
  final StreamSink sink;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => sink.close();
  @override
  Future get done => sink.done;
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  testWidgets(
      'persisted ID navigates to resolved agent, unknown ID never pushes',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Home'));
    })));
    final client = ThreadClient();
    expect(
        await openNotificationConversation(
            context, client, 'recipient-session'),
        false);
    await tester.pump();
    expect(find.byType(AgentThreadScreen), findsNothing);
    expect(
        await openNotificationConversation(context, client, 'persisted'), true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen =
        tester.widget<AgentThreadScreen>(find.byType(AgentThreadScreen));
    expect(screen.agentId, 'actual-agent');
    expect(screen.agentName, 'Actual thread');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
