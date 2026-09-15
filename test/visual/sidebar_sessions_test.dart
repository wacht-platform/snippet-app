import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/shell_nav.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

/// The sidebar session list as it actually renders.
///
/// The widget gallery covers primitives in isolation; this covers the COMPOSED
/// screen most people look at all day. Density bugs (a row that out-indents the
/// section header above it, a badge that changes the row height, a selected row
/// that reads the same as an idle one) are only visible once the rows sit
/// together in a list at real width.
void main() {
  testWidgets('sidebar session list', (tester) async {
    // 242px content in a 258px rail, at 2x, tall enough for the whole list.
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(258, 560) * 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: const _SidebarFixture(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/sidebar_sessions.png'));
  });
}

class _SidebarFixture extends StatelessWidget {
  const _SidebarFixture();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const ShellSectionHeader(label: 'Chats'),
        // A pinned Mission Control row, selected.
        ShellNavRow(
          id: 'mission-control',
          label: 'Mission Control',
          icon: 'layers',
          tone: ShellTone.agent,
          selected: true,
          leading: const SessionStateIcon(
              status: 'idle', icon: 'layers', size: kNavIcon),
          onTap: () {},
        ),
        const SizedBox(height: 4),
        // A folder group, expanded, with one agent working inside it.
        ShellGroupHeader(
          label: 'snippet-mobile',
          icon: 'folder',
          tone: ShellTone.chat,
          expanded: true,
          onToggle: () {},
          trailing: const Text('3', style: TextStyle(fontSize: 10.5)),
        ),
        ShellNavRow(
          id: 'a',
          label: 'Slate accent and press feedback',
          icon: 'chat-thread',
          tone: ShellTone.chat,
          indent: kNavRowInset + 21,
          leading: const SessionStateIcon(status: 'running', size: kNavIcon),
          trailing: const _AgentBadgeFixture(agentId: 'snippet', working: true),
          onTap: () {},
        ),
        ShellNavRow(
          id: 'b',
          label: 'TUI gets stuck when listing sessions',
          icon: 'chat-thread',
          tone: ShellTone.chat,
          indent: kNavRowInset + 21,
          leading: const SessionStateIcon(
              status: 'waiting_for_input', size: kNavIcon),
          onTap: () {},
        ),
        ShellNavRow(
          id: 'c',
          label: '(untitled)',
          icon: 'chat-thread',
          tone: ShellTone.chat,
          indent: kNavRowInset + 21,
          leading: const SessionStateIcon(status: 'idle', size: kNavIcon),
          onTap: () {},
        ),
        const SizedBox(height: 8),
        const ShellSectionHeader(label: 'Terminals'),
        ShellNavRow(
          id: 't1',
          label: 'fish — snippet-mobile',
          icon: 'terminal',
          tone: ShellTone.neutral,
          onTap: () {},
        ),
      ],
    );
  }
}

/// Mirrors the shell's private `_AgentBadge` so the golden shows the real
/// trailing treatment. Kept in sync by eye; if it drifts the golden will show it.
class _AgentBadgeFixture extends StatelessWidget {
  const _AgentBadgeFixture({required this.agentId, this.working = false});

  final String agentId;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final fg = working ? AppColors.run : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: working ? AppColors.runBg : AppColors.accentBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon('users', size: 11, color: fg),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            agentId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(10.5, weight: W.label, color: fg),
          ),
        ),
      ]),
    );
  }
}
