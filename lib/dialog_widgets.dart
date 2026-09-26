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
            style: sans(12, weight: W.label, color: AppColors.fg2)),
        const SizedBox(height: 7),
      ],
      AnimatedContainer(
        duration: Motion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        constraints: BoxConstraints(minHeight: kMobile ? 44 : 34),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
              color: _focus.hasFocus ? AppColors.accentLine : AppColors.border),
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
              style: widget.mono
                  ? mono(13, color: AppColors.fg1)
                  : sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: kMobile ? 8 : 8),
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: widget.mono
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
            style: sans(11, height: 1.4, color: AppColors.fg3)),
      ],
    ]);
  }
}

/// Bottom sheet matching the handoff (drag handle, title + close, scroll body).
/// A bottom-sheet single-field text prompt (rename, etc.). Returns the trimmed
/// text on save, or null if cancelled.
/// Compact confirm — no oversized desktop sheet chrome.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Delete',
  bool danger = true,
}) async {
  final accent = danger ? AppColors.danger : AppColors.accent;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (ctx) {
      return Dialog(
        backgroundColor: AppColors.glassSurface,
        elevation: 0,
        insetPadding:
            EdgeInsets.symmetric(horizontal: kMobile ? 24 : 40, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.card),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Tinted badge: a destructive confirm should look
                    // destructive before you read a word of it.
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: AppIcon(danger ? 'alert-triangle' : 'alert-circle',
                          size: 16, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(title,
                            style: sans(14,
                                weight: W.label, color: AppColors.fg1)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // The body gets its OWN line, aligned under the title rather
                  // than beside it. Sharing one Row made the body wrap into a
                  // narrow column next to a one-line title, so the dialog read
                  // as two unrelated fragments.
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: Text(body,
                        style: sans(12, height: 1.5, color: AppColors.fg3)),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Spacer(),
                    Btn('Cancel',
                        variant: BtnVariant.ghost,
                        small: true,
                        onTap: () => Navigator.pop(ctx, false)),
                    const SizedBox(width: 8),
                    Btn(confirmLabel,
                        variant:
                            danger ? BtnVariant.danger : BtnVariant.primary,
                        small: true,
                        onTap: () => Navigator.pop(ctx, true)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}

Future<String?> promptText(BuildContext context,
    {required String title,
    String initial = '',
    String? hint,
    String saveLabel = 'Save',
    int minLines = 1,
    int maxLines = 1}) {
  if (!kMobile) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.glassSurface,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
            side: BorderSide(color: AppColors.glassBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(R.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        style: sans(13, weight: W.label, color: AppColors.fg1)),
                    const SizedBox(height: 10),
                    _TextPromptSheet(
                        initial: initial,
                        hint: hint,
                        saveLabel: saveLabel,
                        minLines: minLines,
                        maxLines: maxLines),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showAppSheet<String>(context,
      title: title,
      child: _TextPromptSheet(
          initial: initial,
          hint: hint,
          saveLabel: saveLabel,
          minLines: minLines,
          maxLines: maxLines));
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
          const SizedBox(height: 10),
          Row(children: [
            const Spacer(),
            Btn('Cancel',
                variant: BtnVariant.ghost,
                small: true,
                onTap: () => Navigator.pop(context)),
            const SizedBox(width: 6),
            Btn(widget.saveLabel, small: true, onTap: _done),
          ]),
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
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.glassSurface,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.md),
            side: BorderSide(color: AppColors.glassBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(R.md),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(title,
                              style: sans(13,
                                  weight: W.label, color: AppColors.fg1))),
                      IconBtn('x',
                          size: 28,
                          iconSize: 14,
                          tooltip: 'Close',
                          onTap: () => Navigator.pop(ctx)),
                    ]),
                    const SizedBox(height: 6),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    isScrollControlled: true,
    useSafeArea: false,
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
          child: ClipRRect(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
            child: Material(
              color: AppColors.surface1,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
                side: BorderSide(color: AppColors.glassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: limit),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 8),
                  Center(
                      child: Container(
                          width: 28,
                          height: 3,
                          decoration: BoxDecoration(
                              color: AppColors.border2,
                              borderRadius: BorderRadius.circular(99)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(children: [
                      Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(16,
                                  weight: W.label, color: AppColors.fg1))),
                      IconBtn('x',
                          size: 32,
                          iconSize: 16,
                          tooltip: 'Close',
                          onTap: () => Navigator.pop(sheetContext)),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          20, 0, 20, 16 + media.padding.bottom),
                      child: child,
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
