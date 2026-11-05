import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/local_service.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_welcome.dart';

const _local =
    Instance(name: 'laptop', url: 'http://127.0.0.1:8787', token: 't');

Future<void> _pump(
  WidgetTester t,
  TargetPlatform p, {
  ValueChanged<Instance>? onReady,
  Instance? found,
  bool up = false,
  Future<Instance> Function(String)? remote,
  Future<InstallResult> Function(void Function(InstallStage, String))? install,
  bool installed = false,
}) async {
  debugDefaultTargetPlatformOverride = p;
  t.view.physicalSize = const Size(1200, 900);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ShellWelcomeView(
        onAddInstance: () {},
        onConnected: onReady,
        probeLocal: () async => found,
        probeRunning: () async => up,
        recheck: const Duration(hours: 1),
        connectRemote: remote ?? (_) async => _local,
        install: install ?? (_) async => const InstallResult.failed('unused'),
        binaryInstalled: () => installed,
      ),
    ),
  ));
  await t.pump();
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('desktop shows this computer and another computer', (t) async {
    await _pump(t, TargetPlatform.macOS);
    expect(find.text('Snippet needs a service'), findsOneWidget);
    expect(find.text('On this computer'), findsOneWidget);
    expect(find.text('On another computer'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hovering a side widens it', (t) async {
    await _pump(t, TargetPlatform.macOS);
    final idle = t.getSize(find.byKey(const ValueKey('welcome-left'))).width;
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(900, 400));
    await g.moveTo(const Offset(900, 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    final overRight =
        t.getSize(find.byKey(const ValueKey('welcome-left'))).width;
    expect(overRight, lessThan(idle));
    await g.moveTo(const Offset(200, 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    final overLeft =
        t.getSize(find.byKey(const ValueKey('welcome-left'))).width;
    expect(overLeft, greaterThan(idle));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a running local service offers one click connect', (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.macOS,
        found: _local, up: true, onReady: (i) => got = i);
    expect(got, isNull);
    expect(find.text('Snippet is running here'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    await t.tap(find.text('Connect').first);
    expect(got, _local);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('running but unreadable tells the user to paste the link',
      (t) async {
    await _pump(t, TargetPlatform.macOS, up: true);
    expect(find.textContaining('cannot read its link'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('installed but stopped offers to start it', (t) async {
    await _pump(t, TargetPlatform.macOS, installed: true);
    expect(find.text('Start the service'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('install success hands the instance over', (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.linux,
        onReady: (i) => got = i,
        install: (on) async {
          on(InstallStage.download, 'downloading snippet.tar.gz');
          return const InstallResult.ok(_local);
        });
    await t.tap(find.text('Install'));
    await t.pump();
    expect(got, _local);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('install failure shows the reason and the manual command',
      (t) async {
    await _pump(t, TargetPlatform.linux,
        install: (_) async =>
            const InstallResult.failed('glibc 2.31 is too old'));
    await t.tap(find.text('Install'));
    await t.pump();
    await t.pump();
    expect(find.text('glibc 2.31 is too old'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(installCommand), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('install that cannot auto-start warns before continuing',
      (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.linux,
        onReady: (i) => got = i,
        install: (_) async => const InstallResult.ok(_local, autoStart: false));
    await t.tap(find.text('Install'));
    await t.pump();
    await t.pump();
    expect(got, isNull);
    expect(find.text('Not set to start automatically'), findsOneWidget);
    await t.tap(find.text('Continue'));
    expect(got, _local);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('pasting a link connects to the remote', (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.macOS, onReady: (i) => got = i);
    await t.enterText(find.byType(TextField), 'https://box.example?token=abc');
    await t.tap(find.text('Connect').last);
    await t.pump();
    await t.pump();
    expect(got, _local);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a bad remote link shows the error and stays', (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.macOS,
        onReady: (i) => got = i, remote: (_) async => throw 'refused');
    await t.enterText(find.byType(TextField), 'nonsense');
    await t.tap(find.text('Connect').last);
    await t.pump();
    await t.pump();
    expect(got, isNull);
    expect(find.text('Could not connect: refused'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('windows gets terminal commands, no install button', (t) async {
    await _pump(t, TargetPlatform.windows);
    expect(find.text('Install'), findsNothing);
    expect(find.text(installCommand), findsOneWidget);
    expect(find.text(enableCommand), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone shows the remote steps only', (t) async {
    await _pump(t, TargetPlatform.android);
    expect(find.text('On another computer'), findsNothing);
    expect(find.text('Scan QR code'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
