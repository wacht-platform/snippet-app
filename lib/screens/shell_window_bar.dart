import 'package:flutter/material.dart';

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
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(tabIconKind(tab), size: 13, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(
            tab.title.isEmpty ? '(untitled)' : tab.title,
            style: sans(12, color: AppColors.fg1),
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

  const TopWorkspaceTabChip({
    super.key,
    required this.tab,
    required this.isActive,
    required this.status,
    required this.canClose,
    required this.onTap,
    this.onClose,
    this.chipKey,
  });

  @override
  Widget build(BuildContext context) {
    final title = tab.title.isEmpty ? '(untitled)' : tab.title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: chipKey,
        height: kTitleTabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.bg : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.md)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SessionStateIcon(
              status: status,
              icon: tabIconKind(tab),
              size: 18,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14,
                    weight: isActive ? W.label : W.body,
                    color: isActive ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (canClose && onClose != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon('x', size: 13, color: AppColors.fg4),
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
                      border: Border.all(color: AppColors.border2),
                    ),
                    child: Text(
                      initial,
                      style: sans(10, weight: W.title, color: AppColors.fg1),
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
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 4),
      children: [
        for (final t in tabs) ...[
          TopWorkspaceTabChip(
            tab: t,
            isActive: t == activeTab,
            status: statusForTab(t),
            canClose: canCloseTab(t),
            onTap: () => onActivateTab(t),
            onClose: () => onCloseTab(t),
            chipKey: chipKeyFor(t.key),
          ),
          const SizedBox(width: 4),
        ],
        Center(
          child: IconBtn(
            'plus',
            size: 24,
            iconSize: 16,
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

  const MacWindowBar({
    super.key,
    required this.canNavigateBack,
    required this.canNavigateForward,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.tabsRow,
    required this.onOpenSettings,
    required this.machineSwitcher,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: macOSIsFullscreen(),
      builder: (context, snapshot) {
        final hasWindowControls = snapshot.data != true;
        return SizedBox(
          height: kTitleBarHeight,
          child: ColoredBox(
            color: AppColors.floor,
            child: Padding(
              padding: EdgeInsets.only(
                left: hasWindowControls ? kTrafficLightReserve : 16,
                right: 20,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconBtn(
                          'chevron-left',
                          size: 24,
                          iconSize: 16,
                          tooltip: 'Back',
                          onTap: canNavigateBack ? onNavigateBack : null,
                        ),
                        IconBtn(
                          'chevron-right',
                          size: 24,
                          iconSize: 16,
                          tooltip: 'Forward',
                          onTap: canNavigateForward ? onNavigateForward : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(child: tabsRow),
                  ),
                  const SizedBox(width: 8),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconBtn(
                          'settings',
                          size: 24,
                          iconSize: 16,
                          tooltip: 'Settings',
                          onTap: onOpenSettings,
                        ),
                        const SizedBox(width: 6),
                        machineSwitcher,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        right:
            (MediaQuery.of(context).size.width - origin.dx - box.size.width)
                .clamp(10.0, 500.0),
        top: origin.dy + box.size.height + 4,
        width: 260,
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.md),
          elevation: 12,
          shadowColor: Colors.black87,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: content,
          ),
        ),
      ),
    ]),
  );
}
