import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';
import 'session.dart' show TerminalInfo;

/// Sidebar panel for a session's terminals.
///
/// Rows mirror the file tree and chat list: flat 26px rows at the sidebar's
/// content inset, selection as a surface step, no card fill or border. The
/// previous version drew bordered cards with a two-line body and a hard-coded
/// title list, which is why it read as both broken and fake.
class TerminalsSidebarPanel extends StatelessWidget {
  const TerminalsSidebarPanel({
    super.key,
    required this.workspacePath,
    required this.terminals,
    required this.focus,
    required this.onNewTerminal,
    required this.onOpenTerminal,
    required this.onCloseTerminal,
  });

  final String workspacePath;

  /// Live terminals for the active session, published by `SessionScreen`.
  /// Empty when the session has not opened one yet.
  final List<TerminalInfo> terminals;

  /// Index of the focused terminal, or -1 when the drawer is closed.
  final int focus;

  final VoidCallback onNewTerminal;
  final ValueChanged<int> onOpenTerminal;

  /// Destroy a terminal. This — or the + above — is the ONLY way a shell is
  /// created or destroyed; the pane can only minimize it.
  final ValueChanged<String> onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final displayPath =
        workspacePath.trim().isEmpty ? '~/workspace' : workspacePath;

    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          ShellSectionHeader(
            label: 'Terminals',
            actions: [
              ShellSectionAction(
                icon: 'plus',
                tooltip: 'New terminal',
                onTap: onNewTerminal,
              ),
            ],
          ),
          // The session's working directory, same flat 32px row the file tree
          // and git panels use for their context line.
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
              child: Row(children: [
                AppIcon('folder-open', size: 14, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11.5, color: AppColors.fg3)),
                ),
              ]),
            ),
          ),
          if (terminals.isEmpty)
            const _SidebarEmpty('No terminals yet. Open one with the + button.')
          else ...[
            const SizedBox(height: 6),
            for (var i = 0; i < terminals.length; i++) _row(i),
          ],
        ],
      ),
    );
  }

  Widget _row(int i) {
    final t = terminals[i];
    final selected = i == focus;
    return ShellNavRow(
      id: t.id,
      label: t.title,
      icon: 'terminal',
      tone: ShellTone.neutral,
      selected: selected,
      onTap: () => onOpenTerminal(i),
      // Alive dot on the left of the close affordance, so a running pty reads
      // at a glance while the row stays a single 26px line.
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (t.alive) ...[
          const StatusDot(status: 'online', size: 7),
          const SizedBox(width: 6),
        ],
        // Destroying lives here, not in the pane: the pane can only minimize.
        GestureDetector(
          onTap: () => onCloseTerminal(t.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AppIcon('x', size: 12, color: AppColors.fg4),
          ),
        ),
      ]),
    );
  }
}

/// Quiet empty state, matching the chat and file-tree panels.
class _SidebarEmpty extends StatelessWidget {
  const _SidebarEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Text(message,
            textAlign: TextAlign.center,
            style: sans(12.5, color: AppColors.fg4, height: 1.45)),
      );
}
