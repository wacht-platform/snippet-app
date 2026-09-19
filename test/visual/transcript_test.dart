import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/widgets.dart';
import 'golden.dart';

/// The chat transcript as it composes on screen.
///
/// This MIRRORS `SessionScreen._transcript()` rather than driving it: the real
/// screen needs a live daemon and websocket. Every element, order and gap below
/// is copied from that builder, so the density and hierarchy are the real ones —
/// but the fixture is a copy, and a change to `_transcript` will not fail here.
/// Treat it as a review surface, not a regression guard.
///
/// Gaps (from `_transcript`):
///   user turn      -> Padding(top: 4, bottom: 20)
///   assistant turn -> Padding(top: 4, bottom: 4)
///   tool run       -> Padding(vertical: 8) inside ToolRun
///   list           -> fromLTRB(kMobile ? 16 : 20, 16, ..., 24)
///   embedded width -> centred, maxWidth 820
void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    testWidgets('chat transcript ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final wide = density == 'desktop';
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize =
            (wide ? const Size(1140, 900) : const Size(430, 860)) * 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: readingBg,
            body: SafeArea(
              bottom: false,
              child: Padding(
                // The real list padding, per density.
                padding: EdgeInsets.fromLTRB(
                    wide ? 20 : M.gutter, 16, wide ? 20 : M.gutter, 24),
                child: _centerWide(
                  wide,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _userTurn('the tui gets stuck when i open it'),
                      ToolRun(
                        const [
                          DenseToolRow(
                            tool: 'bash',
                            args: {'command': 'cargo test --lib --offline'},
                            result: {
                              'status': 'ok',
                              'stdout': 'test result: ok. 193 passed'
                            },
                          ),
                          DenseToolRow(
                            tool: 'search_content',
                            args: {'query': 'store_for_sessions'},
                            result: {
                              'status': 'ok',
                              'matches': [
                                {'path': 'src/session.rs', 'line': 1284}
                              ]
                            },
                          ),
                        ],
                        running: false,
                        open: false,
                      ),
                      _agentTurn(
                          'Found it: the session catalogue calls `Store::open` '
                          'once per directory, and each call re-runs the schema '
                          'migration. Thirty sessions took 2.05s to list.'),
                      ToolRun(
                        const [
                          DenseToolRow(
                            tool: 'edit_file',
                            args: {
                              'path': 'lib/transcript.dart',
                              'old_string': "tool == 'bash'",
                              'new_string': "s('command')",
                            },
                            result: {'status': 'ok'},
                          ),
                          DenseToolRow(
                            tool: 'bash',
                            args: {'command': 'flutter analyze lib/'},
                            result: {'status': 'error', 'stderr': 'exit status 1'},
                          ),
                        ],
                        running: false,
                        open: true,
                      ),
                      const NoteLine('A note the agent left behind.'),
                      const NoteLine('A tool call that failed.', error: true),
                      _userTurn('ok fix it'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
        // Fixed pump: the fixture has a spinner-free tree, but keep the habit.
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/transcript_$density.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Widget _centerWide(bool wide, Widget child) => wide
    ? Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820), child: child))
    : child;

Widget _userTurn(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Bubble(mine: true, text: text),
    );

Widget _agentTurn(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Bubble(mine: false, text: text),
    );
