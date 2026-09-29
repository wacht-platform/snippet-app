import 'dart:async';
import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

OverlayEntry? _activeToast;
Timer? _toastTimer;

ShapeBorder get appMenuShape => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(R.lg),
      side: BorderSide(color: AppColors.line),
    );

PopupMenuItem<T> appMenuItem<T>({
  required T value,
  required String label,
  String? icon,
  String? detail,
  bool danger = false,
  bool selected = false,
  double height = 36,
}) {
  final color = danger ? AppColors.danger : AppColors.fg1;
  return PopupMenuItem<T>(
    value: value,
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: S.s12),
    child: Row(children: [
      if (icon != null) ...[
        AppIcon(icon,
            size: 16, color: danger ? AppColors.danger : AppColors.fg3),
        const SizedBox(width: S.s12),
      ],
      Expanded(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (kMobile ? TS.ui(color) : sans(13, color: color))),
      ),
      if (detail != null) Text(detail, style: TS.meta()),
      if (selected) ...[
        const SizedBox(width: S.s8),
        AppIcon('check', size: 14, color: AppColors.accent),
      ],
    ]),
  );
}

/// A richer popover row: icon, title, optional one-line description, and a
/// trailing check when selected. Used by the composer's approval and provider
/// menus, where the choice needs explaining rather than just naming.
PopupMenuItem<T> appMenuRow<T>({
  required T value,
  required String icon,
  required String label,
  String? description,
  String? trailing,
  bool selected = false,
  double height = 56,
}) {
  return PopupMenuItem<T>(
    value: value,
    height: height,
    // Deliberately small: the row draws its own rounded, filled hit area, so a
    // large outer padding would double up and inset the fill too far.
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        // Icon in a tinted tile. A bare 15px glyph floating beside two lines of
        // text had no visual anchor, which is most of why these menus read flat.
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentBg : AppColors.surface3,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: AppIcon(icon,
              size: 16, color: selected ? AppColors.accent : AppColors.fg3),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.label(AppColors.fg1)),
              if (description != null) ...[
                const SizedBox(height: 2.5),
                Text(description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta()),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing, style: TS.caption()),
        ],
        // The check is the one saturated mark in the row, so "this is the
        // current setting" is legible at a glance rather than one grey glyph
        // among four.
        if (selected) ...[
          const SizedBox(width: 8),
          AppIcon('check', size: 15, color: AppColors.accent),
        ],
      ]),
    ),
  );
}

/// A menu title placed above a group of rows (showMenu takes these as disabled
/// items, which is the only way to put non-selectable text in a popup menu).
PopupMenuItem<T> appMenuHeading<T>(String label) => PopupMenuItem<T>(
      enabled: false,
      height: 34,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      // Upper case -> `caps()`, and a group heading is a label, not a
      // disabled control, so `fg3` rather than the `fg4` placeholder rung.
      child: Text(label.toUpperCase(), style: TS.overline()),
    );

