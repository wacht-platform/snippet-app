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
