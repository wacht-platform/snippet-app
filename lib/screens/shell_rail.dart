import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Width of the sidebar column. The nested navigation strip and the panel
/// below it both use this, so the strip can never exceed the sidebar.
const double kSidebarWidth = 320;

/// The five sidebar work areas. The strip selects which panel the sidebar
/// shows; it never changes the conversation in the main pane.
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

/// Nested navigation strip pinned above the sidebar and constrained to the
/// sidebar's width. Icons are centered within that full width, and the row
/// keeps a hairline so it reads as its own level of the hierarchy.
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
        // A full-width hairline separates the nested navigation from the panel
        // below it; `border2` keeps it visible against the shared grey chrome.
        border: Border(bottom: BorderSide(color: AppColors.border2, width: 1)),
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
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
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
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              width: 32,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.sm),
                border: selected ? Border.all(color: AppColors.border) : null,
              ),
              child: AppIcon(
                section.icon,
                size: 17,
                visualScale: 1,
                color: selected ? AppColors.fg1 : AppColors.fg4,
              ),
            ),
          ),
        ),
      );
}
