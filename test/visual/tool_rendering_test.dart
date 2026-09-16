import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/widgets.dart';
import 'golden.dart';

/// The tool-call rendering as it actually appears in the transcript.
///
/// Rendered collapsed and expanded, with the real tool names and argument shapes
/// the agent produces. `ToolRun` groups consecutive calls; `DenseToolRow` is one
/// call. Between them they are most of what a working session shows, so their
/// density and hierarchy decide whether the transcript reads as a designed feed
/// or as debug output.
void main() {
  testWidgets('tool rendering', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(430, 900) * 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Caption('A RUN, COLLAPSED'),
              ToolRun(_rows(4), running: false, open: false),
              const SizedBox(height: 18),
              const _Caption('THE SAME RUN, EXPANDED'),
              ToolRun(_rows(4), running: false, open: true),
              const SizedBox(height: 18),
              const _Caption('RUNNING (spinner, no result yet)'),
              ToolRun(_pending(2), running: true, open: true),
              const SizedBox(height: 18),
              const _Caption('SINGLE CALLS'),
              const DenseToolRow(
                tool: 'bash',
                args: {'command': 'cargo test --lib --offline'},
                result: {'status': 'ok', 'stdout': 'test result: ok. 193 passed'},
              ),
              const DenseToolRow(
                tool: 'bash',
                args: {'command': 'false'},
                result: {'status': 'error', 'stderr': 'exit status 1'},
              ),
              const DenseToolRow(
                tool: 'read_file',
                args: {'path': 'lib/theme.dart'},
                result: {'status': 'ok', 'content': 'line\nline\nline'},
              ),
              const DenseToolRow(
                tool: 'search_content',
                args: {'query': 'AppColors.accent'},
                result: {
                  'status': 'ok',
                  'matches': [
                    {'path': 'a.dart', 'line': 1}
                  ]
                },
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await expectGolden(tester, find.byType(MaterialApp), 'goldens/tool_rendering.png');
  });
}

/// Consecutive calls, the shape a real turn produces.
List<Widget> _rows(int n) => const [
      DenseToolRow(
        tool: 'search_content',
        args: {'query': 'accentFg|accentBg'},
        result: {
          'status': 'ok',
          'matches': [
            {'path': 'lib/widgets.dart', 'line': 1033}
          ]
        },
      ),
      DenseToolRow(
        tool: 'read_file',
        args: {'path': 'lib/theme.dart'},
        result: {'status': 'ok', 'content': 'x\nx\nx\nx\nx'},
      ),
      DenseToolRow(
        tool: 'edit_file',
        args: {
          'path': 'lib/theme.dart',
          'old_string': 'accentFg: const Color(0xFFFFFFFF),',
          'new_string': 'accentFg: const Color(0xFF0C0C0C),',
        },
        result: {'status': 'ok'},
      ),
      DenseToolRow(
        tool: 'bash',
        args: {'command': 'flutter test'},
        result: {'status': 'ok', 'stdout': 'All tests passed!'},
      ),
    ];

List<Widget> _pending(int n) => const [
      DenseToolRow(
        tool: 'read_file',
        args: {'path': 'lib/transcript.dart'},
      ),
      DenseToolRow(
        tool: 'bash',
        args: {'command': 'flutter analyze lib/'},
      ),
    ];

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SectionLabel(text),
      );
}
