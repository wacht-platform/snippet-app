import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../notifications.dart';
import '../theme.dart';
import 'shell_models.dart';

/// Full-screen mobile shell layout with sliding sidebar and platform back handling.
class MobileShell extends StatelessWidget {
  final Widget? activeTabBody;
  final Widget sidebar;
  final bool hasActiveTab;
  final bool chatsOpen;
  final bool drilledDown;
  final MobileHome mobileHome;
  final VoidCallback onClearDrillDown;
  final ValueChanged<MobileHome> onMobileHome;
  final VoidCallback onCloseChats;
  final VoidCallback? onOpenChats;
  final bool? canPopRoute;
  final VoidCallback? onPopRoute;

  const MobileShell({
    super.key,
    required this.activeTabBody,
    required this.sidebar,
    required this.hasActiveTab,
    required this.chatsOpen,
    required this.drilledDown,
    required this.mobileHome,
    required this.onClearDrillDown,
    required this.onMobileHome,
    required this.onCloseChats,
    this.onOpenChats,
    this.canPopRoute,
    this.onPopRoute,
  });

  @override
  Widget build(BuildContext context) {
    final chatsVisible = chatsOpen || !hasActiveTab;
    final canPop = canPopRoute ??
        (!chatsVisible || drilledDown || mobileHome != MobileHome.agents);

    void handleBack() {
      if (onPopRoute != null) {
        onPopRoute!();
        return;
      }
      if (!chatsVisible) {
        if (onOpenChats != null) {
          onOpenChats!();
        } else {
          onCloseChats();
        }
      } else if (drilledDown) {
        onClearDrillDown();
      } else if (mobileHome != MobileHome.agents) {
        onMobileHome(MobileHome.agents);
      }
    }

    final shell = Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        if (activeTabBody != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: chatsVisible,
              child: AnimatedSlide(
                duration: Motion.base,
                curve: Motion.enter,
                offset: chatsVisible ? const Offset(0.15, 0) : Offset.zero,
                child: AnimatedOpacity(
                  duration: Motion.base,
                  curve: Motion.enter,
                  opacity: chatsVisible ? 0.0 : 1.0,
                  child: SafeArea(
                    bottom: false,
                    child: activeTabBody!,
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !chatsVisible,
            child: AnimatedSlide(
              duration: Motion.base,
              curve: Motion.enter,
              offset: chatsVisible ? Offset.zero : const Offset(-1, 0),
              child: Material(
                color: AppColors.bg,
                child: SafeArea(
                  child: sidebar,
                ),
              ),
            ),
          ),
        ),
        // When in an active session, an edge swipe from the left edge navigates
        // back to the previous screen without trapping the user.
        if (!chatsVisible && (onOpenChats != null || onPopRoute != null))
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 100) {
                  handleBack();
                }
              },
              onHorizontalDragUpdate: (details) {
                if (details.delta.dx > 10) {
                  handleBack();
                }
              },
            ),
          ),
      ]),
    );

    if (canPop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          handleBack();
        },
        child: shell,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await watcherServiceRunning()) {
          minimizeApp();
        } else {
          SystemNavigator.pop();
        }
      },
      child: shell,
    );
  }
}
