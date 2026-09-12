import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/widgets.dart';

/// Widget-lifetime regression tests.
///
/// These cover a defect class `flutter analyze` and a green build are BOTH
/// structurally blind to, and which only fires at runtime on a real device:
///
///   A `late final AnimationController x = AnimationController(...)` initialiser
///   is LAZY — it runs on first access. If `build` never reads it (a static
///   status, a widget unmounted before its first frame), then `dispose` becomes
///   the first access and constructs the controller while the element is being
///   unmounted:
///
///     Element._debugCheckStateIsActiveForAncestorLookup
///     TickerMode.getValuesNotifier
///     AnimationController.<init>
///     _StatusDotState._c            <- the lazy init, triggered from dispose
///     _StatusDotState.dispose
///
///   The fix is to assign in `initState`, so creation never depends on the order
///   in which other methods happen to touch it.
void main() {
  Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('StatusDot mounts and unmounts without touching its ticker',
      (tester) async {
    // 'online' is the case that crashed: `build` returns a plain Container and
    // never reads the controller, so disposal was the first access.
    await mount(tester, const StatusDot(status: 'online'));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusDot unmounts cleanly for every status', (tester) async {
    for (final status in ['online', 'offline', 'checking', 'running']) {
      await mount(tester, StatusDot(status: status));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull,
          reason: 'dispose threw for status "$status"');
    }
  });

  testWidgets('StatusDot animated statuses still animate', (tester) async {
    // The fix must not disable the animation for the statuses that use it.
    await mount(tester, const StatusDot(status: 'running'));
    expect(tester.takeException(), isNull);
    // Scoped to the dot's own subtree: MaterialApp's route transition supplies
    // its own FadeTransitions, so an unscoped finder matches those too.
    expect(
      find.descendant(
          of: find.byType(StatusDot), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
