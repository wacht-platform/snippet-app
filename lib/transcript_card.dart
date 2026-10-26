import 'package:flutter/material.dart';

import 'components.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show AppIcon;

class TranscriptCard extends StatefulWidget {
  const TranscriptCard({
    super.key,
    required this.kind,
    this.icon,
    this.leading,
    this.status,
    this.tone = Tone.neutral,
    this.title,
    this.body,
    this.child,
    this.footer,
    this.onTap,
    this.maxLines = 3,
  });

  final String kind;
  final String? icon;
  final Widget? leading;
  final String? status;
  final Tone tone;
  final String? title;
  final String? body;
  final Widget? child;
  final Widget? footer;
  final VoidCallback? onTap;
  final int maxLines;

  static double get titleSize => kMobile ? 15 : 14;
  static double get bodySize => kMobile ? 14.5 : 13.5;
  static TextStyle get bodyStyle =>
      sans(bodySize, height: 1.45, color: AppColors.fg2);

  @override
  State<TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<TranscriptCard> {
  bool _open = false;

  Widget _body(String text) => LayoutBuilder(builder: (context, c) {
        final style = TranscriptCard.bodyStyle;
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final long = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: style,
                maxLines: _open ? null : widget.maxLines,
                overflow: _open ? null : TextOverflow.ellipsis),
            if (long)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.only(top: S.s4),
                  child: Text(_open ? 'Show less' : 'Show more',
                      style: sans(kMobile ? 13 : 12.5,
                          weight: W.label, color: AppColors.fg3)),
                ),
              ),
          ],
        );
      });

  @override
  Widget build(BuildContext context) {
    final (fg, _) = toneColors(widget.tone);
    final title = widget.title?.trim() ?? '';
    final body = widget.body?.trim() ?? '';
    final pad = kMobile
        ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
        : const EdgeInsets.fromLTRB(14, 10, 14, 11);
    final content = Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: S.s8),
            ] else if (widget.icon != null) ...[
              AppIcon(widget.icon!,
                  size: 14,
                  color: widget.tone == Tone.neutral ? AppColors.fg3 : fg),
              const SizedBox(width: S.s8),
            ],
            Expanded(
              child: Text(widget.kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 13 : 12.5, color: AppColors.fg3)),
            ),
            if (widget.status != null && widget.status!.isNotEmpty) ...[
              const SizedBox(width: S.s8),
              Tag(widget.status!, tone: widget.tone),
            ],
          ]),
          if (title.isNotEmpty) ...[
            const SizedBox(height: S.s4),
            Text(title,
                style: sans(TranscriptCard.titleSize,
                    weight: W.label, height: 1.35, color: AppColors.fg1)),
          ],
          if (body.isNotEmpty) ...[
            SizedBox(height: title.isEmpty ? S.s6 : S.s2),
            _body(body),
          ],
          if (widget.child != null) ...[
            const SizedBox(height: S.s6),
            widget.child!,
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: S.s8),
            widget.footer!,
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.lg - 2),
        clipBehavior: Clip.antiAlias,
        child: widget.onTap == null
            ? content
            : InkWell(onTap: widget.onTap, child: content),
      ),
    );
  }
}
