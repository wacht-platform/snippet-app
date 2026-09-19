import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'mission_control/task_board_screen.dart';
import 'recurring.dart';
import 'session_panels.dart';
import 'shell_models.dart';
import 'shell_nav.dart';
import 'shell_window_bar.dart';

/// The container surface for a desktop split pane with corner rounding and drop highlight.
class PaneSurface extends StatelessWidget {
  final ShellPane pane;
  final Widget child;
  final bool droppable;
  final bool roundRight;

  const PaneSurface({
    super.key,
    required this.pane,
    required this.child,
    this.droppable = false,
    this.roundRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: readingBg,
        borderRadius: BorderRadius.only(
          topLeft: pane == ShellPane.left
              ? const Radius.circular(R.sheetTop)
              : Radius.zero,
          topRight:
              roundRight ? const Radius.circular(R.sheetTop) : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        child,
        if (droppable)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppColors.accent, width: kPaneActiveStroke),
                  borderRadius: BorderRadius.only(
                    topLeft: pane == ShellPane.left
                        ? const Radius.circular(R.sheetTop)
                        : Radius.zero,
                    topRight: roundRight
                        ? const Radius.circular(R.sheetTop)
                        : Radius.zero,
                  ),
                ),
              ),
            ),
          ),
        if (pane == ShellPane.left)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: kPaneHairline,
                color: kPaneSeamColor,
              ),
            ),
          ),
      ]),
    );
  }
}

/// Affordance to re-open a collapsed pane.
class CollapsedPaneStub extends StatelessWidget {
  final ShellPane pane;
  final VoidCallback onExpand;

  const CollapsedPaneStub({
    super.key,
    required this.pane,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconBtn(
        'chevron-right',
        size: 28,
        iconSize: 14,
        tooltip: 'Show pane',
        onTap: onExpand,
      ),
    );
  }
}

/// Placeholder displayed when a pane has no active tabs.
class EmptyPaneHint extends StatelessWidget {
  final String message;

  const EmptyPaneHint({
    super.key,
    this.message = 'Drag a tab here, or open a terminal from the sidebar.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: sans(12, color: AppColors.fg3),
        ),
      ),
    );
  }
}

/// The single shared draggable divider between the two panes.
class PaneResizeHandle extends StatefulWidget {
  final bool joinBaseline;
  final void Function(double deltaDx) onResize;

  const PaneResizeHandle({
    super.key,
    this.joinBaseline = false,
    required this.onResize,
  });

  @override
  State<PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onResize(d.delta.dx),
        child: SizedBox(
          width: kPaneSplitHandleWidth,
          child: Stack(children: [
            Center(
              child: SizedBox(
                width: kPaneHairline,
                height: double.infinity,
                child: ColoredBox(
                  color: _hover ? kPaneSeamHoverColor : kPaneSeamColor,
                ),
              ),
            ),
            if (widget.joinBaseline)
              Positioned(
                left: 0,
                right: 0,
                top: kPaneHeaderHeight - kPaneHairline,
                child: IgnorePointer(
                  child: Container(
                    height: kPaneHairline,
                    color: kPaneSeamColor,
                  ),
                ),
              ),
            if (widget.joinBaseline)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    height: kPaneHairline,
                    color: kPaneSeamColor,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Drag feedback ghost for a session readout chip.
class ReadoutDragFeedback extends StatelessWidget {
  final RightTab tab;

  const ReadoutDragFeedback({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(tab.icon, size: 13, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(tab.label, style: sans(12, color: AppColors.fg1)),
        ]),
      ),
    );
  }
}

/// One readout tab (Lanes / Checkpoints / Usage / an agent) in a pane strip.
class ReadoutChip extends StatelessWidget {
  final ShellPane pane;
  final RightTab tab;
  final bool active;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  const ReadoutChip({
    super.key,
    required this.pane,
    required this.tab,
    required this.active,
    required this.width,
    required this.onTap,
    required this.onClose,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Container(
          height: kPaneTabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: readingBg,
            border: Border(
              right: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
              top: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
            ),
          ),
          foregroundDecoration: !active
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppColors.fg1, width: kPaneActiveStroke),
                  ),
                ),
          child: Row(children: [
            AppIcon(tab.icon,
                size: 14, color: active ? AppColors.fg1 : AppColors.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kPaneTabText,
                    weight: active ? W.label : W.body,
                    color: active ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AppIcon('x', size: 11, color: AppColors.fg4),
              ),
            ),
          ]),
        ),
      ),
    );

    if (kMobile) {
      return LongPressDraggable<RightTab>(
        data: tab,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ReadoutDragFeedback(tab: tab),
        childWhenDragging: Opacity(opacity: 0.4, child: chip),
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        child: chip,
      );
    }
    return Draggable<RightTab>(
      data: tab,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: ReadoutDragFeedback(tab: tab),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: chip,
    );
  }
}

