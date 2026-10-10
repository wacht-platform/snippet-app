import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Fades and lifts its child into place once, when it first mounts.
///
/// Rows of a list pass the time their list first painted as [since]: a row
/// that mounts well after that (scrolled into view, recycled) shows at rest
/// instead of animating again. [index] staggers the first screenful.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.child,
    this.index = 0,
    this.since,
    this.offset = 8,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final DateTime? since;
  final double offset;
  final bool enabled;

  static const _window = Duration(milliseconds: 700);
  static const _step = Duration(milliseconds: 28);
  static const _maxStagger = 10;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    final since = widget.since;
    final fresh =
        since == null || DateTime.now().difference(since) < Appear._window;
    if (!widget.enabled || !fresh) return;
    final c = AnimationController(vsync: this, duration: Motion.base);
    _c = c;
    final delay = Appear._step * widget.index.clamp(0, Appear._maxStagger);
    if (delay == Duration.zero) {
      c.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final curve = CurvedAnimation(parent: c, curve: Motion.enter);
    final faded = FadeTransition(opacity: curve, child: widget.child);
    if (reduceMotion(context)) return faded;
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, widget.offset * (1 - curve.value)),
        child: child,
      ),
      child: faded,
    );
  }
}

/// Cross-fades between states of one area (loading, empty, content, or a
/// changed value). Give each state a distinct [stateKey].
class Swap extends StatelessWidget {
  const Swap({
    super.key,
    required this.stateKey,
    required this.child,
    this.duration = Motion.fast,
    this.alignment = Alignment.topCenter,
    this.fill = false,
  });

  final Object stateKey;
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  /// Stretch each state to the area's full size, for panels and pages.
  final bool fill;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        reverseDuration: Motion.quick,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: alignment,
          fit: fill ? StackFit.expand : StackFit.loose,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(key: ValueKey(stateKey), child: child),
      );
}

/// Short text that cross-fades when its value changes: counts, status lines.
class SwapText extends StatelessWidget {
  const SwapText(this.text,
      {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.fast,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, if (current != null) current],
        ),
        child: Text(text,
            key: ValueKey(text),
            style: style,
            maxLines: maxLines,
            overflow: overflow),
      );
}

/// Three dots that rise and brighten in a wave: the "still working" mark.
class WorkingDots extends StatefulWidget {
  const WorkingDots({super.key, this.color, this.size = 5});

  final Color? color;
  final double size;

  @override
  State<WorkingDots> createState() => _WorkingDotsState();
}

class _WorkingDotsState extends State<WorkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
      _c.value = 0.25;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accent;
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: s * 0.7),
            () {
              final phase = (_c.value - i * 0.16) % 1.0;
              final wave = phase < 0.5
                  ? Curves.easeInOut.transform(phase * 2)
                  : Curves.easeInOut.transform((1 - phase) * 2);
              return Transform.translate(
                offset: Offset(0, -s * 0.5 * wave),
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.35 + 0.65 * wave),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }(),
          ],
        ],
      ),
    );
  }
}

/// A soft highlight sweeping across its child, for text that is "in progress".
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          colors: [widget.color, widget.color],
        ).createShader(rect),
        child: widget.child,
      );
    }
    final base = widget.color.withValues(alpha: 0.6);
    final peak = Color.lerp(widget.color, Colors.white, 0.55)!;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final x = -1.0 + 3.0 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: [base, peak, base],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
