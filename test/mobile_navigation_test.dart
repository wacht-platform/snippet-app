import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _chats = 'Add a machine to begin.';
const _tasks = 'Add a machine to see its tasks.';
const _agents = 'Add a machine to see its agents.';
const _settings = 'Add a machine to configure it.';

Finder _tab(String label) => find.descendant(
    of: find.byType(SidebarMobileBar), matching: find.text(label));

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

void _only(String shown) {
  for (final text in [_chats, _tasks, _agents, _settings]) {
    expect(find.text(text), text == shown ? findsOneWidget : findsNothing,
        reason: 'expected only "$shown" to be showing');
  }
}

void main() {
  testWidgets('the phone starts on Chats and each tab opens its destination',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      await _pumpShell(tester);
      _only(_chats);

      await tester.tap(_tab('Tasks'));
      await tester.pumpAndSettle();
      _only(_tasks);

      await tester.tap(_tab('Agents'));
      await tester.pumpAndSettle();
      _only(_agents);

      // Settings keeps the tab bar; with no machine there is nothing to create.
      await tester.tap(_tab('Settings'));
      await tester.pumpAndSettle();
      _only(_settings);
      expect(find.byTooltip('Add machine'), findsOneWidget);
      expect(_tab('Chats'), findsOneWidget);

      // Back returns to the previous tab.
      expect(find.byTooltip('Back'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _only(_agents);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('swiping walks the tabs in order and stops at either end',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      await _pumpShell(tester);
      Future<void> swipe(double dx) async {
        await tester.fling(find.byType(PageView), Offset(dx, 0), 1000);
        await tester.pumpAndSettle();
      }

      _only(_chats);
      await swipe(300);
      _only(_chats);
      for (final next in [_tasks, _agents, _settings]) {
        await swipe(-300);
        _only(next);
      }
      await swipe(-300);
      _only(_settings);
      for (final back in [_agents, _tasks, _chats]) {
        await swipe(300);
        _only(back);
      }

      // Back on the first tab leaves the app without blocking.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('back unwinds tab history one step at a time', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      await _pumpShell(tester);

      await tester.tap(_tab('Tasks'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Settings'));
      await tester.pumpAndSettle();
      _only(_settings);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _only(_tasks);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _only(_chats);

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

      await tester.tap(_tab('Agents'));
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
