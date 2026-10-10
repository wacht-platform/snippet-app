import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class AppField extends StatefulWidget {
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final bool mono;
  final bool obscure;
  final String? icon;
  final Widget? rightSlot;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  const AppField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.mono = false,
    this.obscure = false,
    this.icon,
    this.rightSlot,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
  });
  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) ...[
        Text(widget.label!,
            style: kMobile
                ? sans(12, color: AppColors.fg4)
                : sans(12, weight: W.label, color: AppColors.fg2)),
        SizedBox(height: kMobile ? 6 : 7),
      ],
      AnimatedContainer(
        duration: Motion.quick,
        padding: EdgeInsets.symmetric(horizontal: kMobile ? 14 : 11),
        constraints: BoxConstraints(minHeight: kMobile ? 48 : 34),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(kMobile ? 12 : R.md),
          border: Border.all(
              color: _focus.hasFocus
                  ? AppColors.accentLine
                  : (kMobile ? Colors.transparent : AppColors.border)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (widget.icon != null) ...[
            AppIcon(widget.icon!, size: 16, color: AppColors.fg3),
            const SizedBox(width: 8)
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              obscureText: widget.obscure,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              onSubmitted: widget.onSubmitted,
              cursorColor: AppColors.accent,
              style: kMobile
                  ? sans(15, color: AppColors.fg1)
                  : widget.mono
                      ? mono(13, color: AppColors.fg1)
                      : sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: kMobile ? 8 : 8),
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: kMobile
                    ? sans(15, color: AppColors.fg4)
                    : widget.mono
                        ? mono(13, color: AppColors.fg4)
                        : sans(13, color: AppColors.fg4),
              ),
            ),
          ),
          if (widget.rightSlot != null) widget.rightSlot!,
        ]),
      ),
      if (widget.helper != null) ...[
        const SizedBox(height: 7),
        Text(widget.helper!,
            style: kMobile
                ? sans(12, height: 17 / 12, color: AppColors.fg4)
                : sans(11, height: 1.4, color: AppColors.fg3)),
      ],
    ]);
  }
}

/// The desktop dialog every modal shares: one surface, border, radius, title
/// and inset, so confirms, prompts and pickers read as one family. Phones use
/// bottom sheets instead (see [showAppSheet]).
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
    this.onClose,
    this.maxWidth = 400,
    this.maxHeight,
  });

  final String title;
  final Widget child;
  final String? icon;
  final Color? iconColor;
  final VoidCallback? onClose;
  final double maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
              maxWidth: maxWidth, maxHeight: maxHeight ?? double.infinity),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border),
            boxShadow: overlayShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(20, 16, onClose == null ? 20 : 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    if (icon != null) ...[
                      AppIcon(icon!,
                          size: 16, color: iconColor ?? AppColors.fg2),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(kMobile ? 15 : 14,
                              weight: W.label, color: AppColors.fg1)),
                    ),
                    if (onClose != null)
                      IconBtn('x',
                          size: 28,
                          iconSize: 14,
                          tooltip: 'Close',
                          onTap: onClose),
                  ]),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.only(right: onClose == null ? 0 : 8),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Cancel and confirm, laid out for the platform: right-aligned and compact on
/// desktop, two full-width buttons within thumb reach on phones.
class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.danger = false,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final variant = danger ? BtnVariant.danger : BtnVariant.primary;
    if (kMobile) {
      return Row(children: [
        Expanded(
          child: Btn('Cancel',
              full: true, variant: BtnVariant.secondary, onTap: onCancel),
        ),
        const SizedBox(width: S.s8),
        Expanded(
          child:
              Btn(confirmLabel, full: true, variant: variant, onTap: onConfirm),
        ),
      ]);
    }
    return Row(children: [
      const Spacer(),
      Btn('Cancel', variant: BtnVariant.ghost, small: true, onTap: onCancel),
      const SizedBox(width: 8),
      Btn(confirmLabel, variant: variant, small: true, onTap: onConfirm),
    ]);
  }
}

