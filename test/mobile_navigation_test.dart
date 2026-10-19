import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/notifications.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _chats = 'Add a machine to begin.';
const _tasks = 'Add a machine to see its tasks.';
const _agents = 'Add a machine to see its agents.';
const _settings = 'Add a machine to configure it.';

Finder _visible(Finder f) => f.hitTestable();

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(390, 844) * 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const DesktopShell(),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('with no machine the phone shows only the connect welcome',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      await _pumpShell(tester);
      expect(find.text('Connect your computer'), findsOneWidget);
      expect(_visible(find.text('Scan or paste')), findsOneWidget);
      expect(find.byType(MobileTopBar), findsNothing);
      for (final text in [_chats, _tasks, _agents, _settings]) {
        expect(find.text(text), findsNothing);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('notification session replaces chat history and reuses its tab',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) =>
        _FakeWebSocketChannel();
    addTearDown(() => DaemonClient.wsConnector = null);
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"},{"name":"Other","url":"http://127.0.0.1:9091","token":"other"}]',
      });
      await _pumpShell(tester);
      Future<void> pump() async {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      sidebar.onOpenSession('old', 'Old session', null);
      await pump();
      sidebar.onOpenSession('target', 'Target session', null);
      await pump();
      final before = tester.widget<MobileShell>(find.byType(MobileShell));
      final targetBody = before.activeTabBody;
      sidebar.onOpenSession('old', 'Old session', null);
      await pump();

      void notify(String url) => onNotifTap!({
            'url': url,
            'session': 'target',
            'title': 'Target session',
          });
      notify('http://127.0.0.1:9090');
      await pump();
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).activeTabBody?.key,
          targetBody?.key);
      notify('http://127.0.0.1:9090');
      await pump();
      await tester.binding.handlePopRoute();
      await pump();
      var shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isTrue);
      expect(shell.mobileHome, MobileHome.chats);
      expect(shell.canPopRoute, isFalse);

      notify('http://127.0.0.1:9091');
      await pump();
      shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isFalse);
      expect(shell.activeTabBody?.key, isNot(targetBody?.key));
      await tester.binding.handlePopRoute();
      await pump();
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).chatsOpen, isTrue);
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).canPopRoute, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('back from a session opened on Agents returns to Agents',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) =>
        _FakeWebSocketChannel();
    addTearDown(() => DaemonClient.wsConnector = null);
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      });
      await _pumpShell(tester);

      await tester.tap(_visible(find.byTooltip('Menu')).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Agents').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AgentsSidebarPanel), findsOneWidget);

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      sidebar.onOpenSession('test-session-1', 'Agent Task Session', null);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Agent Task Session'), findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final mobileShell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(mobileShell.chatsOpen, isTrue);
      expect(mobileShell.mobileHome, MobileHome.agents);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _FakeWebSocketSink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamSink _sink;
  _FakeWebSocketSink(this._sink);
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
  @override
  Future get done => _sink.done;
}