/// Present a menu in the shape the platform expects.
///
/// ONE entry point for every `appMenuItem`/`appMenuRow` menu in the app: a bottom
/// sheet on a phone (full width, rows at real touch height, thumb reachable) and
/// an anchored popover on desktop.
///
/// Callers previously each computed a `RelativeRect` and called `showMenu`
/// directly, which is why the same menu opened as a cramped floating card on a
/// phone — 40px rows, 12px padding, no grab handle, no sheet affordance.
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<PopupMenuEntry<T>> items,

  /// The control this menu belongs to; the desktop popover anchors to it.
  BuildContext? anchor,

  /// Optional vertical reference box (e.g. the composer card container).
  /// When provided, the menu positions its top/bottom edge relative to this
  /// box instead of the anchor control, avoiding covering the input area.
  BuildContext? verticalAnchor,

  /// Explicit screen point (long-press / right-click). Wins over [anchor].
  Offset? point,
  double minWidth = 260,
  double maxWidth = 340,
  Color? color,

  /// Open BELOW the anchor instead of above it. Set for controls at the TOP of
  /// the window (the shell menu), where an upward menu would be clipped offscreen.
  bool below = false,

  /// Align the popover's RIGHT edge with the anchor's, instead of its left.
  /// Set for a control at the right end of a narrow bar — a section header's
  /// actions, say — where a left-aligned popover would open away from the button
  /// it belongs to.
  bool alignEnd = false,
}) {
  final bg = color ?? AppColors.overlay;

  if (kMobile) {
    return showModalBottomSheet<T>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        return ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
          child: Container(
            decoration: BoxDecoration(
              color: color ?? AppColors.raised,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: S.s6),
                  Center(
                      child: Container(
                          width: 32,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppColors.lineStrong,
                              borderRadius: BorderRadius.circular(R.pill)))),
                  const SizedBox(height: S.s8),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: S.s12),
                      child: Material(
                        color: AppColors.overlay,
                        borderRadius: BorderRadius.circular(R.md),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: S.s4),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final item in items)
                                  _appMenuSheetEntry(sheet, item),
                              ]),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: media.padding.bottom + S.s12),
                ]),
          ),
        );
      },
    );
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  RelativeRect position;
  if (overlay == null) {
    position = const RelativeRect.fromLTRB(16, 80, 16, 80);
  } else if (point != null) {
    position = RelativeRect.fromRect(
      Rect.fromCircle(center: point, radius: 0),
      Offset.zero & overlay.size,
    );
  } else if (anchor != null) {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) {
      position = const RelativeRect.fromLTRB(16, 80, 16, 80);
    } else {
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      final vertBox = verticalAnchor?.findRenderObject() as RenderBox?;
      final vertOrigin = vertBox != null
          ? vertBox.localToGlobal(Offset.zero, ancestor: overlay)
          : origin;
      final topY = below
          ? (vertOrigin.dy + (vertBox?.size.height ?? box.size.height) + 6)
          : (vertOrigin.dy - 6);
      final alignRight = origin.dx + box.size.width;
      final left = alignEnd
          ? (alignRight - minWidth)
              .clamp(12.0, overlay.size.width - minWidth - 12)
          : origin.dx.clamp(12.0, overlay.size.width - minWidth - 12);

      position = RelativeRect.fromLTRB(
        alignEnd ? overlay.size.width : left,
        topY,
        alignEnd ? (overlay.size.width - alignRight) : overlay.size.width,
        below ? overlay.size.height : 0,
      );
    }
  } else {
    position = const RelativeRect.fromLTRB(16, 80, 16, 80);
  }

  return showMenu<T>(
    context: context,
    position: position,
    color: bg,
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.4),
    surfaceTintColor: Colors.transparent,
    shape: appMenuShape,
    menuPadding: const EdgeInsets.symmetric(vertical: S.s4),
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
    items: items,
  );
}

/// One entry inside the phone menu sheet.
///
/// Mirrors what `PopupMenuItem` draws, so a helper-built row needs no
/// mobile-specific variant — but sized to a real touch target, which the popup
/// defaults are not.
Widget _appMenuSheetEntry<T>(BuildContext sheet, PopupMenuEntry<T> entry) {
  if (entry is PopupMenuDivider) {
    return Divider(height: 9, thickness: 1, color: AppColors.line);
  }
  if (entry is! PopupMenuItem<T>) {
    return const SizedBox.shrink();
  }
  final pad = entry.padding ?? const EdgeInsets.symmetric(horizontal: S.s12);
  // A heading is a section label and is deliberately NOT tappable.
  if (!entry.enabled) {
    return Padding(
      padding: pad,
      child: SizedBox(height: entry.height, child: entry.child),
    );
  }
  return InkWell(
    onTap: () => Navigator.pop(sheet, entry.value),
    child: Padding(
      // The row now draws its own rounded, filled hit area for desktop, where a
      // 4px outer inset is right — the popover supplies the surrounding gutter.
      // A SHEET does not: it is full width, so inheriting 4px would run the fill
      // nearly edge-to-edge. Impose the sheet's own gutter here and let the row's
      // fill sit inside it.
      padding: const EdgeInsets.symmetric(horizontal: S.s4),
      child: SizedBox(
        height: 44,
        child: entry.child,
      ),
    ),
  );
}

