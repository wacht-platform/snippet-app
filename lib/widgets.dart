import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'platform.dart';
import 'api.dart';
import 'media_views.dart';
import 'theme.dart';
import 'components.dart';
import 'dialog_widgets.dart';
import 'markdown_widgets.dart';
import 'menu_widgets.dart';

export 'components.dart';
export 'dialog_widgets.dart';
export 'markdown_widgets.dart';
export 'menu_widgets.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label = 'Loading'});
  final String label;

  @override
  Widget build(BuildContext context) => PageLoader(label: label);
}

/// [onSelect] null disables the whole row (e.g. a locked field).
class Pills<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T>? onSelect;
  const Pills(
      {super.key, required this.items, required this.selected, this.onSelect});
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final (val, label) in items)
          Pressable(
            enabled: onSelect != null,
            child: GestureDetector(
              onTap: onSelect == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onSelect!(val);
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  // Selection is a NEUTRAL surface step, not the accent. The
                  // accent is reserved for STATE (running, needs-attention), so
                  // an accent-filled chip reads as an alert rather than "this is
                  // on" — and it collides with the same hue already meaning
                  // status elsewhere. Matches IconBtn.active and the nav rows.
                  color:
                      selected == val ? AppColors.surface3 : AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(
                      color: selected == val
                          ? AppColors.border2
                          : AppColors.border),
                ),
                child: Text(label,
                    style: sans(12,
                        weight: W.label,
                        color:
                            selected == val ? AppColors.fg1 : AppColors.fg2)),
              ),
            ),
          ),
      ]);
}

void openMarkdownLink(String? href) {
  if (href == null || href.isEmpty) return;
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Themed markdown stylesheet for agent messages.
/// Cached per-process to avoid rebuilding the full stylesheet on every Bubble
/// rebuild — the stylesheet is pure allocation and identical across the session
/// lifetime when the theme doesn't change.
MarkdownStyleSheet? _cachedMarkdownStyle;
int? _cachedMarkdownThemeIndex;

MarkdownStyleSheet markdownStyle(BuildContext context) {
  final themeIndex = ThemeManager.instance.index;
  if (_cachedMarkdownStyle != null && _cachedMarkdownThemeIndex == themeIndex) {
    return _cachedMarkdownStyle!;
  }
  _cachedMarkdownThemeIndex = themeIndex;
  _cachedMarkdownStyle =
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: TS.body(),
    pPadding: EdgeInsets.zero,
    strong: TS.body(AppColors.fg1).copyWith(fontWeight: W.strong),
    em: TS.body().copyWith(fontStyle: FontStyle.italic),
    a: TS.body(AppColors.accent),
    h1: TS.sectionTitle(),
    h1Padding: const EdgeInsets.only(top: S.s12, bottom: S.s4),
    h2: TS.rowTitle().copyWith(fontWeight: W.strong),
    h2Padding: const EdgeInsets.only(top: S.s12, bottom: S.s4),
    h3: TS.rowTitle(),
    h3Padding: const EdgeInsets.only(top: S.s8, bottom: S.s2),
    listIndent: 20,
    listBulletPadding: const EdgeInsets.only(right: S.s6),
    code: TS.code(AppColors.fg1).copyWith(
        fontSize: kMobile ? 14 : 13, backgroundColor: AppColors.hover),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    blockquote: TS.body(AppColors.fg3),
    blockquotePadding: const EdgeInsets.fromLTRB(S.s12, S.s2, 0, S.s2),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.lineStrong, width: 2)),
    ),
    listBullet: TS.body(AppColors.fg3),
    tableBody: TS.ui(),
    tableHead: TS.ui(AppColors.fg1).copyWith(fontWeight: W.label),
    // FlexColumnWidth stretches every markdown table to the full message width.
    // Intrinsic columns keep phone tables content-sized; the markdown package
    // supplies horizontal scrolling when a long URL or code value needs it.
    tableColumnWidth:
        kMobile ? const IntrinsicColumnWidth() : const FlexColumnWidth(),
    horizontalRuleDecoration:
        BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
  );
  return _cachedMarkdownStyle!;
}

