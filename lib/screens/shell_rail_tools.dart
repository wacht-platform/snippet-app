import 'package:flutter/material.dart';

import '../theme.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_rail.dart' show RailIcon;

/// Shows an anchored goal popup beneath [anchorContext].
Future<void> showGoalPopover({
  required BuildContext context,
  required BuildContext anchorContext,
  required ValueChanged<String> onSetGoal,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null) return;
  final origin = box.localToGlobal(Offset.zero);
  const width = 320.0;
  final screen = MediaQuery.sizeOf(context).width;
  final left =
      (origin.dx + box.size.width - width).clamp(8.0, screen - width - 8);
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'goal',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.press,
    pageBuilder: (_, __, ___) => Stack(children: [
      Positioned(
        left: left,
        top: origin.dy + box.size.height + 6,
        width: width,
        child: Material(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.md),
          elevation: 12,
          shadowColor: Colors.black87,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GoalPopover(
              onSet: (text) {
                Navigator.pop(context);
                onSetGoal(text);
              },
            ),
          ),
        ),
      ),
    ]),
  );
}

/// Builds the activity rail action tools for the active tab.
List<Widget> buildShellRailTools({
  required ShellTab? activeTab,
  required MacSessionStatus? macSessionStatus,
  required bool Function(RightPanel panel) isRightPanelActive,
  required void Function(RightPanel panel) onToggleRightPanel,
  required void Function(String action, [String? extra]) onSessionAction,
  required void Function(BuildContext ctx) onOpenGoalPopover,
}) {
  final tab = activeTab;
  final mc = tab?.isMissionControl ?? false;
  final s = macSessionStatus?.state;
  final goalRunning = s?.goal?.ongoing ?? false;
  final lanes = s?.lanes.where((l) => l.running).length ?? 0;

  Widget railTool(
    String icon, {
    required String tooltip,
    required VoidCallback? onTap,
    bool active = false,
    String? badge,
  }) =>
      RailIcon(
        icon: icon,
        tooltip: tooltip,
        active: active,
        badge: badge,
        onTap: onTap,
      );

  if (mc) {
    final enabled = tab != null;
    return [
      railTool(
        'layers',
        tooltip: 'Tasks',
        active: isRightPanelActive(RightPanel.tasks),
        onTap: enabled ? () => onToggleRightPanel(RightPanel.tasks) : null,
      ),
      railTool(
        'minimize',
        tooltip: 'Compact history',
        onTap: enabled ? () => onSessionAction('compact') : null,
      ),
      railTool(
        'scheduled',
        tooltip: 'Scheduled',
        active: isRightPanelActive(RightPanel.recurring),
        onTap: enabled ? () => onToggleRightPanel(RightPanel.recurring) : null,
      ),
    ];
  }

  return [
    Builder(
      builder: (ctx) => railTool(
        'goal',
        tooltip: goalRunning ? 'Cancel goal' : 'Set goal',
        active: goalRunning,
        onTap: tab == null
            ? null
            : (goalRunning
                ? () => onSessionAction('goal')
                : () => onOpenGoalPopover(ctx)),
      ),
    ),
    railTool(
      'layers',
      tooltip: 'Lanes',
      active: isRightPanelActive(RightPanel.lanes),
      badge: lanes > 0 ? '$lanes' : null,
      onTap: tab == null ? null : () => onToggleRightPanel(RightPanel.lanes),
    ),
    railTool(
      'history',
      tooltip: 'Checkpoints',
      active: isRightPanelActive(RightPanel.checkpoints),
      onTap: tab == null
          ? null
          : () => onToggleRightPanel(RightPanel.checkpoints),
    ),
    railTool(
      'scheduled',
      tooltip: 'Scheduled',
      active: isRightPanelActive(RightPanel.recurring),
      onTap: tab == null
          ? null
          : () => onToggleRightPanel(RightPanel.recurring),
    ),
  ];
}