/// A slick, theme-styled toast rendered in the ROOT overlay — so it floats above
/// panels/dialogs instead of a SnackBar buried behind a modal backdrop. A new one
/// replaces the previous (no stacking). Use for transient feedback.
void toast(BuildContext context, String message, {bool danger = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeToast?.remove();
  _toastTimer?.cancel();
  final entry = OverlayEntry(
    builder: (ctx) => _toastSlot(ctx,
        IgnorePointer(child: _ToastCard(message: message, danger: danger))),
  );
  _activeToast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 2600), () {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
    }
  });
}

/// A toast with tappable action buttons (e.g. Open / Share after a download).
/// Unlike [toast] it isn't IgnorePointer'd, and it lingers longer so the actions
/// are reachable. Tapping an action dismisses it.
typedef ToastAction = ({String label, String icon, VoidCallback onTap});

void actionToast(BuildContext context, String message,
    {required List<ToastAction> actions}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeToast?.remove();
  _toastTimer?.cancel();
  late final OverlayEntry entry;
  void dismiss() {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
      _toastTimer?.cancel();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _toastSlot(
      ctx,
      Center(
        child: _ToastCard(
          message: message,
          danger: false,
          actions: actions
              .map((a) => (
                    label: a.label,
                    icon: a.icon,
                    onTap: () {
                      // Run the action first, then tear the toast down — removing the
                      // overlay entry mid-tap could otherwise swallow the action.
                      a.onTap();
                      dismiss();
                    }
                  ))
              .toList(),
        ),
      ),
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 6000), dismiss);
}

/// Where toasts sit: under the status bar on phones, so they never cover the
/// composer or the bottom bar; bottom-centre on desktop.
Widget _toastSlot(BuildContext ctx, Widget card) {
  final pad = MediaQuery.of(ctx).padding;
  return Positioned(
    left: 0,
    right: 0,
    top: kMobile ? pad.top + S.s12 : null,
    bottom: kMobile ? null : pad.bottom + 24,
    child: Center(child: card),
  );
}

class _ToastCard extends StatefulWidget {
  final String message;
  final bool danger;
  final List<ToastAction> actions;
  const _ToastCard(
      {required this.message, required this.danger, this.actions = const []});
  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  /// Eager, in initState — a lazy `late final` makes `dispose` the first access
  /// when `build` never runs, constructing a controller on a dead element. Same
  /// defect class as `_StatusDotState`; fixed together so it cannot recur.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.base)..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final curve = CurvedAnimation(parent: _c, curve: Motion.enter);
    // Only the icon carries the tone; the message stays readable.
    final tone = widget.danger ? AppColors.danger : AppColors.ok;
    // Material ancestor: without it, text floating in the root Overlay falls back
    // to the debug default style (the yellow underline). It also gives clean ink.
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position:
              Tween(begin: Offset(0, kMobile ? -0.25 : 0.25), end: Offset.zero)
                  .animate(curve),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(horizontal: M.gutter),
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppColors.lineStrong),
              boxShadow: overlayShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(widget.danger ? 'alert-triangle' : 'check-circle',
                  size: 15, color: tone),
              const SizedBox(width: 10),
              Flexible(
                child: Text(widget.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, height: 1.4, color: AppColors.fg1)
                        .copyWith(decoration: TextDecoration.none)),
              ),
              for (final a in widget.actions) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: a.onTap,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(a.label,
                        style:
                            sans(13, weight: W.label, color: AppColors.accent)
                                .copyWith(decoration: TextDecoration.none)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Open a markdown link in the external browser (fire-and-forget).
/// Compact relative time like "now", "5m", "3h", "2d", "4mo" (empty for 0).
String relativeTime(int unixSec) {
  if (unixSec == 0) return '';
  final d = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(unixSec * 1000));
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 30) return '${d.inDays}d';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
  return '${(d.inDays / 365).floor()}y';
}

/// Human-readable byte size (B / KB / MB). Accepts an int or anything parseable.
String formatBytes(dynamic n) {
  final b = n is int ? n : int.tryParse(n.toString()) ?? 0;
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Last non-empty path segment (the folder/file name), or [ifEmpty] when there is none.
String lastPathSegment(String path, {String ifEmpty = ''}) {
  final seg = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
  return seg ?? (path.isEmpty ? ifEmpty : path);
}

/// A row of selectable rounded pills. [items] maps each value to its label;