/// Dimmed markdown for live model thinking/reasoning — same structure as
/// [markdownStyle], quieter palette so it reads as an aside, not the answer.
MarkdownStyleSheet? _cachedThinkingMarkdownStyle;
int? _cachedThinkingMarkdownThemeIndex;

MarkdownStyleSheet thinkingMarkdownStyle(BuildContext context) {
  final themeIndex = ThemeManager.instance.index;
  if (_cachedThinkingMarkdownStyle != null &&
      _cachedThinkingMarkdownThemeIndex == themeIndex) {
    return _cachedThinkingMarkdownStyle!;
  }
  _cachedThinkingMarkdownThemeIndex = themeIndex;
  final dim = AppColors.fg3;
  final dim2 = AppColors.fg4;
  _cachedThinkingMarkdownStyle =
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: sans(13, height: 1.45, color: dim),
    pPadding: EdgeInsets.zero,
    em: sans(13, height: 1.45, color: dim)
        .copyWith(fontStyle: FontStyle.italic),
    strong: sans(13, height: 1.45, color: dim, weight: W.label),
    a: sans(13, height: 1.45, color: AppColors.accent),
    h1: sans(16, weight: W.label, height: 1.3, color: dim),
    h1Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h2: sans(14, weight: W.label, height: 1.3, color: dim),
    h2Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h3: sans(14, weight: W.label, height: 1.3, color: dim),
    h3Padding: const EdgeInsets.only(top: 2, bottom: 1),
    code: mono(12, color: dim2),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    blockquote: sans(13, height: 1.45, color: dim2),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.xs),
      border: Border(left: BorderSide(color: AppColors.border, width: 2)),
    ),
    listBullet: sans(13, height: 1.45, color: dim),
    tableBody: sans(12, color: dim),
    tableColumnWidth:
        kMobile ? const IntrinsicColumnWidth() : const FlexColumnWidth(),
    horizontalRuleDecoration:
        BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
  );
  return _cachedThinkingMarkdownStyle!;
}

/// Live thinking/reasoning stream — full markdown, dimmed.

/// HugeIcons sit inside an explicit square and are optically scaled below its
/// layout bound. This prevents round/full-canvas SVGs from reading larger than
/// adjacent text or controls.
class AppIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  /// Extra correction on top of the per-glyph table.
  ///
  /// Rarely needed — [glyphInkScale] already normalises the glyphs whose ink
  /// differs from the norm — so this is a one-off escape hatch.
  final double visualScale;
  const AppIcon(this.name,
      {super.key, this.size = 18, this.color, this.visualScale = 1.0});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: name == 'check'
            ? CustomPaint(
                painter: _CheckPainter(
                    color ?? AppColors.fg2, size * visualScale / 9),
              )
            : Center(
                child: HugeIcon(
                  icon: hugeIconFor(name),
                  // Layout keeps the nominal `size`; only the INK is normalised, so a
                  // corrected glyph still occupies the same box as its neighbours.
                  size: size * visualScale * glyphInkScale(name),
                  color: color ?? AppColors.fg2,
                ),
              ),
      );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color, this.stroke);

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke < 1.4 ? 1.4 : stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.2, size.height * 0.53)
        ..lineTo(size.width * 0.42, size.height * 0.74)
        ..lineTo(size.width * 0.8, size.height * 0.3),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.color != color || old.stroke != stroke;
}

/// Glowing status dot.
class StatusDot extends StatefulWidget {
  final String status; // online | running | offline | checking
  final double size;
  final Color? color;
  const StatusDot(
      {super.key, this.status = 'online', this.size = 9, this.color});
  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  /// Assigned in initState, NOT as a lazy `late final` initialiser.
  ///
  /// A lazy initialiser is evaluated on FIRST ACCESS, and for a static status
  /// ('online'/'offline') `build` never reads it — so `dispose` became the first
  /// access and constructed an AnimationController on an element that was
  /// already unmounting, throwing "the widget's element tree is no longer
  /// stable". Creating it eagerly removes the ordering dependency entirely.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
  }

  /// Reduced motion stops the breath but keeps the lit dot: the state is still
  /// readable from colour alone, so nothing is lost by holding it steady.
  bool get _pulses => widget.status == 'checking' || widget.status == 'running';

  void _sync() {
    if (!_pulses || reduceMotion(context)) {
      if (_c.isAnimating) _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _color =>
      widget.color ??
      switch (widget.status) {
        'online' => AppColors.ok,
        'running' => AppColors.run,
        'offline' => AppColors.danger,
        _ => AppColors.fg3,
      };

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final c = _color;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: widget.status == 'offline'
            ? null
            : [
                BoxShadow(
                    color: c.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1)
              ],
      ),
    );
    if (_pulses) {
      return FadeTransition(
          opacity: Tween(begin: 0.45, end: 1.0).animate(_c), child: dot);
    }
    return dot;
  }
}

