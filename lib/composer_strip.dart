import 'package:flutter/material.dart';

import 'platform.dart';
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
        contentPadding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TS.body(AppColors.fg4),
      );

  @override
  Widget build(BuildContext context) => Container(
        key: cardKey,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: AppColors.accent, width: 1.5)
              : Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
                color: AppColors.bg.withValues(alpha: 0.9),
                blurRadius: 40,
                offset: const Offset(0, -18)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            Row(children: [
              ...footer,
              if (!footer.any((w) => w is Spacer)) const Spacer(),
              for (final w in inline)
                Padding(padding: const EdgeInsets.only(right: 6), child: w),
              send,
            ]),
          ],
        ),
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
            ? (kMobile ? AppColors.fg1 : AppColors.surface3)
            : (kMobile ? AppColors.accentFill : AppColors.fg1);
    final ink = !enabled
        ? AppColors.fg4
        : stop
            ? (kMobile ? AppColors.bg : AppColors.fg1)
            : (kMobile ? AppColors.accentFg : AppColors.bg);
    const ShapeBorder shape = CircleBorder();
    return Material(
      color: fill,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMobile ? 34 : 30,
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

class DesktopRecorderStrip extends StatelessWidget {
  const DesktopRecorderStrip({
    super.key,
    required this.recording,
    required this.time,
    required this.wave,
    required this.playing,
    required this.onDiscard,
    required this.onPlay,
    required this.onStop,
    required this.onSend,
    this.onSeek,
  });

  final bool recording;
  final String time;
  final Widget wave;
  final bool playing;
  final VoidCallback onDiscard;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onSend;
  final ValueChanged<double>? onSeek;

  Widget _btn(String icon, String tip, VoidCallback onTap,
          {Color? color, Color? fill}) =>
      Tooltip(
        message: tip,
        child: Material(
          color: fill ?? Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMobile ? 40 : 32,
              child: Center(
                  child: AppIcon(icon,
                      size: kMobile ? 17 : 15, color: color ?? AppColors.fg2)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final timeText = Text(time,
        style: mono(12, color: recording ? AppColors.danger : AppColors.fg3));
    final bar = SizedBox(height: 24, child: wave);
    Widget track = bar;
    if (!recording && onSeek != null) {
      track = LayoutBuilder(
        builder: (_, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) =>
              onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          child: Center(child: bar),
        ),
      );
    }
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: kMobile ? AppColors.surface1 : AppColors.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        if (recording) ...[
          const SizedBox(width: 10),
          StatusDot(status: 'running', size: 8, color: AppColors.danger),
          const SizedBox(width: 8),
          timeText,
          const SizedBox(width: 10),
          Expanded(child: track),
          const SizedBox(width: 4),
          _btn('trash', 'Discard', onDiscard, color: AppColors.fg3),
          _btn('stop', 'Stop', onStop,
              color: kMobile ? AppColors.bg : AppColors.fg1,
              fill: kMobile ? AppColors.fg1 : AppColors.surface3),
        ] else ...[
          _btn(playing ? 'pause' : 'play', playing ? 'Pause' : 'Play', onPlay,
              color: AppColors.fg1),
          Expanded(child: track),
          const SizedBox(width: 8),
          timeText,
          const SizedBox(width: 4),
          _btn('trash', 'Discard', onDiscard, color: AppColors.fg3),
          _btn('arrow-up', 'Send voice note', onSend,
              color: kMobile ? AppColors.accentFg : AppColors.bg,
              fill: kMobile ? AppColors.accentFill : AppColors.fg1),
        ],
      ]),
    );
  }
}
