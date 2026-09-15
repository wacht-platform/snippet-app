import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/screens/git.dart';
import 'package:snippet/widgets.dart';

/// Regression tests for pane body layout.
///
/// Both cover the same class of bug: a child that shrink-wraps under LOOSE
/// constraints. `_paneView` puts pane bodies in a `Stack`, whose non-positioned
/// children receive loose constraints and are aligned to the top-left. A widget
/// that sizes to its content therefore sits in the corner instead of filling
/// the surface it was handed — and `flutter analyze` cannot see it, because
/// nothing is malformed; the geometry is simply wrong.
class _FakeGitClient extends DaemonClient {
  _FakeGitClient(this.patch) : super('https://daemon.invalid', 'test-token');

  final String patch;

  @override
  Future<String> gitDiff(String session,
          {String? file, bool staged = false, bool untracked = false}) async =>
      patch;
}

void main() {
  // The pane's own shape: a sized box whose child is a Stack, exactly as
  // `_paneView` supplies it. Mounting directly in the sized box would give TIGHT
  // constraints and hide the bug — that is a test artefact, not the real case.
  Future<void> pumpInPane(WidgetTester tester, Widget child,
      {double width = 600, double height = 400}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: Stack(children: [child]),
        ),
      ),
    ));
  }

  testWidgets('EmptyState centres itself in the pane body', (tester) async {
    await pumpInPane(
      tester,
      const EmptyState(
        icon: 'layers',
        title: 'No delegated lanes',
        body: 'Parallel agent work will appear here when started.',
      ),
    );

    expect(tester.takeException(), isNull);

    // The content block should sit in the middle of the pane it was given, not
    // pinned to its top-left corner.
    final content = tester.getRect(find.byType(Column).first);
    expect(content.center.dx, closeTo(300, 1));
    expect(content.center.dy, closeTo(200, 1));
  });

  testWidgets('a narrow diff still fills the pane width', (tester) async {
    // Every line is far narrower than the pane, which is precisely when a
    // shrink-wrapping body collapses to the widest line instead of filling.
    final client = _FakeGitClient('alpha\n+beta\n');

    await pumpInPane(
      tester,
      GitFileDiffView(
        client: client,
        sessionId: 's',
        file: 'notes.txt',
        staged: false,
        untracked: false,
        embedded: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('alpha'), findsOneWidget);

    // `IntrinsicWidth` is what sizes the diff to its widest line; the pane-width
    // floor is what stops that from being narrower than the pane.
    expect(tester.getSize(find.byType(IntrinsicWidth)).width, 600);
  });

  testWidgets('a wide diff scrolls instead of being clipped', (tester) async {
    // The floor must not cap the content: a line wider than the pane keeps its
    // natural width so the horizontal scroll view can reach it.
    final long = 'x' * 400;
    final client = _FakeGitClient('$long\n+short\n');

    await pumpInPane(
      tester,
      GitFileDiffView(
        client: client,
        sessionId: 's',
        file: 'wide.txt',
        staged: false,
        untracked: false,
        embedded: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(IntrinsicWidth)).width, greaterThan(600));
  });
}