/// Rounded status pill with a leading dot.
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill({super.key, required this.status});
  @override
  Widget build(BuildContext context) => switch (status) {
        'running' => const Tag('Running', tone: Tone.run, live: true),
        'online' => const Tag('Online', tone: Tone.ok, dot: true),
        'offline' => const Tag('Offline', tone: Tone.danger, dot: true),
        'error' => const Tag('Error', tone: Tone.danger, dot: true),
        'checking' => const Tag('Checking', dot: true),
        _ => const Tag('Idle', dot: true),
      };
}

/// Surface-1 card with a hairline border.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const AppCard(
      {super.key,
      required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Pressable(
      enabled: onTap != null,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.card),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

enum BtnVariant {
  primary,
  secondary,

  /// A surface STEP, no border.
  ///
  /// The design language has no borders and reserves the accent hue for state,
  /// so neither [primary] (accent fill) nor [secondary] (hairline) is right for
  /// a plain action. This is the doc's chip/active ladder doing the work.
  surface,
  outline,
  ghost,
  danger,
}

class Btn extends StatelessWidget {
  final String label;
  final BtnVariant variant;
  final bool small;
  final bool full;
  final bool disabled;
  final String? icon;
  final String? iconRight;
  final VoidCallback? onTap;
  const Btn(this.label,
      {super.key,
      this.variant = BtnVariant.primary,
      this.small = false,
      this.full = false,
      this.disabled = false,
      this.icon,
      this.iconRight,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final (Color bg, Color fg, Color? bd) = switch (variant) {
      BtnVariant.primary => (AppColors.accentFill, AppColors.accentFg, null),
      BtnVariant.secondary => (
          AppColors.surface2,
          AppColors.fg1,
          AppColors.border
        ),
      // Ladder, not a line: the fill is the separation.
      BtnVariant.surface => (AppColors.surface3, AppColors.fg2, null),
      BtnVariant.outline => (
          Colors.transparent,
          AppColors.fg1,
          AppColors.border
        ),
      BtnVariant.ghost => (Colors.transparent, AppColors.fg2, null),
      BtnVariant.danger => (
          AppColors.dangerBg,
          AppColors.danger,
          AppColors.danger.withValues(alpha: 0.3)
        ),
    };
    // Compact on desktop (mouse), roomy touch targets on mobile.
    // 44 on mobile for BOTH variants. `small` was 34 — under Apple's 44pt and
    // Material's 48dp floors — and it is the primary action of the agent thread
    // composer and every dialog footer. Desktop keeps the compact 28/34 so a
    // mouse-sized toolbar does not grow.
    final h = small ? (kMobile ? 36.0 : 28.0) : (kMobile ? 44.0 : 34.0);
    final child = Row(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: small ? 15 : 17, color: fg),
          const SizedBox(width: 8)
        ],
        Text(label, style: sans(small ? 12 : 13, weight: W.label, color: fg)),
        if (iconRight != null) ...[
          const SizedBox(width: 8),
          AppIcon(iconRight!, size: small ? 15 : 17, color: fg)
        ],
      ],
    );
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Pressable(
        enabled: !disabled && onTap != null,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: disabled || onTap == null
                ? null
                : () {
                    if (variant == BtnVariant.primary) {
                      HapticFeedback.lightImpact();
                    }
                    onTap!();
                  },
            borderRadius: BorderRadius.circular(R.sm),
            child: Container(
              height: h,
              width: full ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.sm),
                border: bd != null ? Border.all(color: bd) : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent pill action (Claude-style primary affordance).
class PillBtn extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  const PillBtn(this.label, {super.key, this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        enabled: onTap != null,
        child: Material(
          color: AppColors.accentFill,
          borderRadius: BorderRadius.circular(R.pill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.pill),
            child: Container(
              height: kMobile ? 48 : 36,
              padding: EdgeInsets.symmetric(horizontal: kMobile ? 20 : 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  AppIcon(icon!,
                      size: kMobile ? 18 : 16, color: AppColors.accentFg),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: sans(kMobile ? 14 : 13,
                        weight: W.label, color: AppColors.accentFg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile press feedback: a small scale-down while the finger or button is
/// held down.
///
/// An ink ripple confirms the RELEASE, so the control only answers once the
/// touch is over. This answers on the way down, which is what makes a button
/// feel like it is listening. It wraps a Material without disturbing the ink or
/// the tap: a `Listener` observes the pointer but never joins the gesture arena.
class Pressable extends StatefulWidget {
  final Widget child;

  /// Off for inert controls, and for a surface where motion would distract.
  final bool enabled;

  /// Subtle by design — 0.96 reads as tactile, below 0.95 reads as exaggerated.
  final double scale;

  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (!widget.enabled || _down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion keeps the press feedback but drops the travel: the state
    // still changes, it just does not move across the screen.
    final reduced = reduceMotion(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1.0,
        duration: reduced ? Duration.zero : Motion.press,
        curve: Motion.enter,
        child: widget.child,
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool active;
  final String? tooltip;
  const IconBtn(this.name,
      {super.key,
      this.onTap,
      this.size = 38,
      this.iconSize = 19,
      this.active = false,
      this.tooltip});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // A touch target may not be smaller than a fingertip just because the ink
    // is small: on a phone the layout box grows to [M.minTarget] while the glyph
    // keeps its size, so a 22px clear button is still comfortably tappable. On
    // desktop the pointer is precise, so `size` is taken at its word.
    final box =
        kMobile && onTap != null && size < M.minTarget ? M.minTarget : size;
    final btn = Pressable(
      enabled: onTap != null,
      child: Material(
        // Selection is surface-only, matching the sidebar/rail selection
        // language. The accent is reserved for state, not for "this is on".
        color: active ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: SizedBox(
            width: box,
            height: box,
            child: Center(
              child: AppIcon(name,
                  size: iconSize,
                  color: active ? AppColors.fg1 : AppColors.fg2),
            ),
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// Dashed add / empty card.
class AddCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const AddCard({super.key, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Pressable(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.card),
        child: CustomPaint(
          painter: _DashedBorder(color: AppColors.border2, radius: R.card),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const AppIcon('plus', size: 15),
              const SizedBox(width: 8),
              Text(label,
                  style: sans(12, weight: W.label, color: AppColors.fg2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorder({required this.color, required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    const dash = 5.0, gap = 4.0;
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}

/// Internal attachment and transcription markers are agent-facing metadata, not
/// user-facing chat text.
final RegExp _attachMarkerRe =
    RegExp(r'\[attached (image|file) —([^\]]*)\]', multiLine: true);
final RegExp _audioTranscriptHeaderRe = RegExp(
  r'\[Audio transcript for ([^\]\r\n]+)\]\r?\n',
  multiLine: true,
);
final RegExp _audioUnavailableRe = RegExp(
  r'\[Audio transcription unavailable: ([^\]\r\n]*)\]',
  multiLine: true,
);

class AudioTranscriptItem {
  final String text;
  final bool unavailable;
  const AudioTranscriptItem(this.text, {this.unavailable = false});
}

/// Extract the daemon's audio transcript block(s) without exposing its internal
/// attachment path. A message may contain more than one audio attachment.
List<AudioTranscriptItem> audioTranscriptItems(String raw) {
  final headers = _audioTranscriptHeaderRe.allMatches(raw).toList();
  final items = <AudioTranscriptItem>[];
  for (var i = 0; i < headers.length; i++) {
    final start = headers[i].end;
    final end = i + 1 < headers.length ? headers[i + 1].start : raw.length;
    final text = raw.substring(start, end).trim();
    if (text.isNotEmpty) items.add(AudioTranscriptItem(text));
  }
  for (final match in _audioUnavailableRe.allMatches(raw)) {
    final error = match.group(1)?.trim() ?? 'unknown error';
    items.add(AudioTranscriptItem(error, unavailable: true));
  }
  return items;
}

String? audioTranscriptionError(String raw) {
  final match = _audioUnavailableRe.firstMatch(raw);
  return match?.group(1)?.trim();
}

bool isAudioAttachmentPath(String value) {
  final path = value.trim().toLowerCase();
  return const [
    '.aac',
    '.flac',
    '.m4a',
    '.mp3',
    '.oga',
    '.ogg',
    '.opus',
    '.wav',
    '.webm',
  ].any(path.endsWith);
}

/// Remove internal attachment/transcription metadata from the message body while
/// leaving the audio transcript available to the dedicated transcript card.
String hideAttachmentMarkers(String raw) {
  var shown = splitPastedBlocks(raw).$2;
  final headers = _audioTranscriptHeaderRe.allMatches(shown).toList();
  for (var i = headers.length - 1; i >= 0; i--) {
    final start = headers[i].start;
    final end = i + 1 < headers.length ? headers[i + 1].start : shown.length;
    shown = shown.replaceRange(start, end, '');
  }
  return shown
      .replaceAll(_audioUnavailableRe, '')
      .replaceAll(_attachMarkerRe, '')
      .trim();
}

/// Read-only attachment summary on a sent message — icon + count, no emoji.
/// Images and files each get their own compact pill (matches desktop).
class AttachmentPill extends StatelessWidget {
  final int audio, images, files;
  const AttachmentPill({
    super.key,
    required this.audio,
    required this.images,
    required this.files,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    Widget pill(String icon, String label, {bool isAudio = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isAudio ? AppColors.accentBg : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: isAudio ? AppColors.accentLine : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon,
                size: 11, color: isAudio ? AppColors.accent : AppColors.fg3),
            const SizedBox(width: 4),
            Text(label,
                style: sans(11,
                    color: isAudio ? AppColors.accent : AppColors.fg2)),
          ]),
        );
    final pills = <Widget>[];
    if (audio > 0) {
      pills.add(
          pill('mic', audio == 1 ? 'audio' : '$audio audio', isAudio: true));
    }
    if (images > 0) {
      pills.add(pill('image', images == 1 ? 'image' : '$images images'));
    }
    if (files > 0) {
      pills.add(pill('file', files == 1 ? 'file' : '$files files'));
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 6, children: pills);
  }
}

/// A compact, readable transcript attached to the audio pill. It is collapsed by
/// default so the conversation stays compact, but can be expanded without hiding
/// the original audio attachment.
class AudioTranscriptCard extends StatefulWidget {
  final List<AudioTranscriptItem> items;
  const AudioTranscriptCard({super.key, required this.items});

  @override
  State<AudioTranscriptCard> createState() => _AudioTranscriptCardState();
}

class _AudioTranscriptCardState extends State<AudioTranscriptCard> {
  bool _expanded = false;

  String _lineFor(AudioTranscriptItem item) => item.unavailable
      ? 'Could not transcribe this audio: ${item.text}'
      : item.text;

  String get _preview {
    final first = widget.items.isEmpty ? '' : _lineFor(widget.items.first);
    return first.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool get _canExpand {
    if (widget.items.length > 1) return true;
    if (widget.items.isEmpty) return false;
    return _lineFor(widget.items.first).contains('\n') || _preview.length > 72;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: _canExpand ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_expanded)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    _preview.isEmpty ? 'Transcript' : _preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, height: 1.4, color: AppColors.fg2),
                  ),
                ),
                if (_canExpand) ...[
                  const SizedBox(width: 8),
                  AppIcon('chevron-down', size: 13, color: AppColors.fg4),
                ],
              ])
            else ...[
              for (var i = 0; i < widget.items.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                Text(
                  _lineFor(widget.items[i]),
                  style: sans(12,
                      height: 1.4,
                      color: widget.items[i].unavailable
                          ? AppColors.fg3
                          : AppColors.fg2),
                ),
              ],
              const SizedBox(height: 4),
              Row(children: [
                const Spacer(),
                AppIcon('chevron-up', size: 13, color: AppColors.fg4),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// One chat message — flat (no bubble/box). YOUR messages get a left accent bar
/// + label; the agent's are plain full-width markdown under a dim label. The bar
/// vs no-bar is the primary you/agent distinction.
/// A reply's long-press sheet on phones: copy it whole, or open it to select.
void _messageActions(BuildContext context, String text) {
  showAppSheet(context,
      title: 'Message',
      child: SheetActions([
        SheetAction('clipboard', 'Copy message', () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: text));
          toast(context, 'Copied');
        }),
        SheetAction('edit', 'Select text', () {
          Navigator.pop(context);
          showAppSheet(context,
              title: 'Select text',
              maxHeight: 640,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.s4),
                child: SelectionArea(
                  child: MarkdownBody(
                    data: text,
                    styleSheet: markdownStyle(context),
                    builders: {'pre': PreBlockBuilder()},
                  ),
                ),
              ));
        }),
      ]));
}

class Bubble extends StatelessWidget {
  final bool mine;
  final String text;

  /// Live bubbles are intentionally not selectable while their text is changing.
  /// Set this to false for streaming/optimistic content; durable transcript
  /// bubbles use the default per-message selection container.
  final bool selectable;

  /// When given, a sent message's attachments render as real media (image
  /// thumbnails, file cards, playable voice notes) instead of count pills.
  final DaemonClient? client;
  const Bubble({
    super.key,
    required this.mine,
    required this.text,
    this.selectable = true,
    this.client,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final (pasted, body) = splitPastedBlocks(text);
    final matches = _attachMarkerRe.allMatches(body).toList();
    final transcripts = audioTranscriptItems(body);
    final shown = hideAttachmentMarkers(body);
    final pastedCards = [
      for (final block in pasted)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: PastedTextCard(text: block),
        ),
    ];
    final audio =
        matches.where((m) => isAudioAttachmentPath(m.group(2) ?? '')).length;
    final images = matches.where((m) => m.group(1) == 'image').length;
    final files = matches.length - images - audio;
    final textBody = shown.isNotEmpty
        ? MarkdownBody(
            data: shown,
            selectable: false,
            styleSheet: markdownStyle(context),
            builders: {'pre': PreBlockBuilder()},
            onTapLink: (txt, href, title) => openMarkdownLink(href),
          )
        : null;
    final voice = <Widget>[
      if (audio > 0) AttachmentPill(audio: audio, images: 0, files: 0),
      if (transcripts.isNotEmpty) AudioTranscriptCard(items: transcripts),
      if (audio > 0 && transcripts.isEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('activity', size: 12, color: AppColors.fg3),
          const SizedBox(width: 6),
          Text('Transcribing audio…', style: TS.meta()),
        ]),
    ];
    final extras = <Widget>[
      if (images > 0 || files > 0)
        AttachmentPill(audio: 0, images: images, files: files),
    ];
    final media =
        client == null ? null : _sentMedia(context, client!, transcripts);
    final mineText = textBody == null
        ? const SizedBox.shrink()
        : (selectable ? SelectionArea(child: textBody) : textBody);
    final agentContent = MarkdownBody(
      data: shown,
      selectable: false,
      styleSheet: markdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href),
    );

    final agent =
        selectable ? SelectionArea(child: agentContent) : agentContent;

    if (!mine && kMobile && selectable) {
      // Phones: no Copy row under every reply. Long-press offers copying the
      // whole message or selecting within it (a long-press can't do both).
      return Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: shown.isEmpty
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  _messageActions(context, shown);
                },
          child: agentContent,
        ),
      );
    }

    if (!mine) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              agent,
              if (selectable && shown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: shown));
                      toast(context, 'Copied');
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon('clipboard', size: 12, color: AppColors.fg4),
                        const SizedBox(width: 5),
                        Text('Copy', style: TS.meta()),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (media != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...media,
            if (shown.isNotEmpty)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: media.isEmpty ? 0 : 6),
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.card),
                ),
                child: mineText,
              ),
            ...pastedCards,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shown.isNotEmpty || voice.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shown.isNotEmpty) mineText,
                  if (shown.isNotEmpty && voice.isNotEmpty)
                    const SizedBox(height: 8),
                  for (var i = 0; i < voice.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    voice[i],
                  ],
                ],
              ),
            ),
          for (final extra in extras) ...[
            const SizedBox(height: 4),
            extra,
          ],
          ...pastedCards,
        ],
      ),
    );
  }
}

