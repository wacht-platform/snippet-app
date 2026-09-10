import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// The five sidebar work areas. This is a compact horizontal strip that owns
/// its own full-width row; the active panel fills the complete sidebar below.
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

/// Full-width nested navigation row. Section icons stay left-aligned while the
/// remaining space is explicitly reserved for future sidebar-level controls.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
    this.trailing,
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      width: double.infinity,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final item in ShellSection.values) ...[
            _RailButton(
              section: item,
              selected: item == section,
              onTap: () => onSelect(item),
            ),
            if (item != ShellSection.values.last) const SizedBox(width: 8),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
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
                visualScale: 1,
                color: selected ? AppColors.fg1 : AppColors.fg4,
              ),
            ),
          ),
        ),
      );
}
