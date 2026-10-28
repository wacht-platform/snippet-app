import 'package:flutter/material.dart';

import '../mochi.dart';

import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_models.dart';
import 'shell_nav.dart';

/// Top-level workspace tab chip that appears when dragging a tab.
class TabDragFeedback extends StatelessWidget {
  final ShellTab tab;

  const TabDragFeedback({super.key, required this.tab});

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
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(tabIconKind(tab), size: 13, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(
            tab.title.isEmpty ? '(untitled)' : tab.title,
            style: sans(13, color: AppColors.fg1),
          ),
        ]),
      ),
    );
  }
}

/// A top-level workspace tab chip in the desktop window bar.
class TopWorkspaceTabChip extends StatelessWidget {
  final ShellTab tab;
  final bool isActive;
  final String? status;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final GlobalKey? chipKey;
  final String? provider;

  const TopWorkspaceTabChip({
    super.key,
    required this.tab,
    required this.isActive,
    required this.status,
    required this.canClose,
    required this.onTap,
    this.onClose,
    this.chipKey,
    this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final title = tab.title.isEmpty ? '(untitled)' : tab.title;
    final working = status == 'running' || status == 'waiting_for_input';
    final showClose = canClose && onClose != null && isActive;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        key: chipKey,
        height: 30,
        padding: EdgeInsets.fromLTRB(11, 0, showClose ? 5 : 11, 0),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: isActive ? AppColors.line : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isMissionControl)
              WorkingMochi(color: AppColors.accent, size: 14)
            else if (tab.isPrs)
              AppIcon('pull-request', size: 13, color: AppColors.ok)
            else if (provider != null)
              ProviderLogo(provider, size: 12)
            else
              SessionStateIcon(
                status: working ? null : status,
                icon: tabIconKind(tab),
                size: 13,
              ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 14 : 13,
                    color: isActive ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (working) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == 'running'
                      ? AppColors.accent
                      : Colors.transparent,
                  border: status == 'running'
                      ? null
                      : Border.all(color: AppColors.accent, width: 1.5),
                ),
              ),
            ],
            if (showClose) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: AppIcon('x', size: 11, color: AppColors.fg4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The machine avatar and health indicator in the desktop window bar.
class TopMachineSwitcher extends StatelessWidget {
  final Instance? active;
  final bool? isHealthy;
  final bool hasInstances;
  final VoidCallback onAdd;
  final VoidCallback onOpenList;
  final GlobalKey anchorKey;

  const TopMachineSwitcher({
    super.key,
    required this.active,
    required this.isHealthy,
    required this.hasInstances,
    required this.onAdd,
    required this.onOpenList,
    required this.anchorKey,
  });

  @override
  Widget build(BuildContext context) {
    final a = active;
    final initial = a == null || a.label.trim().isEmpty
        ? '+'
        : a.label.trim().characters.first.toUpperCase();

    if (a != null) {
      return Tooltip(
        message: 'Switch machine',
        child: Material(
          key: anchorKey,
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: hasInstances ? onOpenList : onAdd,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(5, 0, 12, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Text(initial, style: sans(11, color: AppColors.fg1)),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg2)),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isHealthy == true ? AppColors.ok : AppColors.fg4,
                    shape: BoxShape.circle,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: a == null ? 'Add machine' : 'Switch machine',
      child: Material(
        key: anchorKey,
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: hasInstances ? onOpenList : onAdd,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initial,
                      style: sans(11, weight: W.title, color: AppColors.fg1),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isHealthy == true ? AppColors.ok : AppColors.fg4,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Strip of top-level workspace tabs plus new session button.
class MainTabsStrip extends StatelessWidget {
  final ScrollController controller;
  final List<ShellTab> tabs;
  final ShellTab? activeTab;
  final String? Function(ShellTab) statusForTab;
  final bool Function(ShellTab) canCloseTab;
  final void Function(ShellTab) onActivateTab;
  final void Function(ShellTab) onCloseTab;
  final VoidCallback onNewSession;
  final GlobalKey Function(String key) chipKeyFor;
  final String? Function(ShellTab)? providerFor;

  const MainTabsStrip({
    super.key,
    required this.controller,
    required this.tabs,
    required this.activeTab,
    required this.statusForTab,
    required this.canCloseTab,
    required this.onActivateTab,
    required this.onCloseTab,
    required this.onNewSession,
    required this.chipKeyFor,
    this.providerFor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 4),
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0 && tabs[i] != activeTab && tabs[i - 1] != activeTab)
            Center(
              child: Container(
                width: 1,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: AppColors.line,
              ),
            ),
          Center(
            child: TopWorkspaceTabChip(
              tab: tabs[i],
              provider: providerFor?.call(tabs[i]),
              isActive: tabs[i] == activeTab,
              status: statusForTab(tabs[i]),
              canClose: canCloseTab(tabs[i]),
              onTap: () => onActivateTab(tabs[i]),
              onClose: () => onCloseTab(tabs[i]),
              chipKey: chipKeyFor(tabs[i].key),
            ),
          ),
          const SizedBox(width: 2),
        ],
        Center(
          child: IconBtn(
            'plus',
            size: 28,
            iconSize: 14,
            tooltip: 'New session',
            onTap: onNewSession,
          ),
        ),
      ],
    );
  }
}

/// The complete macOS window title bar with navigation buttons, tabs strip, and utility actions.
class MacWindowBar extends StatelessWidget {
  final bool canNavigateBack;
  final bool canNavigateForward;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final Widget tabsRow;
  final VoidCallback onOpenSettings;
  final Widget machineSwitcher;
  final List<Widget> tools;
  final bool reserveWindowControls;

  const MacWindowBar({
    super.key,
    required this.canNavigateBack,
    required this.canNavigateForward,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.tabsRow,
    required this.onOpenSettings,
    required this.machineSwitcher,
    this.tools = const [],
    this.reserveWindowControls = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
      decoration: BoxDecoration(
        color: AppColors.windowBg,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: tabsRow)),
          const SizedBox(width: 8),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in tools) ...[
                  tool,
                  const SizedBox(width: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the machines popover dialog anchored to [anchorKey].
Future<void> showTopMachinesPopover({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget content,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  final origin = box.localToGlobal(Offset.zero);
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'machines',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.press,
    pageBuilder: (_, __, ___) => Stack(children: [
      Positioned(
        right: (MediaQuery.of(context).size.width - origin.dx - box.size.width)
            .clamp(10.0, 500.0),
        top: origin.dy + box.size.height + 4,
        width: 260,
        child: Material(
          color: AppColors.overlay,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.lg),
              side: BorderSide(color: AppColors.line)),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: content,
          ),
        ),
      ),
    ]),
  );
}
