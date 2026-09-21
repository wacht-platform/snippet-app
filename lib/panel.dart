import 'dart:ui';

import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';

enum PanelStyle { drawer, dialog }

/// Present [builder]'s screen as an overlay whose layout adapts to the window:
/// full-screen when narrow (phone / shrunk window), a right-side drawer or a
/// centered dialog when wide. Because the layout is chosen inside a LayoutBuilder,
/// it re-lays out live when the window crosses the breakpoint while open.
/// [builder] gets a `close` callback to dismiss.
Future<T?> presentScreen<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PanelStyle style = PanelStyle.dialog,
  bool dismissible = true,
  double maxWidth = 720,
  double maxHeight = 640,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'panel',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: Motion.fast,
    pageBuilder: (ctx, _, __) {
      void close() => Navigator.of(ctx).pop();
      // Host the screen directly; sub-pushes (file viewer, diff) go to the root
      // navigator over the panel, which is fine.
      final content = builder(ctx, close);
      return LayoutBuilder(builder: (lctx, c) {
        final wide = c.maxWidth >= kDesktopBreakpoint;
        if (!wide) {
          return _frame(content, rounded: false, edge: false);
        }
        if (style == PanelStyle.dialog) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
                  child: _frame(content, rounded: true)),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
              width: c.maxWidth < 500 ? c.maxWidth : 460.0,
              height: double.infinity,
              child: _frame(content, rounded: false, edge: true)),
        );
      });
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.enter);
      final transition = (style == PanelStyle.dialog)
          ? FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.0).animate(curved),
                  child: child),
            )
          : SlideTransition(
              position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                  .animate(curved),
              child: child,
            );
      return BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 20.0 * curved.value, sigmaY: 20.0 * curved.value),
        child: transition,
      );
    },
  );
}

/// Present an adaptive panel: a rounded, dismissible bottom sheet on phones
/// and the existing drawer/dialog treatment on wider layouts.
Future<T?> presentAdaptivePanel<T>(
  BuildContext context,
  Widget child, {
  PanelStyle style = PanelStyle.drawer,
  double maxWidth = 720,
  double maxHeight = 820,
}) {
  if (!kMobile) {
    return presentScreen<T>(
      context,
      style: style,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      builder: (_, __) => child,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.56),
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.92;
      return SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Material(
            color: AppColors.bg,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(R.sheetTop),
            ),
            child: Column(children: [
              const SizedBox(height: 8),
              Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: child),
            ]),
          ),
        ),
      );
    },
  );
}

/// Present a SELF-CONTAINED screen (no internal sub-pushes) as a centered modal
/// that returns a value. The screen's own `Navigator.pop(context, value)` closes
/// the modal and yields that value (e.g. AddInstanceScreen returning an Instance).
/// Falls back to a full-screen push on phones.
Future<T?> showModal<T>(
  BuildContext context,
  Widget child, {
  double width = 560,
  double height = 540,
}) {
  final view = View.of(context);
  final windowWidth = view.physicalSize.width / view.devicePixelRatio;
  if (windowWidth < kDesktopBreakpoint) {
    return Navigator.of(context)
        .push<T>(MaterialPageRoute(builder: (_) => child));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'modal',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: Motion.fast,
    pageBuilder: (ctx, _, __) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: height),
          child: _frame(child, rounded: true),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.enter);
      return BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 20.0 * curved.value, sigmaY: 20.0 * curved.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(curved),
              child: child),
        ),
      );
    },
  );
}

// Wide presentations (right drawer / centered dialog) sit on surface1 like
// every other popover, with the hosted Scaffolds re-based onto the same
// surface (single background, no darker strip). Narrow/full-screen keeps the
// plain shell background so phones look exactly as before.
Widget _frame(Widget child, {required bool rounded, bool edge = true}) {
  final panel = rounded || edge;
  final color = panel ? AppColors.glassSurface : AppColors.bg;
  final radius = BorderRadius.circular(R.card);

  Widget themedBody = !panel
      ? child
      : Builder(
          builder: (ctx) => Theme(
            data: Theme.of(ctx).copyWith(scaffoldBackgroundColor: color),
            child: child,
          ),
        );

  if (rounded) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: themedBody,
        ),
      ),
    );
  }

  if (edge) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            border: Border(left: BorderSide(color: AppColors.glassBorder)),
          ),
          child: themedBody,
        ),
      ),
    );
  }

  return themedBody;
}
