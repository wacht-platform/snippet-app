import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// What the shell's contextual sidebar is showing. The icon row picks one; the
/// sidebar renders it. Modelled on the reference app, where the icon row
/// switches the sidebar's *content* rather than the main pane — so the
/// conversation you're reading never gets pushed aside.
enum ShellSection {
  sessions('Chat', 'message-text'),
  terminal('Shell', 'terminal'),
  files('Files', 'folder'),
  activity('Activity', 'activity'),
  agents('Agents', 'users');

  const ShellSection(this.label, this.icon);
  final String label;
  final String icon;
}

/// Horizontal icon row pinned to the top of the sidebar column.
///
/// Sits *above* the sidebar rather than beside it, so the sidebar — not the rail
/// — owns the left edge and the working area keeps its width. Wide layouts only;
/// on a phone these destinations are reached from the session menu instead.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
    required this.onTerminal,
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;

  /// The shell opens a real terminal, which is not a sidebar panel — the host
  /// handles it rather than the rail switching a section.
  final VoidCallback onTerminal;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 8),
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.md),
            child: Container(
              width: 34,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Selection is a surface lift, not a filled block — the row
                // should stay quiet at rest.
                color: selected ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.md),
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