/// One docked shell tab chip in a pane strip.
class PaneTabChip extends StatelessWidget {
  final ShellPane pane;
  final ShellTab tab;
  final bool active;
  final double width;
  final String? status;
  final bool canDismiss;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  const PaneTabChip({
    super.key,
    required this.pane,
    required this.tab,
    required this.active,
    required this.width,
    required this.status,
    required this.canDismiss,
    required this.onTap,
    required this.onDismiss,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Container(
          height: kPaneTabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: readingBg,
            border: Border(
              right: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
              top: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
            ),
          ),
          foregroundDecoration: !active
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppColors.fg1, width: kPaneActiveStroke),
                  ),
                ),
          child: Row(children: [
            SessionStateIcon(
              status: status,
              icon: tabIconKind(tab),
              size: 14,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tab.title.isEmpty ? '(untitled)' : tab.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kPaneTabText,
                    weight: active ? W.label : W.body,
                    color: active ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (canDismiss) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDismiss,
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
    );

    if (kMobile) {
      return LongPressDraggable<ShellTab>(
        data: tab,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: TabDragFeedback(tab: tab),
        childWhenDragging: Opacity(opacity: 0.4, child: chip),
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        child: chip,
      );
    }
    return Draggable<ShellTab>(
      data: tab,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: TabDragFeedback(tab: tab),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: chip,
    );
  }
}

/// The tab strip for a pane, containing both docked ShellTabs and RightTabs.
class PaneStrip extends StatelessWidget {
  final ShellPane pane;
  final List<ShellTab> tabs;
  final List<RightTab> readouts;
  final String? activeKey;
  final String? Function(ShellTab) statusForTab;
  final bool Function(ShellTab) canDismissTab;
  final void Function(ShellTab) onActivateTab;
  final void Function(ShellTab) onDismissTab;
  final void Function(RightTab) onActivateReadout;
  final void Function(RightTab) onCloseReadout;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  const PaneStrip({
    super.key,
    required this.pane,
    required this.tabs,
    required this.readouts,
    required this.activeKey,
    required this.statusForTab,
    required this.canDismissTab,
    required this.onActivateTab,
    required this.onDismissTab,
    required this.onActivateReadout,
    required this.onCloseReadout,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final count = tabs.length + readouts.length;
    return Container(
      height: kPaneHeaderHeight,
      color: readingBg,
      child: Stack(fit: StackFit.expand, children: [
        LayoutBuilder(builder: (context, c) {
          final w = kPaneTabWidth(c.maxWidth, count);
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox.shrink(),
            itemBuilder: (_, i) {
              if (i < tabs.length) {
                final t = tabs[i];
                return PaneTabChip(
                  pane: pane,
                  tab: t,
                  active: t.key == activeKey,
                  width: w,
                  status: statusForTab(t),
                  canDismiss: canDismissTab(t),
                  onTap: () => onActivateTab(t),
                  onDismiss: () => onDismissTab(t),
                  onDragStarted: onDragStarted,
                  onDragEnd: onDragEnd,
                );
              }
              final r = readouts[i - tabs.length];
              return ReadoutChip(
                pane: pane,
                tab: r,
                active: r.key == activeKey,
                width: w,
                onTap: () => onActivateReadout(r),
                onClose: () => onCloseReadout(r),
                onDragStarted: onDragStarted,
                onDragEnd: onDragEnd,
              );
            },
          );
        }),
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
}

/// Renders the body content of a RightTab (Lanes, Tasks, Checkpoints, Recurring, or Agent detail).
class RightTabBody extends StatelessWidget {
  final RightTab tab;
  final HarnessState? state;
  final MacSessionControls? controls;
  final DaemonClient? client;
  final String? activeSessionId;

  const RightTabBody({
    super.key,
    required this.tab,
    required this.state,
    required this.controls,
    required this.client,
    required this.activeSessionId,
  });

  @override
  Widget build(BuildContext context) {
    final agent = tab.agent;
    if (agent != null) {
      return CoordinationAgentDetail(
        agent: agent,
        client: client,
        embedded: true,
      );
    }
    return switch (tab.panel) {
      RightPanel.lanes => SessionLanesPanel(lanes: state?.lanes ?? const []),
      RightPanel.tasks => client == null
          ? const EmptyPaneHint()
          : TaskBoardScreen(client: client!, embedded: true),
      RightPanel.recurring => client == null
          ? const EmptyPaneHint()
          : RecurringScreen(
              client: client!,
              embedded: true,
              sessionId: activeSessionId,
              workspace: state?.workspace,
            ),
      RightPanel.checkpoints => SessionCheckpointsPanel(
          checkpoints: state?.checkpoints.reversed.toList() ?? const [],
          onRewind: (c) => controls?.performAction('rewind', c.id),
          onFork: (c) => controls?.performAction('fork', c.id),
        ),
      RightPanel.none => const SizedBox.shrink(),
    };
  }
}
