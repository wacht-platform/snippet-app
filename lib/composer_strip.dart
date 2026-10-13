import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

class DesktopComposerStrip extends StatelessWidget {
  const DesktopComposerStrip({
    super.key,
    required this.field,
    required this.send,
    this.inline = const [],
    this.footer = const [],
    this.highlight = false,
    this.cardKey,
  });

  final Widget field;
  final Widget send;
  final List<Widget> inline;
  final List<Widget> footer;
  final bool highlight;
  final Key? cardKey;

  static InputDecoration decoration(String hint) => InputDecoration(
        isCollapsed: true,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TS.body(AppColors.fg4),
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: cardKey,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
            decoration: BoxDecoration(
              color: AppColors.raised,
              borderRadius: BorderRadius.circular(12),
              border: highlight
                  ? Border.all(color: AppColors.accent, width: 1.5)
                  : Border.all(color: AppColors.border),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: field),
              for (final w in inline)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8, right: 6),
                    child: w),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: send),
            ]),
          ),
          if (footer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: footer),
            ),
        ],
      );
}

class StripSendButton extends StatelessWidget {
  const StripSendButton(
      {super.key,
      required this.enabled,
      this.sending = false,
      this.stop = false,
      this.onTap});

  final bool enabled;
  final bool sending;
  final bool stop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = !enabled
        ? AppColors.hover
        : stop
            ? AppColors.surface3
            : AppColors.accentFill;
    final ink = !enabled
        ? AppColors.fg4
        : stop
            ? AppColors.fg1
            : AppColors.accentFg;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return Material(
      color: fill,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: sending
                ? Spinner(size: 13, color: ink)
                : AppIcon(stop ? 'stop' : 'arrow-up',
                    size: stop ? 13 : 15, color: ink),
          ),
        ),
      ),
    );
  }
}

class StripIcon extends StatelessWidget {
  const StripIcon(this.icon,
      {super.key, required this.tooltip, required this.onTap, this.color});

  final String icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 26,
              child: Center(
                  child: AppIcon(icon, size: 16, color: color ?? AppColors.fg3)),
            ),
          ),
        ),
      );
}
