import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('sends one frame to the resolved machine and session', () async {
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"},{"name":"Other","url":"http://127.0.0.1:9091","token":"other"}]',
    });
    final ch = _Channel();
    Uri? seen;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
      seen = uri;
      Timer(const Duration(milliseconds: 20),
          () => ch.incoming.add('{"wire":"snapshot"}'));
      return ch;
    };
    addTearDown(() => DaemonClient.wsConnector = null);

    final ok = await quickSendForPayload(
      {'url': 'http://127.0.0.1:9091', 'session': 's-1'},
      const QuickAnswer('Run it'),
    );

    expect(ok, isTrue);
    expect(seen!.port, 9091);
    expect(seen!.queryParameters['session'], 's-1');
    final frame = jsonDecode(ch.sent.single as String) as Map;
    expect(frame['kind'], 'answer');
    expect(frame['value'], 'Run it');
    expect(frame['nonce'], isNotEmpty);
    expect(ch.closed, isTrue);
  });

  test('unknown machine sends nothing', () async {
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"A","url":"http://a","token":"t"},{"name":"B","url":"http://b","token":"t"}]',
    });
    final ok = await quickSendForPayload(
        {'url': 'http://c', 'session': 's'}, const QuickApprove());
    expect(ok, isFalse);
  });
}

class _Channel extends StreamChannelMixin implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  bool closed = false;
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
  _Sink(this.ch);
  final _Channel ch;
  @override
  void add(dynamic data) => ch.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async => ch.closed = true;
  @override
  Future get done => Future.value();
}
