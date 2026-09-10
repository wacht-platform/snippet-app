import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// The five sidebar work areas. This is a compact horizontal strip that owns
/// its own row; the active panel fills the complete sidebar underneath it.
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

/// Narrow horizontal section strip at the top of the sidebar. Glyphs are kept
/// deliberately small so this reads as nested navigation, not a second toolbar.
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
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final item in ShellSection.values) ...[
            _RailButton(
              section: item,
              selected: item == section,
              onTap: () => onSelect(item),
            ),
            if (item != ShellSection.values.last) const SizedBox(width: 8),
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
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(R.xs),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.xs),
            child: Container(
              width: 24,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.xs),
              ),
              child: AppIcon(
                section.icon,
                size: 13,
                color: selected ? AppColors.fg1 : AppColors.fg4,
              ),
            ),
          ),
        ),
      );
}
