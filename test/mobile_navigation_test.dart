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

void main() {
  testWidgets('mobile shell starts on Agents and tabs switch to the correct destinations',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});

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

      // 1. Initial destination is Agents (index 0)
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);
      expect(find.text('Add a machine to begin.'), findsNothing);

      // 2. Tap Chats tab (index 1)
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to begin.'), findsOneWidget);
      expect(find.text('Add a machine to see its agents.'), findsNothing);

      // 3. Tap Agents tab again (index 0)
      await tester.tap(find.text('Agents'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to see its agents.'), findsOneWidget);
      expect(find.text('Add a machine to begin.'), findsNothing);

      // 4. Tap Settings tab (index 2)
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to configure it.'), findsOneWidget);

      // 5. In Settings: machine picker is in header, bottom bar is hidden
      expect(find.byTooltip('Add machine'), findsOneWidget);
      expect(find.byTooltip('Search'), findsNothing);
      expect(find.byTooltip('New'), findsNothing);

      // 6. System back in Settings returns to Agents and restores bottom bar
      expect(find.byTooltip('Back'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Add a machine to see its agents.'), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('New'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'swiping left and right navigates across agents, chats, and settings',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});

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

      // 1. Starts on Agents
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);

      // Swiping right when at index 0 does nothing (clamped)
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);

      // 2. Swipe left from Agents -> navigates to Chats
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to begin.'), findsOneWidget);

      // 3. Swipe left from Chats -> navigates to Settings
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to configure it.'), findsOneWidget);

      // Swiping left when at index 2 does nothing (clamped)
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to configure it.'), findsOneWidget);

      // 4. Swipe right from Settings -> navigates back to Chats
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to begin.'), findsOneWidget);

      // 5. Swipe right from Chats -> navigates back to Agents
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);

      // 6. System back on Agents triggers app close/minimize without blocking
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'routing history: switching to settings from chats and back pressing returns to chats',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});

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

      // Starts on Agents
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);

      // Switch to Chats
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to begin.'), findsOneWidget);

      // Switch to Settings from Chats
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to configure it.'), findsOneWidget);

      // Back press from Settings should return to Chats (not jump to Agents)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to begin.'), findsOneWidget);
      expect(find.text('Add a machine to see its agents.'), findsNothing);

      // Back press from Chats should return to Agents
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Add a machine to see its agents.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'routing history: opening a session from agent and back pressing returns to agent',
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

      // 1. Starts on Agents
      expect(find.byType(AgentsSidebarPanel), findsOneWidget);

      // Find Sidebar and simulate onOpenSession from agent screen
      final sidebarFinder = find.byType(Sidebar);
      expect(sidebarFinder, findsOneWidget);
      final sidebar = tester.widget<Sidebar>(sidebarFinder);
      sidebar.onOpenSession('test-session-1', 'Agent Task Session', null);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Session is now open
      expect(find.text('Agent Task Session'), findsWidgets);

      // 2. Back press from session should return directly to Agents (last screen), not jump to Chats
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Sidebar is restored and user is back on Agents (not Chats)
      final mobileShell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(mobileShell.chatsOpen, isTrue);
      expect(mobileShell.mobileHome, MobileHome.agents);

      // 3. Back press from Agents triggers app close/minimize
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));

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
