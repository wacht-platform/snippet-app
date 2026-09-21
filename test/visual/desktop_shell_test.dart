import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

/// The desktop shell, rendered as a FRESH INSTALL.
///
/// `DesktopShell` builds its own `DaemonClient` from the saved instance, so
/// there is no seam to inject a fake — the shell decides what to talk to. The
/// state used here is the one that needs no daemon at all: an EMPTY instance
/// store, which is what the app shows on a first run.
///
/// That state is genuinely inert, and it is worth stating why, because it is the
/// only reason a golden of this screen is honest:
///
///  * `_active` and `_client` stay null, so `_connectEventsWatch` takes its
///    `_client == null` branch and **never opens the socket**.
///  * `_loadSessions` takes its `c == null` branch and returns without a request.
///  * `_refreshHealth` maps over an empty list — `Future.wait([])` issues nothing.
///
/// The remaining timer (`_startSessionsTicker`) is cancelled by `dispose`, so
/// unmounting before the test ends is enough.
///
/// What this does NOT cover: the populated sidebar, tabs, or any instance-backed
/// pane. Those need a live daemon and cannot be faked through this widget.
void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    testWidgets('desktop shell, fresh install ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        // No saved instances: the first-run state.
        SharedPreferences.setMockInitialValues({});

        tester.view.devicePixelRatio = 2.0;
        // A desktop shell needs a desktop viewport: below `kDesktopBreakpoint`
        // the shell lays out as the phone shell, which is a different screen.
        tester.view.physicalSize = const Size(1440, 900) * 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const DesktopShell(),
        ));

        // `_loadInstances` is async and clears the `_loading` gate; pump past it
        // rather than settling, since the sessions ticker never goes quiet.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/desktop_shell_empty_$density.png');

        // Unmount so `dispose` cancels the sessions ticker.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
