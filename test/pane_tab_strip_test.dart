import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/screens/shell_nav.dart';

/// Layout regression tests for shell chrome.
///
/// These exist because `flutter analyze` is structurally blind to the class of
/// bug they cover. A `Column` with `crossAxisAlignment: stretch` placed in a
/// `Row` receives the Row's *unbounded* cross-axis constraint, so `stretch`
/// resolves to `w = Infinity` and throws during `performLayout()` — at runtime,
/// on a real device, with a clean analyze and a green build.
///
/// Mounting matters. In the app the strip is a child of a `Column`, which gives
/// it a BOUNDED width. Mounting it directly in a `Row` would hand it unbounded
/// width, and its internal `Spacer` would fail — a test artefact, not the bug
/// under test.
void main() {
  Future<void> pumpAsMounted(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Column, exactly as the app nests it (PaneTabStrip <- Column).
          body: Column(children: [child]),
        ),
      ),
    );
  }

  testWidgets('PaneTabStrip lays out in a bounded-width parent',
      (tester) async {
    await pumpAsMounted(
      tester,
      PaneTabStrip(
        tabs: const [PaneTab(label: 'Checkpoints', icon: 'history')],
        activeIndex: 0,
      ),
    );

    // A constraint error surfaces as a caught exception, not a failed matcher,
    // so it has to be asserted explicitly.
    expect(tester.takeException(), isNull);
    expect(find.text('Checkpoints'), findsOneWidget);
  });

  testWidgets('PaneTabStrip lays out with multiple tabs', (tester) async {
    await pumpAsMounted(
      tester,
      PaneTabStrip(
        tabs: const [
          PaneTab(label: 'Lanes', icon: 'layers'),
          PaneTab(label: 'Usage', icon: 'activity'),
        ],
        activeIndex: 1,
        onSelect: (_) {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Lanes'), findsOneWidget);
    expect(find.text('Usage'), findsOneWidget);
  });

  testWidgets('PaneTabStrip survives an empty tab list', (tester) async {
    await pumpAsMounted(tester, const PaneTabStrip(tabs: [], activeIndex: 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a tab does not shift the layout', (tester) async {
    Future<Rect> rectFor(int active) async {
      await pumpAsMounted(
        tester,
        PaneTabStrip(
          tabs: const [
            PaneTab(label: 'Lanes', icon: 'layers'),
            PaneTab(label: 'Usage', icon: 'activity'),
          ],
          activeIndex: active,
        ),
      );
      return tester.getRect(find.text('Lanes'));
    }

    // The indicator is a reserved 2px row on EVERY tab, so selecting must not
    // move the label — otherwise tabs jitter horizontally as you click them.
    expect(await rectFor(0), equals(await rectFor(1)));
  });

  group('paneTabBelongsInGroup', () {
    bool belongs({
      required String? rootKey,
      required String tabKey,
      String? groupSessionKey,
      required bool isAuxiliary,
    }) =>
        paneTabBelongsInGroup(
          rootKey: rootKey,
          tabKey: tabKey,
          groupSessionKey: groupSessionKey,
          isAuxiliary: isAuxiliary,
        );

    test('a pane with a root shows it and the content filed under it', () {
      expect(belongs(rootKey: 's1', tabKey: 's1', isAuxiliary: false), isTrue);
      expect(
          belongs(
              rootKey: 's1',
              tabKey: 'f1',
              groupSessionKey: 's1',
              isAuxiliary: true),
          isTrue);
    });

    test('a pane with a root hides a tab from another group', () {
      expect(
          belongs(
              rootKey: 's1',
              tabKey: 'f2',
              groupSessionKey: 's2',
              isAuxiliary: true),
          isFalse);
    });

    test('a rootless pane still shows its auxiliary content', () {
      // A file dragged into the secondary pane keeps the group key of the
      // conversation it came from, which lives in the other pane — so the
      // destination has no root. Requiring one here made the tab vanish.
      expect(
          belongs(
              rootKey: null,
              tabKey: 'f1',
              groupSessionKey: 's1',
              isAuxiliary: true),
          isTrue);
    });

    test('a rootless pane never re-renders a workspace tab', () {
      // The regression: after its session is dragged to the other pane, that
      // pane holds no root. Admitting every docked tab here made the abandoned
      // pane paint a full duplicate of a top-level tab the window bar owns.
      expect(belongs(rootKey: null, tabKey: 'mc', isAuxiliary: false), isFalse);
      expect(
          belongs(
              rootKey: null,
              tabKey: 'f1',
              groupSessionKey: 's1',
              isAuxiliary: false),
          isFalse);
    });
  });
}
