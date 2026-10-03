import 'package:flutter/material.dart';

import '../api.dart';
import '../platform.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_welcome.dart';

/// Single-pane or narrow-window main view displaying workspace tabs via a [PageView].
class MainPaneView extends StatelessWidget {
  const MainPaneView({
    super.key,
    required this.client,
    required this.tabs,
    required this.activeIndex,
    required this.pageController,
    required this.onPageChanged,
    required this.tabBodyBuilder,
    required this.welcomeView,
    required this.recentPlaceholder,
    this.tabStrip,
    this.onMenu,
  });

  final DaemonClient? client;
  final List<ShellTab> tabs;
  final int activeIndex;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final Widget Function(ShellTab tab, bool primary) tabBodyBuilder;
  final Widget welcomeView;
  final Widget recentPlaceholder;
  final Widget? tabStrip;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    if (client == null) {
      return ShellWithMenu(onMenu: onMenu, child: welcomeView);
    }
    if (tabs.isEmpty) {
      return ShellWithMenu(onMenu: onMenu, child: recentPlaceholder);
    }
    return Column(children: [
      // Narrow desktop keeps its local strip because the sidebar is a drawer.
      if (!kMacOS && tabStrip != null) tabStrip!,
      Expanded(
        // Pane-scoped MediaQuery so window-width sizing (chat bubbles) fits the pane.
        child: LayoutBuilder(builder: (ctx, c) {
          final mq = MediaQuery.of(ctx);
          return MediaQuery(
            data: mq.copyWith(size: Size(c.maxWidth, c.maxHeight)),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Disconnect the old session's TextField as soon as a horizontal
                // page swipe starts. Waiting for onPageChanged leaves the old
                // field as the platform text-input client during the gesture.
                if (notification is ScrollStartNotification &&
                    notification.metrics.axis == Axis.horizontal) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: PageView.builder(
                controller: pageController,
                physics: kMobile ? null : const NeverScrollableScrollPhysics(),
                itemCount: tabs.length,
                onPageChanged: (i) {
                  // PageView keeps each session mounted. Remove focus from the
                  // old composer before changing the active page so the platform
                  // text-input client cannot remain attached to the previous
                  // session after a swipe.
                  FocusManager.instance.primaryFocus?.unfocus();
                  onPageChanged(i);
                },
                itemBuilder: (_, i) {
                  final t = tabs[i];
                  return ShellKeepAlive(
                    key: ValueKey(t.key),
                    keep: t.isMissionControl || i == activeIndex,
                    // Same body builder as the split panes, so a terminal
                    // or a diff renders identically whether it is in a pane or
                    // the narrow single-column layout.
                    child: tabBodyBuilder(t, i == activeIndex),
                  );
                },
              ),
            ),
          );
        }),
      ),
    ]);
  }
}
