import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Width of the sidebar column. The nested navigation strip centres its icons
/// over this column, and the panel below uses it exactly.
const double kSidebarWidth = 300;

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

/// Shell-level navigation band.
///
/// Spans the full window width and sits between the top bar and the body, so
/// it belongs to the shell rather than to the sidebar. Separation from the
/// chrome below comes from the surface step, not a drawn line.
class ShellRail extends StatelessWidget {
  const ShellRail({
    super.key,
    required this.section,
    required this.onSelect,
    this.tools = const [],
  });

  final ShellSection section;
  final ValueChanged<ShellSection> onSelect;

  /// Tool buttons pinned to the extreme right of the band.
  ///
  /// These are the session-scoped tools that used to live as a row of buttons
  /// in the removed bottom status strip. The band was the only full-width
  /// chrome row left, so they live here rather than being dropped.
  final List<Widget> tools;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      width: double.infinity,
      height: 40,
      color: AppColors.bg,
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          // Icons are centred over the sidebar column, exactly as the reference
          // does, so the strip and the panel below share one axis.
          SizedBox(
            width: kSidebarWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final item in ShellSection.values) ...[
                  _RailButton(
                    section: item,
                    selected: item == section,
                    onTap: () => onSelect(item),
                  ),
                  if (item != ShellSection.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const Spacer(),
          // Tools sit at the far right, against the band's edge.
          for (final tool in tools) ...[
            tool,
            const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

/// The canonical 24px rail glyph: 24px target around a 16px icon, weight and
/// colour marking selection.
///
/// ONE widget for BOTH clusters — the strip above the sidebar and the tool
/// buttons at the right of the band. They were two separate implementations at
/// 16px and 15px with different padding, which is exactly why they read as two
/// different design languages on the same row.
class RailIcon extends StatelessWidget {
  const RailIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.badge,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  /// Small count pill on the top-right of the glyph (e.g. running lanes).
  final String? badge;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final enabled = onTap != null;
    final button = Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: AppIcon(
                icon,
                size: 16,
                color: !enabled
                    ? AppColors.fg4
                    : (active ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
          ),
        ),
      ),
    );
    if (badge == null) return button;
    return Stack(clipBehavior: Clip.none, children: [
      button,
      Positioned(
        right: 0,
        top: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(badge!, style: mono(9, color: AppColors.fg2)),
        ),
      ),
    ]);
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
  Widget build(BuildContext context) => RailIcon(
        icon: section.icon,
        tooltip: section.label,
        active: selected,
        onTap: onTap,
      );
}
