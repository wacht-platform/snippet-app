import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_models.dart';

/// Context menu shown when right clicking or long-pressing a tab.
void showTabContextMenu({
  required BuildContext context,
  required ShellTab tab,
  required int index,
  required bool hasNonMissionControlTabs,
  required VoidCallback onCloseTab,
  required VoidCallback onCloseOthers,
  required VoidCallback onCloseAll,
}) {
  Widget tabMenuItem(
    BuildContext ctx,
    String icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.fg1;
    return InkWell(
      onTap: () {
        Navigator.of(ctx).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          AppIcon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Text(label, style: sans(13, color: color)),
        ]),
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface1,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Row(children: [
            AppIcon(tab.isFile ? 'file' : 'terminal',
                size: 15, color: AppColors.fg3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tab.title.isEmpty ? '(untitled)' : tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: AppColors.fg1)),
            ),
          ]),
        ),
        Divider(height: 1, color: AppColors.border),
        if (!tab.isMissionControl)
          tabMenuItem(ctx, 'x', 'Close tab', onCloseTab),
        if (hasNonMissionControlTabs)
          tabMenuItem(ctx, 'copy', 'Close other tabs', onCloseOthers),
        if (hasNonMissionControlTabs)
          tabMenuItem(ctx, 'trash', 'Close all tabs', onCloseAll,
              danger: true),
      ]),
    ),
  );
}

/// A standalone rounded card tab chip used in fallback desktop and mobile layouts.
class CardTabChip extends StatelessWidget {
  final ShellTab tab;
  final bool isActive;
  final String subtitle;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onClose;
  final GlobalKey chipKey;

  const CardTabChip({
    super.key,
    required this.tab,
    required this.isActive,
    required this.subtitle,
    required this.canClose,
    required this.onTap,
    required this.onLongPress,
    required this.onClose,
    required this.chipKey,
  });

  @override
  Widget build(BuildContext context) {
    final title = tab.title.isEmpty ? '(untitled)' : tab.title;
    final desktop = !kMobile;

    if (!desktop) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.enter,
          key: chipKey,
          margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: isActive ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: isActive ? AppColors.border : Colors.transparent,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(
              tabIconKind(tab),
              size: 12,
              color: isActive ? AppColors.accent : AppColors.fg4,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    sans(12, color: isActive ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (canClose) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon('x', size: 10, color: AppColors.fg4),
                ),
              ),
            ],
          ]),
        ),
      );
    }

    // Desktop card tab: bounded width, distinct card surface, 2-line label
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: Motion.press,
        curve: Motion.enter,
        key: chipKey,
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: activeBorderColor(isActive),
          ),
        ),
        child: Row(
          children: [
            AppIcon(
              tabIconKind(tab),
              size: 14,
              color: isActive ? AppColors.accent : AppColors.fg4,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(
                      11,
                      weight: isActive ? W.label : W.body,
                      color: isActive ? AppColors.fg1 : AppColors.fg3,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(10, color: AppColors.fg3),
                  ),
                ],
              ),
            ),
            if (canClose) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.xs),
                  ),
                  child: AppIcon('x',
                      size: 10, color: isActive ? AppColors.fg3 : AppColors.fg4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color activeBorderColor(bool isActive) =>
      isActive ? AppColors.border2 : Colors.transparent;
}

/// The horizontal card tab strip with sidebar toggle, cards list, plus button, and file actions.
class CardTabStrip extends StatelessWidget {
  final ScrollController controller;
  final List<ShellTab> tabs;
  final int activeIndex;
  final VoidCallback? onMenu;
  final String Function(ShellTab) subtitleForTab;
  final bool Function(ShellTab) canCloseTab;
  final void Function(int) onActivateTab;
  final void Function(int) onTabMenu;
  final void Function(int) onCloseTab;
  final VoidCallback onNewTab;
  final bool isFileActive;
  final VoidCallback? onDownloadFile;
  final VoidCallback? onEditFile;
  final GlobalKey Function(String key) chipKeyFor;

  const CardTabStrip({
    super.key,
    required this.controller,
    required this.tabs,
    required this.activeIndex,
    this.onMenu,
    required this.subtitleForTab,
    required this.canCloseTab,
    required this.onActivateTab,
    required this.onTabMenu,
    required this.onCloseTab,
    required this.onNewTab,
    this.isFileActive = false,
    this.onDownloadFile,
    this.onEditFile,
    required this.chipKeyFor,
  });

  @override
  Widget build(BuildContext context) {
    final compact = kMobile ? M.tabStripHeight : 42.0;
    return Container(
      height: compact,
      color: AppColors.bg,
      child: Row(children: [
        if (onMenu != null)
          IconBtn('sidebar',
              size: kMobile ? M.tabActionSize : 36,
              iconSize: kMobile ? M.tabIconSize : 16,
              tooltip: 'Sidebar',
              onTap: onMenu),
        Expanded(
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  CardTabChip(
                    tab: tabs[i],
                    isActive: i == activeIndex,
                    subtitle: subtitleForTab(tabs[i]),
                    canClose: canCloseTab(tabs[i]),
                    onTap: () => onActivateTab(i),
                    onLongPress: () => onTabMenu(i),
                    onClose: () => onCloseTab(i),
                    chipKey: chipKeyFor(tabs[i].key),
                  ),
                const SizedBox(width: 4),
                IconBtn(
                  'plus',
                  size: 28,
                  iconSize: 14,
                  tooltip: 'New tab',
                  onTap: onNewTab,
                ),
              ],
            ),
          ),
        ),
        if (!kMobile && isFileActive) ...[
          if (onDownloadFile != null)
            IconBtn('download',
                size: 32,
                iconSize: 14,
                tooltip: 'Download',
                onTap: onDownloadFile),
          if (onEditFile != null)
            IconBtn('edit',
                size: 32,
                iconSize: 14,
                tooltip: 'Edit',
                onTap: onEditFile),
        ],
      ]),
    );
  }
}
