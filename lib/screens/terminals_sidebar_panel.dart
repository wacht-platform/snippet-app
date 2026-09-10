import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// Sidebar panel for terminals:
/// - Section header: `⌄ >_ TERMINALS` with a `+` action button.
/// - Cards showing terminal name (e.g. `git terminal`, `dev commands`)
///   and workspace path subtitle.
class TerminalsSidebarPanel extends StatelessWidget {
  const TerminalsSidebarPanel({
    super.key,
    required this.workspacePath,
    required this.onNewTerminal,
    required this.onOpenTerminal,
    this.terminalTitles = const ['git terminal', 'dev commands'],
    this.activeIndex = 0,
  });

  final String workspacePath;
  final VoidCallback onNewTerminal;
  final ValueChanged<int> onOpenTerminal;
  final List<String> terminalTitles;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final displayPath =
        workspacePath.trim().isEmpty ? '~/workspace' : workspacePath;

    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
        children: [
          ShellSectionHeader(
            label: 'Terminals',
            expanded: true,
            onToggle: () {},
            actions: [
              ShellSectionAction(
                icon: 'plus',
                tooltip: 'New terminal',
                onTap: onNewTerminal,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < terminalTitles.length; i++)
            _TerminalCard(
              title: terminalTitles[i],
              path: displayPath,
              selected: i == activeIndex,
              onTap: () => onOpenTerminal(i),
            ),
        ],
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({
    required this.title,
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.surface2 : AppColors.surface1,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                color: selected ? AppColors.border2 : AppColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AppIcon(
                    'terminal',
                    size: 14,
                    color: selected ? AppColors.accent : AppColors.fg3,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(
                          12.5,
                          weight: selected ? W.title : W.label,
                          color: selected ? AppColors.fg1 : AppColors.fg2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(10, color: AppColors.fg4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
