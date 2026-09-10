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
enum ShellTone { chat, ticket, artifact, review, agent, neutral }

Color toneColor(ShellTone tone) => switch (tone) {
      ShellTone.chat => AppColors.accent,
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

/// Left padding inside a row. Top-level rows and section headers share it; a
/// nested row adds [kNavNestStep] so the hierarchy reads without indentation
/// guides.
const double kNavIndent = 12;
const double kNavNestStep = 24;
const double kNavNestedIndent = kNavIndent + kNavNestStep;

/// Outer padding on sidebar sections.
const double kSidebarContentInset = 8;

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
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: kNavIndent, vertical: 8),
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
          const SizedBox(width: kNavIndent),
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
          borderRadius: BorderRadius.circular(R.md),
          child: SizedBox(
            // 24px target around a 16px glyph.
            width: 24,
            height: 24,
            child: Center(
              child: AppIcon(icon,
                  size: 16,
                  color: onTap == null ? AppColors.fg4 : AppColors.fg3),
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
      height: kNavRowHeight,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: kNavIndent),
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
          horizontal: kSidebarContentInset, vertical: 1),
      child: Material(
        color: selected ? AppColors.surface1 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            height: kNavRowHeight,
            padding: EdgeInsets.only(left: indent, right: kNavIndent),
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
