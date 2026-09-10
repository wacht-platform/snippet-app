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

  testWidgets('PaneTabStrip lays out with multiple tabs and actions',
      (tester) async {
    await pumpAsMounted(
      tester,
      PaneTabStrip(
        tabs: const [
          PaneTab(label: 'Lanes', icon: 'layers'),
          PaneTab(label: 'Usage', icon: 'activity'),
        ],
        activeIndex: 1,
        onSelect: (_) {},
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.close))],
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
}