/// Ask before doing something; true when confirmed. A dialog on desktop, a
/// bottom sheet on phones.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Delete',
  bool danger = true,
}) async {
  Widget content(BuildContext ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s4 : 0),
            child: Text(body,
                style:
                    sans(kMobile ? 14 : 13, height: 1.5, color: AppColors.fg2)),
          ),
          SizedBox(height: kMobile ? S.s20 : 18),
          _DialogActions(
            confirmLabel: confirmLabel,
            danger: danger,
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      );
  final bool? result;
  if (kMobile) {
    result = await showAppSheet<bool>(context,
        title: title, child: Builder(builder: content));
  } else {
    result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => _DialogFrame(
        title: title,
        icon: danger ? 'alert-triangle' : null,
        iconColor: AppColors.danger,
        child: content(ctx),
      ),
    );
  }
  return result == true;
}

/// A single-field text prompt (rename, etc.): a dialog on desktop, a bottom
/// sheet on phones. Returns the trimmed text on save, or null if cancelled.
Future<String?> promptText(BuildContext context,
    {required String title,
    String initial = '',
    String? hint,
    String saveLabel = 'Save',
    int minLines = 1,
    int maxLines = 1}) {
  final field = _TextPromptSheet(
      initial: initial,
      hint: hint,
      saveLabel: saveLabel,
      minLines: minLines,
      maxLines: maxLines);
  if (!kMobile) {
    return showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => _DialogFrame(title: title, maxWidth: 380, child: field),
    );
  }
  return showAppSheet<String>(context, title: title, child: field);
}

class _TextPromptSheet extends StatefulWidget {
  final String initial;
  final String? hint;
  final String saveLabel;
  final int minLines;
  final int maxLines;
  const _TextPromptSheet({
    required this.initial,
    required this.hint,
    required this.saveLabel,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
              controller: _controller,
              hint: widget.hint,
              autofocus: true,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              onSubmitted: (_) => _done()),
          SizedBox(height: kMobile ? S.s16 : 14),
          _DialogActions(
            confirmLabel: widget.saveLabel,
            onConfirm: _done,
            onCancel: () => Navigator.pop(context),
          ),
        ]);
  }
}

Future<T?> showAppSheet<T>(BuildContext context,
    {required String title,
    required Widget child,
    // Per-caller sizing. A dialog has room for a wider sheet than the 340px
    // default, which is what the agent picker uses to fit names and roles.
    double maxWidth = 340,
    double maxHeight = 520}) {
  if (!kMobile) {
    return showDialog<T>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => _DialogFrame(
        title: title,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        onClose: () => Navigator.pop(ctx),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 4),
          child: child,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: false,
    sheetAnimationStyle: sheetMotion,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final keyboard = media.viewInsets.bottom;
      // Lift the whole sheet above the keyboard. Padding the *inside* of a
      // pinned-to-bottom sheet just grew a blank band under the field while
      // the keyboard still covered the inputs.
      final aboveKeyboard = media.size.height - keyboard;
      final available = aboveKeyboard * 0.92;
      final limit = available < maxHeight ? available : maxHeight;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ClipRRect(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
            child: Material(
              color: AppColors.raised,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: limit),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SheetHeader(
                      title: title, onClose: () => Navigator.pop(sheetContext)),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          S.s12, S.s6, S.s12, S.s12 + media.padding.bottom),
                      child:
                          SurfaceScope(group: AppColors.overlay, child: child),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A theme-styled switch track + thumb.
///
/// Extracted so a settings row can use the switch WITHOUT the card chrome that
/// [AppToggle] wraps around it. Call sites previously reached for
/// `Transform.scale(child: Switch(...))` to size a Material switch down, which
/// scales the whole widget including its touch target and distorts Material's
/// fixed internal proportions — that is why the result looked wrong.