extension on Bubble {
  /// The attachments of a sent message as media, in the order images, files,
  /// voice notes; empty when the message has none.
  List<Widget> _sentMedia(BuildContext context, DaemonClient client,
      List<AudioTranscriptItem> transcripts) {
    final attachments = parseSentAttachments(text);
    if (attachments.isEmpty) return const [];
    final images = [
      for (final a in attachments)
        if (a.kind == MediaKind.image) a.path
    ];
    final audio = [
      for (final a in attachments)
        if (a.kind == MediaKind.audio) a.path
    ];
    final files = [
      for (final a in attachments)
        if (a.kind != MediaKind.image && a.kind != MediaKind.audio) a.path
    ];
    final maxWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 280.0);
    Widget card(Widget child) => Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.card),
          ),
          child: child,
        );
    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 6));
      out.add(w);
    }

    if (images.isNotEmpty) {
      add(ImageGallery(client: client, paths: images, maxWidth: maxWidth));
    }
    if (files.isNotEmpty) {
      add(SizedBox(
        width: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              FileChip(client: client, path: files[i]),
            ],
          ],
        ),
      ));
    }
    for (var i = 0; i < audio.length; i++) {
      final transcript = i < transcripts.length
          ? AudioTranscriptCard(items: [transcripts[i]])
          : (transcripts.isEmpty
              ? Text('Transcribing…', style: TS.meta())
              : null);
      add(card(
          VoiceNote(client: client, path: audio[i], transcript: transcript)));
    }
    return out;
  }
}

