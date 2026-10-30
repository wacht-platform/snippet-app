import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final bool missionPair;
  final VoidCallback? onSwipeToSessions;
  final VoidCallback? onSwipeToMission;

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
    this.missionPair = false,
    this.onSwipeToSessions,
    this.onSwipeToMission,
  });

  @override
  Widget build(BuildContext context) {
    final chatsVisible = chatsOpen || !hasActiveTab;
    final canPop = canPopRoute ??
        (!chatsVisible || drilledDown || mobileHome != MobileHome.chats);

    void handleBack() {
      final route = ModalRoute.of(context);
      if (route?.willHandlePopInternally ?? false) {
        Navigator.of(context).pop();
        return;
      }
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
      } else if (mobileHome != MobileHome.chats) {
        onMobileHome(MobileHome.chats);
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
                offset: chatsVisible
                    ? Offset(missionPair ? -0.25 : 0.15, 0)
                    : Offset.zero,
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
              offset:
                  chatsVisible ? Offset.zero : Offset(missionPair ? 1 : -1, 0),
              child: Material(
                color: AppColors.bg,
                child: SafeArea(
                  child: sidebar,
                ),
              ),
            ),
          ),
        ),
        // iOS has no system back gesture for this in-app stack, so an edge
        // swipe provides one. It fires once per gesture, after a deliberate
        // travel or flick. Android already routes its back gesture through
        // PopScope below; a second detector there made one swipe go back
        // several screens.
        if (!chatsVisible &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            (onOpenChats != null || onPopRoute != null))
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 20,
            child: _EdgeSwipeBack(onBack: handleBack),
          ),
      ]),
    );

    final swipe = chatsVisible
        ? (mobileHome == MobileHome.chats && !drilledDown
            ? onSwipeToMission
            : null)
        : (missionPair ? onSwipeToSessions : null);
    final body = swipe != null
        ? _PairSwipe(toRight: chatsVisible, onSwipe: swipe, child: shell)
        : shell;

    if (canPop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          handleBack();
        },
        child: body,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
          Navigator.of(context).pop();
          return;
        }
        SystemNavigator.pop();
      },
      child: body,
    );
  }
}

class _PairSwipe extends StatefulWidget {
  final bool toRight;
  final VoidCallback onSwipe;
  final Widget child;
  const _PairSwipe(
      {required this.toRight, required this.onSwipe, required this.child});

  @override
  State<_PairSwipe> createState() => _PairSwipeState();
}

class _PairSwipeState extends State<_PairSwipe> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) {
    final dir = widget.toRight ? 1.0 : -1.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _travel = 0,
      onHorizontalDragUpdate: (d) => _travel += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final v = (d.primaryVelocity ?? 0) * dir;
        if (_travel * dir > 80 || v > 600) {
          HapticFeedback.selectionClick();
          widget.onSwipe();
        }
        _travel = 0;
      },
      onHorizontalDragCancel: () => _travel = 0,
      child: widget.child,
    );
  }
}

class _EdgeSwipeBack extends StatefulWidget {
  final VoidCallback onBack;
  const _EdgeSwipeBack({required this.onBack});

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _travel = 0,
      onHorizontalDragUpdate: (d) => _travel += d.delta.dx,
      onHorizontalDragEnd: (d) {
        if (_travel > 60 || (d.primaryVelocity ?? 0) > 700) widget.onBack();
        _travel = 0;
      },
      onHorizontalDragCancel: () => _travel = 0,
    );
  }
}
