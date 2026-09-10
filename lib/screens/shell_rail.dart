import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// What the shell's contextual sidebar is showing. The icon row picks one; the
/// sidebar renders it. Modelled on the reference app, where the icon row
/// switches the sidebar's *content* rather than the main pane — so the
/// conversation you're reading never gets pushed aside.
enum ShellSection {
  sessions('Chat', 'message-text'),
  terminal('Terminal', 'terminal'),
  git('Git Diff', 'git-branch'),
  files('File Tree', 'file'),
  agents('Agents', 'users');

  const ShellSection(this.label, this.icon);
  final String label;
  final String icon;
}

/// Horizontal icon row pinned to the top of the sidebar column:
/// - Clean icons with spacing
/// - Active icon has a white horizontal underline bar right underneath it
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
    required this.onTerminal,
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;
  final VoidCallback onTerminal;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final s in ShellSection.values)
            _RailButton(
              section: s,
              selected: s == section,
              onTap: () =>
                  s == ShellSection.terminal ? onTerminal() : onSelect(s),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final ShellSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: section.label,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.xs),
          child: SizedBox(
            width: 36,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AppIcon(
                  section.icon,
                  size: 17,
                  color: selected ? AppColors.fg1 : AppColors.fg4,
                ),
                if (selected)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 24,
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
