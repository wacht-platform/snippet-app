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

/// A row's box sits at the SAME inset as a section header — measured x8 for
/// both. An earlier version inset rows one step further, which pushed every
/// list 10px right of its own header and off the sidebar's left edge.
/// Deeper nesting still adds `kTreeIndentStep` per level via a row's `indent`.
const double kNavRowInset = kSidebarContentInset;

/// Padding inside a row, between its box edge and its content.
///
/// With the box at 8 this puts the icon at 20 — the same column as the section
/// header's chevron, so header and rows align on one axis.
const double kNavPadH = 12;

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
                      // Measured: 12px/500 in the default body ink (#C1C1C1), not
                      // the faintest tone. At fg4 the header was nearly invisible
                      // and read as disabled chrome rather than a section label.
                      style: sans(12,
                          weight: W.label, color: AppColors.fg2, spacing: 0.4),
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
      // The row box sits at the same inset as the section header, so header and
      // rows share one left edge and one icon column.
      //
      // No vertical padding: measured rows are exactly 26px with zero gap, so
      // any margin here would space the list out at 28 and drift from the
      // reference's rhythm.
      padding: EdgeInsets.only(left: indent, right: kSidebarContentInset),
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

/// Header height for a pane. Measured 36px in the reference.
const double kPaneHeaderHeight = 36;

/// A framed tab sits in the full strip band. Every tab carries the same hairline
/// top seam, so a pane is bounded on top; the active tab additionally overlays a
/// heavier white stroke on its own segment.
const double kPaneTabHeight = kPaneHeaderHeight;
const double kPaneHairline = 0.2;
const double kPaneActiveStroke = 2.0;

/// Hit width of the pane split handle. The visible line is one hairline at the
/// centre; this is only the grab zone around it.
const double kPaneSplitHandleWidth = 6;

/// Passive pane/tab seam. Low-alpha white over the canvas: clearly present as a
/// boundary, but still a step below the chrome's own borders.
const double kPaneSeamAlpha = 0.22;

/// The same seam while the divider is hovered — bright enough to signal that the
/// line is the resize target, without becoming a drawn border.
const double kPaneSeamHoverAlpha = 0.42;

/// The one seam colour both panes share, so their boundary cannot render as two
/// disjoint edges.
Color get kPaneSeamColor => AppColors.fg1.withValues(alpha: kPaneSeamAlpha);
Color get kPaneSeamHoverColor =>
    AppColors.fg1.withValues(alpha: kPaneSeamHoverAlpha);

/// Pane tab widths. Tabs open at [kPaneTabMaxWidth] and shrink together as more
/// are added, down to the fixed [kPaneTabMinWidth] floor — past which the strip
/// scrolls rather than squeezing labels into nothing.
const double kPaneTabMinWidth = 140;
const double kPaneTabMaxWidth = 260;

/// Width one pane tab should take when [count] tabs share [available] width.
///
/// Tabs open wide and shrink together as more are added, stopping at
/// [kPaneTabMinWidth]. Past that floor the strip scrolls instead of squeezing
/// labels into nothing — so the minimum is a fixed number, not a ratio.
double kPaneTabWidth(double available, int count) {
  if (count <= 0) return kPaneTabMaxWidth;
  return (available / count).clamp(kPaneTabMinWidth, kPaneTabMaxWidth);
}

/// Pane tab label size.
const double kPaneTabText = 12;

/// One tab in a pane header. Readout tabs may close themselves; the pane never
/// owns a separate close action.
class PaneTab {
  const PaneTab({required this.label, required this.icon, this.onClose});
  final String label;
  final String icon;
  final VoidCallback? onClose;
}

/// Shared joined tab strip for a pane readout. Tabs meet directly and share one
/// near-background baseline; the active tab carries a solid white top edge.
class PaneTabStrip extends StatelessWidget {
  const PaneTabStrip({
    super.key,
    required this.tabs,
    required this.activeIndex,
    this.onSelect,
  });

  final List<PaneTab> tabs;
  final int activeIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: kPaneHeaderHeight,
      color: AppColors.canvas,
      child: Stack(fit: StackFit.expand, children: [
        LayoutBuilder(builder: (context, c) {
          final w = kPaneTabWidth(c.maxWidth, tabs.length);
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: tabs.length,
            separatorBuilder: (_, __) => const SizedBox.shrink(),
            itemBuilder: (_, i) => _tab(i, w),
          );
        }),
        // Foreground baseline: the ListView paints over the container's own
        // decoration, so the strip rule must be laid on top of the tabs.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(height: kPaneHairline, color: kPaneSeamColor),
          ),
        ),
      ]),
    );
  }

  Widget _tab(int i, double width) {
    final t = tabs[i];
    final active = i == activeIndex;
    return MouseRegion(
      cursor: onSelect == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSelect == null ? null : () => onSelect!(i),
        child: SizedBox(
          width: width,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              border: Border(
                right: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
                // Every tab is bounded on top, so the pane has a real top edge;
                // the active tab simply makes its own segment heavier.
                top: active
                    ? BorderSide(color: AppColors.fg1, width: kPaneActiveStroke)
                    : BorderSide(color: kPaneSeamColor, width: kPaneHairline),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(t.icon,
                  size: 14, color: active ? AppColors.fg2 : AppColors.fg4),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kPaneTabText,
                      weight: active ? W.label : W.body,
                      color: active ? AppColors.fg1 : AppColors.fg3),
                ),
              ),
              if (t.onClose != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: t.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: AppIcon('x', size: 11, color: AppColors.fg4),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Secondary pane width. Width-driven rather than a flex ratio: a fixed flex
/// ratio cannot be dragged, and a terminal needs a column count while a readout
/// should not stretch to 45% of a 4K window.
const double kPaneDefaultWidth = 420;

/// Smallest usable pane width. Below this a terminal loses its columns and a
/// readout starts wrapping every label.
const double kPaneMinWidth = 280;
