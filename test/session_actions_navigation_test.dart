import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/processes.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openActions(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  addTearDown(() => DaemonClient.wsConnector = null);
  SharedPreferences.setMockInitialValues({
    'instances': '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: const DesktopShell(),
  ));
  await _pump(tester);
  tester.widget<Sidebar>(find.byType(Sidebar)).onOpenSession('actions-test', 'Action session', null);
  await _pump(tester);
  await tester.tap(find.text('Action session').first);
  await _pump(tester);
  expect(find.text('Actions'), findsOneWidget);
}

void _sessionUnchanged(WidgetTester tester) {
  final shell = tester.widget<MobileShell>(find.byType(MobileShell));
  expect(shell.chatsOpen, isFalse);
  expect(shell.canPopRoute, isTrue);
}

void main() {
  for (final desktop in [false, true]) {
    for (final sessionId in ['mission-control', 'mission-control/session.json']) {
      testWidgets('MC chat $sessionId has no Tasks entry (${desktop ? 'desktop' : 'mobile'})',
          (tester) async {
        debugDefaultTargetPlatformOverride =
            desktop ? TargetPlatform.linux : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        DaemonClient.wsConnector =
            (uri, {connectTimeout, pingInterval}) => _Socket();
        addTearDown(() => DaemonClient.wsConnector = null);
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            desktop ? const Size(1440, 900) : const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: SessionScreen(
            client: DaemonClient('http://127.0.0.1:9090', 'tok'),
            sessionId: sessionId,
            title: 'Mission Control',
            onMenu: () {},
          ),
        ));
        await _pump(tester);
        expect(find.byType(SessionScreen), findsOneWidget);
        expect(find.byTooltip('Tasks'), findsNothing);
        expect(find.text('Tasks'), findsNothing);
        expect(find.byTooltip('Shell'), findsNothing);
        if (!desktop) {
          await tester.tap(find.text('Mission Control').first);
          await _pump(tester);
          expect(find.text('Actions'), findsOneWidget);
          expect(find.text('Scheduled'), findsOneWidget);
          expect(find.text('Tasks'), findsNothing);
          expect(find.byTooltip('Tasks'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('Android back closes root actions without consuming session history', (tester) async {
    await _openActions(tester, TargetPlatform.android);
    await tester.binding.handlePopRoute();
    await _pump(tester);
    expect(find.text('Actions'), findsNothing);
    _sessionUnchanged(tester);
    await tester.binding.handlePopRoute();
    await _pump(tester);
    expect(tester.widget<MobileShell>(find.byType(MobileShell)).chatsOpen, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} nested action returns to parent before closing', (tester) async {
      await _openActions(tester, platform);
      await tester.ensureVisible(find.text('Processes'));
      await tester.tap(find.text('Processes'));
      await _pump(tester);
      expect(find.byType(ProcessesScreen), findsOneWidget);
      if (platform == TargetPlatform.android) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.descendant(
          of: find.byType(ProcessesScreen),
          matching: find.byTooltip('Back'),
        ));
      }
      await _pump(tester);
      expect(find.byType(ProcessesScreen), findsNothing);
      expect(find.text('Actions'), findsOneWidget);
      _sessionUnchanged(tester);
      await tester.tap(find.byTooltip('Close').last);
      await _pump(tester);
      expect(find.text('Actions'), findsNothing);
      _sessionUnchanged(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
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
  final StreamSink _sink;
  _Sink(this._sink);
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
