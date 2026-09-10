import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// What the shell's contextual sidebar is showing. The rail picks one; the
/// sidebar renders it. Modelled on the reference app, where the leftmost icon
/// column switches the sidebar's *content* rather than the main pane — so the
/// conversation you're reading never gets pushed aside.
enum ShellSection {
  sessions('Chat', 'message-text'),
  agents('Agents', 'users'),
  activity('Activity', 'activity');

  const ShellSection(this.label, this.icon);
  final String label;
  final String icon;
}

/// Narrow vertical icon rail. Wide layouts only: on a phone the same choices are
/// reached from the session menu, and a 48px strip would cost real estate a
/// small screen cannot spare.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
    this.topInset = 0,
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;

  /// Pushes the icons below the native title bar on macOS.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Container(
      width: 52,
      color: AppColors.bg,
      child: Column(
        children: [
          SizedBox(height: topInset),
          const SizedBox(height: 10),
          for (final s in ShellSection.values)
            _RailButton(
              section: s,
              selected: s == section,
              onTap: () => onSelect(s),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Tooltip(
          message: section.label,
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(R.md),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Selection is a surface lift plus the accent, not a filled
                  // block — the rail should stay quiet at rest.
                  color: selected ? AppColors.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: AppIcon(
                  section.icon,
                  size: 18,
                  color: selected ? AppColors.fg1 : AppColors.fg3,
                ),
              ),
            ),
          ),
        ),
      );
}
