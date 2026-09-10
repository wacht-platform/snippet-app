import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Design-language primitives for the shell sidebar.
///
/// Metrics are measured from the reference, not eyeballed:
///   1. SECTION header — 32px tall, 8px/12px padding, uppercase, muted
///   2. GROUP header   — 26px tall, same padding, collapsible
///   3. ROW            — 26px tall, 8px radius, icon + label
///
/// Separation comes from the surface ladder, never from drawn lines: the
/// reference contains no borders at all.
///
/// Kept in one file so the sidebar's look is reviewable in one place rather
/// than scattered through a 4k-line screen.

/// Rows are colour-coded by kind. Colour here is *information* — which list a
/// row belongs to — which is why the reference can afford several hues: they
/// are rationed to iconography, never used as surfaces.
///
/// Chat rows in particular stay neutral: every conversation sharing one
/// saturated accent turned the list into a wall of blue and buried the
/// selection state.
enum ShellTone { chat, ticket, artifact, review, agent, neutral }

Color toneColor(ShellTone tone) => switch (tone) {
      ShellTone.chat => AppColors.fg3,
      ShellTone.ticket => AppColors.run,
      ShellTone.review => AppColors.ok,
      ShellTone.artifact => AppColors.fg3,
      ShellTone.agent => AppColors.fg2,
      ShellTone.neutral => AppColors.fg2,
    };

/// Measured metrics.
const double kNavRowHeight = 26;
const double kNavHeaderHeight = 32;
const double kNavIcon = 16;

/// Outer padding on sidebar sections.
const double kSidebarContentInset = 8;

/// A row's box is inset one step further than a section header. That offset is
/// what gives the list its hierarchy without drawing indentation guides, and it
/// keeps the selected pill from colliding with the sidebar edge. Deeper nesting
/// adds this same step again via a row's `indent`.
///
/// Kept modest: an over-wide gutter pushed row text far from the panel's left
/// edge and wasted the width the sidebar needs for titles.
const double kNavRowInset = kSidebarContentInset + 10;

/// Padding inside a row, between its box edge and its content.
const double kNavPadH = 8;

/// UPPERCASE section header with a leading chevron and a trailing action
/// cluster.
class ShellSectionHeader extends StatelessWidget {
  const ShellSectionHeader({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    this.actions = const [],
  });

  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  /// Rendered right-aligned, smallest-first.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return SizedBox(
      height: kNavHeaderHeight,
      child: Padding(
        // Headers sit at the outer section inset; the rows beneath them are
        // inset one step further, which is what creates the hierarchy.
        padding: const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kNavPadH, vertical: 8),
                  child: Row(children: [
                    AppIcon(expanded ? 'chevron-down' : 'chevron-right',
                        size: 16, color: AppColors.fg4),
                    const SizedBox(width: 8),
                    Text(
                      label.toUpperCase(),
                      style: sans(11,
                          weight: W.label, color: AppColors.fg4, spacing: 0.7),
                    ),
                  ]),
                ),
              ),
            ),
            ...actions,
            const SizedBox(width: kNavPadH),
          ],
        ),
      ),
    );
  }
}

/// Small square icon action used inside a section header's cluster.
class ShellSectionAction extends StatelessWidget {
  const ShellSectionAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Tints the glyph with the accent. Used to show that a toggle in the cluster
  /// is currently on — e.g. a text filter is active — so the state is visible
  /// without opening the control.
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: SizedBox(
            // 24px target around a 16px glyph.
            width: 24,
            height: 24,
            child: Center(
              child: AppIcon(icon,
                  size: 16,
                  color: active
                      ? AppColors.accent
                      : (onTap == null ? AppColors.fg4 : AppColors.fg3)),
            ),
          ),
        ),
      );
}

/// Title-case collapsible group inside a section (e.g. a folder).
class ShellGroupHeader extends StatelessWidget {
  const ShellGroupHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    required this.expanded,
    required this.onToggle,
    this.indent = kNavRowInset,
    this.trailing,
  });

  final String label;
  final String icon;
  final ShellTone tone;
  final bool expanded;
  final VoidCallback onToggle;
  final double indent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: kNavRowHeight,
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: kSidebarContentInset),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
            child: Row(children: [
              AppIcon(expanded ? 'chevron-down' : 'chevron-right',
                  size: 16, color: AppColors.fg4),
              const SizedBox(width: 8),
              AppIcon(icon, size: kNavIcon, color: toneColor(tone)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, weight: W.label, color: AppColors.fg2)),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}

/// The leaf: one nav row.
///
/// Selection is expressed by surface alone — `surface1` (#222222) behind the
/// row with 8px radius and no border — exactly as the reference does it. Text
/// lifts from the default `#C1C1C1` to white only on the active row.
class ShellNavRow extends StatelessWidget {
  const ShellNavRow({
    super.key,
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
    this.selected = false,
    this.indent = kNavRowInset,
    this.onTap,
    this.trailing,
  });

  final String id;
  final String label;
  final String icon;
  final ShellTone tone;
  final bool selected;
  final double indent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      // The row box is inset one step past the section header, so the list
      // reads as nested under it and the selected pill never touches the
      // sidebar edge.
      padding: EdgeInsets.only(
          left: indent, right: kSidebarContentInset, top: 1, bottom: 1),
      child: Material(
        color: selected ? AppColors.surface1 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            height: kNavRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
            child: Row(children: [
              AppIcon(
                icon,
                size: kNavIcon,
                color: selected ? AppColors.fg1 : toneColor(tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(
                    13,
                    weight: selected ? W.label : W.body,
                    color: selected ? AppColors.fg1 : AppColors.fg2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}
