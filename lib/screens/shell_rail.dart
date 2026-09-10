import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// What the shell's contextual sidebar is showing. The compact icon rail picks
/// one panel without taking focus away from the tab already open in the pane.
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

/// Compact, centered section picker pinned above the sidebar panel.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in ShellSection.values) ...[
            _RailButton(
              section: s,
              selected: s == section,
              onTap: () => onSelect(s),
            ),
            if (s != ShellSection.values.last) const SizedBox(width: 6),
          ],
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
            width: 34,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AppIcon(
                  section.icon,
                  size: 16,
                  color: selected ? AppColors.fg1 : AppColors.fg4,
                ),
                if (selected)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 22,
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.fg1,
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
