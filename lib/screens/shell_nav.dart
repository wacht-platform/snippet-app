import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Design-language primitives for the shell sidebar.
///
/// Three levels, exactly as the reference does it:
///   1. SECTION header — UPPERCASE, muted, with an action cluster on the right
///   2. GROUP header   — title case, chevron, collapsible, indented one step
///   3. ROW            — compact, icon + label, indented under its group
///
/// Kept in one file so the sidebar's look is reviewable in one place rather
/// than scattered through a 4k-line screen.

/// Rows are colour-coded by kind. Colour here is *information* — which list a
/// row belongs to — which is why the reference can afford several hues: they
/// are rationed to iconography, never used as surfaces.
enum ShellTone { chat, ticket, artifact, review, agent, neutral }

Color toneColor(ShellTone tone) => switch (tone) {
      ShellTone.chat => AppColors.accent,
      ShellTone.ticket => AppColors.run,
      ShellTone.review => AppColors.ok,
      ShellTone.artifact => AppColors.fg3,
      ShellTone.agent => AppColors.fg2,
      ShellTone.neutral => AppColors.fg3,
    };

/// Compact metrics. The reference packs ~34px rows so a long list stays
/// scannable — that density is the point, not an accident.
const double kNavRowHeight = 34;
const double kNavHeaderHeight = 32;
const double kNavIcon = 14;
const double kNavIndent = 18;
const double kSidebarContentInset = 14;

/// UPPERCASE section header with a leading chevron and a trailing action
/// cluster (filter · sort · view · add).
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

  /// Rendered right-aligned, smallest-first, matching the reference cluster.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return SizedBox(
      height: kNavHeaderHeight,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(left: kSidebarContentInset),
                child: Row(children: [
                  AppIcon(expanded ? 'chevron-down' : 'chevron-right',
                      size: 13, color: AppColors.fg4),
                  const SizedBox(width: 7),
                  Text(
                    label.toUpperCase(),
                    style: sans(10.5,
                        weight: W.title, color: AppColors.fg4, spacing: 0.7),
                  ),
                ]),
              ),
            ),
          ),
          ...actions,
          const SizedBox(width: 6),
        ],
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
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: AppIcon(icon,
                  size: 13,
                  color: onTap == null ? AppColors.fg4 : AppColors.fg3),
            ),
          ),
        ),
      );
}

/// Title-case collapsible group inside a section (e.g. "Tickets", a folder).
class ShellGroupHeader extends StatelessWidget {
  const ShellGroupHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    required this.expanded,
    required this.onToggle,
    this.indent = kNavIndent,
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
      height: kNavHeaderHeight,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(children: [
            AppIcon(expanded ? 'chevron-down' : 'chevron-right',
                size: 12, color: AppColors.fg4),
            const SizedBox(width: 6),
            AppIcon(icon, size: 14, color: toneColor(tone)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, weight: W.label, color: AppColors.fg2)),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 8),
          ]),
        ),
      ),
    );
  }
}

/// The leaf: one nav row. Selection is an active card:
/// - Background `AppColors.surface2` (#1B1B22)
/// - Subtle hairline border `AppColors.border2` (#2E2E38)
/// - Radius 6px
/// - Crisp white text with `W.label`
class ShellNavRow extends StatelessWidget {
  const ShellNavRow({
    super.key,
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
    this.selected = false,
    this.indent = kNavIndent,
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
      padding: const EdgeInsets.symmetric(
          horizontal: kSidebarContentInset, vertical: 2),
      child: Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: Container(
            height: kNavRowHeight,
            padding: EdgeInsets.only(left: indent, right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                color: selected ? AppColors.border2 : Colors.transparent,
              ),
            ),
            child: Row(children: [
              AppIcon(
                icon,
                size: kNavIcon,
                color: selected ? AppColors.accent : toneColor(tone),
              ),
              const SizedBox(width: 9),
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
