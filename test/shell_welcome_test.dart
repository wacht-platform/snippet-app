import 'package:flutter/foundation.dart';
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
  VoidCallback? onAdd,
  ValueChanged<Instance>? onReady,
  Future<Instance?> Function()? probe,
  Future<InstallResult> Function(void Function(InstallStage, String))? install,
  bool installed = false,
}) async {
  debugDefaultTargetPlatformOverride = p;
  t.view.physicalSize = const Size(1200, 900);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
        body: ShellWelcomeView(
      onAddInstance: onAdd ?? () {},
      onLocalReady: onReady,
      probeLocal: probe ?? () async => null,
      install: install ?? (_) async => const InstallResult.failed('unused'),
      binaryInstalled: () => installed,
    )),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('desktop explains the service and offers install or remote',
      (t) async {
    var added = 0;
    await _pump(t, TargetPlatform.macOS, onAdd: () => added++);
    expect(find.text('Snippet needs a service'), findsOneWidget);
    expect(find.text('Install on this computer'), findsOneWidget);
    await t.tap(find.text('Connect to a remote'));
    expect(added, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a running local service connects without a click', (t) async {
    Instance? got;
    await _pump(t, TargetPlatform.macOS,
        probe: () async => _local, onReady: (i) => got = i);
    expect(got, _local);
    expect(find.text('Connecting to this computer'), findsOneWidget);
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
    await t.tap(find.text('Install on this computer'));
    await t.pump();
    expect(got, _local);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('install failure shows the reason and the manual command',
      (t) async {
    await _pump(t, TargetPlatform.linux,
        install: (_) async =>
            const InstallResult.failed('glibc 2.31 is too old'));
    await t.tap(find.text('Install on this computer'));
    await t.pump();
    await t.pump();
    expect(find.text('glibc 2.31 is too old'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(installCommand), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('windows has no install button', (t) async {
    await _pump(t, TargetPlatform.windows);
    expect(find.text('Snippet needs a service'), findsOneWidget);
    expect(find.text('Install on this computer'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone shows the remote steps only', (t) async {
    await _pump(t, TargetPlatform.android);
    expect(find.text('Install on this computer'), findsNothing);
    expect(find.text('Scan or paste'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
