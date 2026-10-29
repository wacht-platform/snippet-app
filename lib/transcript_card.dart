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
    this.maxLines = 2,
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

  static double get titleSize => kMobile ? 14 : 13;
  static double get bodySize => kMobile ? 13.5 : 12.5;
  static double get metaSize => kMobile ? 12 : 11.5;
  static TextStyle get bodyStyle =>
      sans(bodySize, height: 1.4, color: AppColors.fg2);

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
                  padding: const EdgeInsets.only(top: S.s2),
                  child: Text(_open ? 'Show less' : 'Show more',
                      style: sans(TranscriptCard.metaSize,
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
        ? const EdgeInsets.fromLTRB(12, 9, 12, 10)
        : const EdgeInsets.fromLTRB(12, 7, 12, 8);
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
                  size: 12,
                  color: widget.tone == Tone.neutral ? AppColors.fg3 : fg),
              const SizedBox(width: S.s6),
            ],
            Expanded(
              child: Text(widget.kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(TranscriptCard.metaSize, color: AppColors.fg3)),
            ),
            if (widget.status != null && widget.status!.isNotEmpty) ...[
              const SizedBox(width: S.s8),
              CardStatus(widget.status!, tone: widget.tone),
            ],
          ]),
          if (title.isNotEmpty) ...[
            const SizedBox(height: S.s2),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(TranscriptCard.titleSize,
                    weight: W.label, height: 1.3, color: AppColors.fg1)),
          ],
          if (body.isNotEmpty) ...[
            SizedBox(height: title.isEmpty ? S.s4 : S.s2),
            _body(body),
          ],
          if (widget.child != null) ...[
            SizedBox(height: title.isEmpty ? S.s4 : S.s2),
            widget.child!,
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: S.s4),
            widget.footer!,
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: widget.onTap == null
            ? content
            : InkWell(onTap: widget.onTap, child: content),
      ),
    );
  }
}

class CardStatus extends StatelessWidget {
  const CardStatus(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final fg = tone == Tone.neutral ? AppColors.fg3 : toneColors(tone).$1;
    return Text(label,
        maxLines: 1,
        style: sans(TranscriptCard.metaSize, weight: W.label, color: fg));
  }
}
