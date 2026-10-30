import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/panel.dart';
import 'package:snippet/shell_panel.dart';

void main() {
  testWidgets('drawer docks, reuses identity, retains origin and local back',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final a = DaemonClient('https://a.invalid', 'test');
    final b = DaemonClient('https://b.invalid', 'test');
    final requests = <String, ShellPanelRequest>{};
    ShellPanelRequest? shown;
    late StateSetter update;
    late BuildContext entry;
    var active = a;
    var closed = false;
    Future<Object?> open(ShellPanelRequest request) {
      update(() => shown = requests.putIfAbsent(request.key, () => request));
      return shown!.dismissed.future;
    }

    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return ShellPanelScope(
        open: open,
        client: active,
        sessionId: 'session',
        child: Scaffold(
            body: Column(children: [
          Builder(builder: (context) {
            entry = context;
            return const Text('root');
          }),
          if (shown != null)
            Expanded(
                child: ShellPanelBody(
                    request: shown!,
                    onClose: () {
                      shown!.complete();
                      update(() => shown = null);
                    })),
        ])),
      );
    })));
    Future<void> enter() => presentScreen<void>(entry,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.task,
            panelId: 'task', builder: (context, close) {
          expect(DaemonScope.maybeOf(context), same(a));
          expect(ShellPanelScope.maybeOf(context)!.sessionId, 'session');
          return Column(children: [
            TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (nested) => TextButton(
                            onPressed: () => Navigator.of(nested).pop(),
                            child: const Text('nested back')))),
                child: const Text('nested')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('back')),
            TextButton(onPressed: close, child: const Text('close')),
          ]);
        });
    final first = enter().then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible),
        findsNothing);
    final original = shown;
    final second = enter();
    await tester.pumpAndSettle();
    expect(shown, same(original));
    expect(requests.length, 1);
    expect(closed, false);
    update(() => active = b);
    await tester.pumpAndSettle();
    expect(shown!.client, same(a));
    await tester.tap(find.text('nested'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('nested back'));
    await tester.pumpAndSettle();
    expect(shown, same(original));
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await first;
    await second;
    expect(shown, isNull);
    expect(find.text('root'), findsOneWidget);
    expect(closed, true);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('centered dialog bypasses desktop host', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    late BuildContext entry;
    await tester.pumpWidget(MaterialApp(home: ShellPanelScope(
      open: (_) => throw StateError('dialog must not dock'),
      child: Builder(builder: (context) { entry = context; return const SizedBox(); }),
    )));
    presentScreen<void>(entry, purpose: ShellPanelPurpose.generic,
      builder: (_, close) => TextButton(onPressed: close, child: const Text('dialog close')));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is ModalBarrier && w.dismissible), findsWidgets);
    await tester.tap(find.text('dialog close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile drawer remains modal even in a host', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late BuildContext entry;
    await tester.pumpWidget(MaterialApp(
        home: ShellPanelScope(
      open: (_) => throw StateError('must not dock'),
      child: Builder(builder: (context) {
        entry = context;
        return const SizedBox();
      }),
    )));
    presentScreen<void>(entry,
        style: PanelStyle.drawer,
        purpose: ShellPanelPurpose.files,
        builder: (_, close) =>
            TextButton(onPressed: close, child: const Text('mobile close')));
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier), findsWidgets);
    await tester.tap(find.text('mobile close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
