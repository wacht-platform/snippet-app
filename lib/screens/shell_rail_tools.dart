import 'package:flutter/material.dart';

import '../platform.dart';
import '../menu_widgets.dart';
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
          color: AppColors.overlay,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.lg),
              side: BorderSide(color: AppColors.line)),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.4),
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
        'activity',
        tooltip: 'Automated wakes',
        onTap: enabled ? () => onSessionAction('autonomy') : null,
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

  final win = s?.contextWindow ?? 0;
  final used = s?.lastPromptTokens ?? 0;
  final frac = win > 0 ? (used / win).clamp(0.0, 1.0) : 0.0;
  String k(int v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';
  Widget dots(int n, double size, double gap) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++)
            Container(
              width: size,
              height: size,
              margin: EdgeInsets.only(right: gap),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < (frac * n).round()
                    ? (frac > 0.8 ? AppColors.danger : AppColors.fg3)
                    : AppColors.line,
              ),
            ),
        ],
      );

  Future<void> openMenu(BuildContext ctx) async {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final o = box.localToGlobal(Offset(0, box.size.height + 6));
    final screen = MediaQuery.sizeOf(ctx);
    PopupMenuItem<VoidCallback> item(String icon, String label, VoidCallback fn,
            {String? detail}) =>
        appMenuItem(value: fn, icon: icon, label: label, detail: detail);
    final fn = await showMenu<VoidCallback>(
      context: ctx,
      color: AppColors.surface1,
      elevation: 0,
      shape: appMenuShape,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 280),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      position: RelativeRect.fromLTRB(
          o.dx + box.size.width - 280, o.dy, screen.width - o.dx - box.size.width, 0),
      items: [
        if (win > 0 && used > 0) ...[
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Context',
                              style: sans(12.5, color: AppColors.fg2))),
                      Text('${k(used)} / ${k(win)}',
                          style: mono(11, color: AppColors.fg4)),
                    ]),
                    const SizedBox(height: 8),
                    dots(24, 6, 3),
                  ]),
            ),
          ),
          item('wrap', 'Compact now', () => onSessionAction('compact')),
          const PopupMenuDivider(),
        ],
        goalRunning
            ? item('goal', 'Cancel goal', () => onSessionAction('goal'))
            : item('goal', 'Set goal', () => onOpenGoalPopover(ctx)),
        item('layers', 'Lanes', () => onToggleRightPanel(RightPanel.lanes),
            detail: lanes > 0 ? '$lanes running' : null),
        item('clipboard', 'Artifacts & files',
            () => onSessionAction('artifacts')),
        item('history', 'Checkpoints',
            () => onToggleRightPanel(RightPanel.checkpoints)),
        item('scheduled', 'Scheduled',
            () => onToggleRightPanel(RightPanel.recurring)),
        if (win <= 0 || used <= 0)
          item('wrap', 'Compact history', () => onSessionAction('compact')),
      ],
    );
    fn?.call();
  }

  return [
    if (tab != null && win > 0 && used > 0)
      Tooltip(
        message: 'Context ${k(used)} of ${k(win)}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            dots(8, 4, 2),
            const SizedBox(width: 4),
            Text(k(used), style: sans(12, color: AppColors.fg4)),
          ]),
        ),
      ),
    Builder(
      builder: (ctx) => railTool(
        'more-horizontal',
        tooltip: 'Session actions',
        badge: lanes > 0 ? '$lanes' : null,
        active: goalRunning ||
            isRightPanelActive(RightPanel.lanes) ||
            isRightPanelActive(RightPanel.checkpoints) ||
            isRightPanelActive(RightPanel.recurring),
        onTap: tab == null ? null : () => openMenu(ctx),
      ),
    ),
  ];
}