/// Dim note (centered) / error (left-aligned, capped at two lines).
class NoteLine extends StatelessWidget {
  final String text;
  final bool error;

  /// What went wrong, as the card's header (errors only).
  final String? label;
  const NoteLine(this.text, {super.key, this.error = false, this.label});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (!error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(12, height: 1.4, color: AppColors.fg3)),
      );
    }
    // An error reads as the transcript's other cards: a mono header in the
    // danger tone, then the message itself, selectable so it can be copied.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AppIcon('alert-triangle', size: 12, color: AppColors.danger),
              const SizedBox(width: 6),
              Text(label ?? 'Error', style: mono(10, color: AppColors.danger)),
            ]),
            const SizedBox(height: 5),
            SelectableText(text,
                minLines: 1,
                maxLines: 6,
                style: sans(13, height: 1.45, color: AppColors.fg2)),
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool accent;
  const StatTile(
      {super.key,
      required this.label,
      required this.value,
      this.sub,
      this.accent = false});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TS.caption()),
            const SizedBox(height: 5),
            Text(value,
                style: mono(16,
                    weight: W.label,
                    color: accent ? AppColors.accent : AppColors.fg1)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, style: mono(10, color: AppColors.fg3))
            ],
          ]),
    );
  }
}

class Progress extends StatelessWidget {
  final double pct; // 0..100
  final Color? color;
  final double height;
  const Progress({super.key, required this.pct, this.color, this.height = 7});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0, 1),
        minHeight: height,
        backgroundColor: AppColors.surface2,
        valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
      ),
    );
  }
}

