import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';
import 'package:snippet/screens/shell_rail.dart';

/// The file panel's two header actions must open SMALL POPOVERS anchored to
/// their own buttons.
///
/// Both used to take over the window — the "+" a centered modal sheet, the
/// search a centered 640px card — which read as leaving the panel rather than
/// acting inside it, and put the results nowhere near the control that asked
/// for them. These tests pin the replacement, because I cannot run desktop in
/// this environment: they are the only evidence the anchoring actually works.
class _FakeFsClient extends DaemonClient {
  _FakeFsClient() : super('https://daemon.invalid', 'test-token');

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': path ?? '/workspace',
        'parent': null,
        'entries': [
          {
            'name': 'README.md',
            'path': '/workspace/README.md',
            'is_dir': false,
            'git': true,
          },
          {'name': 'lib', 'path': '/workspace/lib', 'is_dir': true, 'git': true},
        ],
      });
}

void main() {
  /// Run [body] with the shell treated as DESKTOP.
  ///
  /// `kMobile` derives from the target platform, which flutter_test leaves as a
  /// mobile one — so without this the bottom-sheet branch is what runs and the
  /// popover path is never reached, letting the test pass while the feature was
  /// absent.
  ///
  /// The override is cleared in a `finally` INSIDE the test body, not via
  /// `tearDown`/`addTearDown`: the framework asserts no foundation debug
  /// variable is left set when the body ends, and both of those run after that
  /// check.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    // Wider than kDesktopBreakpoint (900), so the desktop branches are live.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: kSidebarWidth,
            height: 900,
            child: FileTreeSidebarPanel(
              client: _FakeFsClient(),
              workspacePath: '/workspace',
              onOpenFile: (_, __) {},
            ),
          ),
        ),
      ),
    ));
    // The listing must arrive: "+" is disabled until it does.
    await tester.pumpAndSettle();
  }

  testWidgets('the + action opens a popover anchored under its button',
      (tester) async {
    await onDesktop(() async {
      await pumpPanel(tester);

      final plus = find.byTooltip('New file or folder');
      expect(plus, findsOneWidget);
      await tester.tap(plus);
      await tester.pumpAndSettle();

      expect(find.text('New file'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      // A popover, not the modal sheet this replaced — that drew a `Dialog`.
      expect(find.byType(Dialog), findsNothing);

      // Anchored: it hangs BELOW the button that summoned it and stays in the
      // panel's own column instead of centering across the window.
      final button = tester.getRect(plus);
      final item = tester.getRect(find.text('New file'));
      expect(item.top, greaterThan(button.bottom - 1));
      expect(item.left, lessThan(kSidebarWidth));
    });
  });

  testWidgets('search opens a popover sized to the sidebar, not the window',
      (tester) async {
    await onDesktop(() async {
      await pumpPanel(tester);

      final search = find.byTooltip('Search files');
      await tester.tap(search);
      // Not `pumpAndSettle`: the field autofocuses, and its cursor blink keeps
      // scheduling frames, so settling would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Search files'), findsOneWidget); // the field's hint
      expect(find.byType(Dialog), findsNothing);

      final field = tester.getRect(find.byType(TextField));
      // Inside the sidebar column. The card this replaced was 640px wide and
      // centered, so on a 1600px window its left edge sat around 480 — this
      // assertion is what distinguishes the two.
      expect(field.left, lessThan(kSidebarWidth));
      expect(field.right, lessThan(kSidebarWidth));
      // Under the button, not behind a centered overlay.
      expect(field.top, greaterThan(tester.getRect(search).bottom - 1));
    });
  });
}
