import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// The sidebar's five work areas. The rail is deliberately a narrow vertical
/// strip, leaving the panel beside it free for dense, full-width content.
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

/// Vertical rail matching the desktop shell: a slim, centered stack of small
/// glyphs with a quiet active capsule rather than an oversized tab bar.
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
      width: 44,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        for (final item in ShellSection.values) ...[
          _RailButton(
            section: item,
            selected: item == section,
            onTap: () => onSelect(item),
          ),
          const SizedBox(height: 5),
        ],
      ]),
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
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.sm),
                border: selected ? Border.all(color: AppColors.border) : null,
              ),
              child: AppIcon(
                section.icon,
                size: 16,
                color: selected ? AppColors.fg1 : AppColors.fg4,
              ),
            ),
          ),
        ),
      );
}