class WarnChip extends StatelessWidget {
  final String label;
  const WarnChip({super.key, this.label = 'No key'});
  @override
  Widget build(BuildContext context) =>
      Tag(label, tone: Tone.run, icon: 'alert-triangle');
}

/// A section label above a group of rows.
///
/// `fg2` at weight 500, matching BOTH other section-header treatments in the app
/// (`ShellSectionHeader` in the sidebar, `_StatusHeader` on the task board).
/// This rendered at `fg4` — the placeholder/disabled rung — which measured
/// 2.98:1 against the panel background, below the 4.5 AA floor, and read as
/// disabled chrome rather than a label. `shell_nav.dart` had already documented
/// and fixed exactly this mistake for its own header; this one was missed.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s2),
        child: Text(text, style: TS.label(AppColors.fg2)),
      );
}

class EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String? body;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.action});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // Fills the box it is handed and centers inside it. Call sites give this the
    // whole body of a pane or an `Expanded`, and a shrink-wrapping child there
    // aligns to the top-left instead of the middle — so the centering has to
    // live here rather than be repeated at every call site.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // Separation by surface step, not a hairline — the design
              // language's first rule. surface2 is the ladder's "quiet raised
              // content" step, which is what this tile is; the border was
              // standing in for a step that already existed.
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: AppIcon(icon, size: 24, color: AppColors.fg3),
          ),
          const SizedBox(height: 12),
          Text(title, style: TS.sectionTitle()),
          if (body != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(body!, textAlign: TextAlign.center, style: TS.meta()),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Custom app bar matching the handoff (back + title/mono-subtitle + right + ⋯).
/// A page header's primary action: a labelled button on desktop, an icon
/// button on phones, where a filled text button crowded the title.
class HeaderAction extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  const HeaderAction(this.label,
      {super.key, this.icon = 'plus', required this.onTap});

  @override
  Widget build(BuildContext context) => kMobile
      ? IconBtn(icon,
          size: M.minTarget, iconSize: 20, tooltip: label, onTap: onTap)
      : Btn(label, icon: icon, small: true, onTap: onTap);
}

class SnAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final double titleSize;
  final bool compact;

  /// Which surface the bar sits on. Defaults to the ambient scaffold colour,
  /// which is what the desktop panels re-theme.
  final Color? background;

  /// Draws the 1px bottom hairline.
  ///
  /// The design language uses NO borders — separation comes from the surface
  /// ladder — so a page that pairs a chrome bar with a canvas body passes
  /// `false` and lets the step do the work. Defaulted to true rather than
  /// flipped globally: the existing call sites share the scaffold's own colour,
  /// where the hairline is currently the only separation they have. Removing it
  /// for them is a follow-up, not something to fold into one page's fix.
  final bool bordered;
  const SnAppBar(
      {super.key,
      required this.title,
      this.subtitle,
      this.onBack,
      this.leading,
      this.actions = const [],
      this.titleSize = 17,
      this.compact = false,
      this.background,
      this.bordered = true});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Container(
      height: compact ? 52 : 64,
      padding: EdgeInsets.fromLTRB(
          onBack != null || leading != null ? S.s4 : S.s12, 0, S.s8, 0),
      decoration: BoxDecoration(
        // Follows the ambient shell surface — desktop panels re-theme this to
        // surface1 so the bar never reads as a darker strip (mobile: still bg).
        color: background ?? Theme.of(context).scaffoldBackgroundColor,
        border: bordered
            ? Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(children: [
        if (leading != null)
          leading!
        else if (onBack != null)
          IconBtn('chevron-left',
              size: kMobile ? M.minTarget : 36,
              iconSize: kMobile ? 22 : 20,
              tooltip: 'Back',
              onTap: onBack),
        if (leading != null || onBack != null) const SizedBox(width: S.s2),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(titleSize)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.codeSmall()),
              ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// Labeled input: focus → accent border + ring.

class AppSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;

  /// Whole-track size. The thumb and its inset derive from this, so the
  /// proportions hold at any size.
  final double width;
  final double height;
  final double thumb;

  const AppSwitch({
    super.key,
    required this.on,
    required this.onChanged,
    this.width = 44,
    this.height = 26,
    this.thumb = 20,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    const inset = 3.0;
    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        // The visible track is small; this keeps the tappable area comfortable
        // without scaling the drawing.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          height: height + 12,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.enter,
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: on ? AppColors.accentFill : AppColors.surface3,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: AnimatedAlign(
                duration: Motion.fast,
                curve: Motion.enter,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: inset),
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? sub;
  const AppToggle(
      {super.key,
      required this.on,
      required this.onChanged,
      required this.label,
      this.sub});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Pressable(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TS.label(AppColors.fg1)),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Text(sub!, style: TS.caption())
                    ],
                  ]),
            ),
            const SizedBox(width: 12),
            AppSwitch(on: on, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}
