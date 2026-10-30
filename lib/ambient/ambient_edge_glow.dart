import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../macos_notch.dart';
import '../platform.dart';
import '../theme.dart';
import 'controller.dart';
import 'voice.dart';

/// Renders a dynamic, soft perimeter edge glow around the application viewport
/// when ambient voice listening is active.
///
/// Features a calm, subtle breathing luminescence while listening that gently
/// brightens and pulses when Snippet or the user speaks. Fully non-intrusive
/// via [IgnorePointer], with full reduced-motion support.
class AmbientEdgeGlow extends StatefulWidget {
  const AmbientEdgeGlow({
    super.key,
    required this.child,
    this.controller,
    this.overrideActive,
    this.overrideSpeaking,
    this.overrideAssistantSpeaking,
    this.overrideColor,
  });

  final Widget child;
  final AmbientController? controller;
  final bool? overrideActive;
  final bool? overrideSpeaking;
  final bool? overrideAssistantSpeaking;
  final Color? overrideColor;

  @override
  State<AmbientEdgeGlow> createState() => _AmbientEdgeGlowState();
}

class _AmbientEdgeGlowState extends State<AmbientEdgeGlow>
    with TickerProviderStateMixin {
  late final AnimationController _cycleController;
  late final AnimationController _fadeController;
  late final AmbientController _ambient;

  ValueListenable<AmbientVoice?>? _voiceListenable;
  AmbientVoice? _currentVoice;
  bool _wasSpeaking = false;

  @override
  void initState() {
    super.initState();
    _ambient = widget.controller ?? AmbientController.instance;

    _cycleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _ambient.addListener(_onAmbientChanged);
    _syncVoiceListenable();

    _updateAnimationState(animate: false);
  }

  @override
  void didUpdateWidget(covariant AmbientEdgeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overrideActive != widget.overrideActive ||
        oldWidget.overrideSpeaking != widget.overrideSpeaking ||
        oldWidget.overrideAssistantSpeaking !=
            widget.overrideAssistantSpeaking ||
        oldWidget.overrideColor != widget.overrideColor) {
      _updateAnimationState(animate: true);
    }
  }

  void _syncVoiceListenable() {
    final next = _ambient.voice;
    if (!identical(next, _voiceListenable)) {
      _voiceListenable?.removeListener(_onVoiceHolderChanged);
      _voiceListenable = next;
      _voiceListenable?.addListener(_onVoiceHolderChanged);
    }
    _onVoiceHolderChanged();
  }

  void _onAmbientChanged() {
    _syncVoiceListenable();
    if (mounted) setState(() => _updateAnimationState(animate: true));
  }

  void _onVoiceHolderChanged() {
    final newVoice = _voiceListenable?.value;
    if (identical(newVoice, _currentVoice)) return;
    _currentVoice?.speaking.removeListener(_onVoiceStateChanged);
    _currentVoice?.state.removeListener(_onVoiceStateChanged);
    _currentVoice = newVoice;
    _currentVoice?.speaking.addListener(_onVoiceStateChanged);
    _currentVoice?.state.addListener(_onVoiceStateChanged);
    if (mounted) setState(() => _updateAnimationState(animate: true));
  }

  void _onVoiceStateChanged() {
    if (mounted) setState(() => _updateAnimationState(animate: true));
  }

  bool get _isActive {
    if (widget.overrideActive != null) return widget.overrideActive!;
    return _ambient.status.running;
  }

  bool get _isUserSpeaking {
    if (widget.overrideSpeaking != null) return widget.overrideSpeaking!;
    return _ambient.status.speaking;
  }

  bool get _isAssistantSpeaking {
    if (widget.overrideAssistantSpeaking != null) {
      return widget.overrideAssistantSpeaking!;
    }
    if (_ambient.status.assistantSpeaking) return true;
    final voice = _currentVoice;
    if (voice != null && voice.speaking.value) return true;
    final stateEvent = voice?.state.value;
    if (stateEvent != null && stateEvent.sub == 'speaking') return true;
    return false;
  }

  double get _speechProbability => _ambient.status.probability;

  Color get _glowColor {
    if (widget.overrideColor != null) return widget.overrideColor!;
    return AppColors.accent;
  }

  void _updateAnimationState({required bool animate}) {
    final active = _isActive;
    if (active) {
      if (_fadeController.value < 1.0 && !_fadeController.isAnimating) {
        if (animate) {
          _fadeController.forward();
        } else {
          _fadeController.value = 1.0;
        }
      }
    } else {
      if (_fadeController.value > 0.0 && !_fadeController.isAnimating) {
        if (animate) {
          _fadeController.reverse();
        } else {
          _fadeController.value = 0.0;
        }
      }
    }

    final speaking = _isAssistantSpeaking;
    if (speaking != _wasSpeaking) {
      _wasSpeaking = speaking;
      _cycleController.duration = speaking
          ? const Duration(milliseconds: 1300)
          : const Duration(milliseconds: 3800);
      if (_cycleController.isAnimating) {
        _cycleController.repeat();
      }
    }

    if (active && !_cycleController.isAnimating) {
      _cycleController.repeat();
    } else if (!active && _fadeController.value == 0.0) {
      _cycleController.stop();
    }

    MacosNotch.updateAmbient(
      active: active,
      userSpeaking: _isUserSpeaking,
      assistantSpeaking: speaking,
      probability: _speechProbability,
    );
  }

  @override
  void dispose() {
    _ambient.removeListener(_onAmbientChanged);
    _voiceListenable?.removeListener(_onVoiceHolderChanged);
    _currentVoice?.speaking.removeListener(_onVoiceStateChanged);
    _currentVoice?.state.removeListener(_onVoiceStateChanged);
    _cycleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_cycleController, _fadeController]),
                builder: (context, _) {
                  final fadeVal = _fadeController.value;
                  if (fadeVal <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                    painter: _AmbientEdgeGlowPainter(
                      t: _cycleController.value,
                      fade: fadeVal,
                      isAssistantSpeaking: _isAssistantSpeaking,
                      isUserSpeaking: _isUserSpeaking,
                      probability: _speechProbability,
                      baseColor: _glowColor,
                      isMobile: kMobile,
                      reducedMotion: reducedMotion,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientEdgeGlowPainter extends CustomPainter {
  _AmbientEdgeGlowPainter({
    required this.t,
    required this.fade,
    required this.isAssistantSpeaking,
    required this.isUserSpeaking,
    required this.probability,
    required this.baseColor,
    required this.isMobile,
    required this.reducedMotion,
  });

  final double t;
  final double fade;
  final bool isAssistantSpeaking;
  final bool isUserSpeaking;
  final double probability;
  final Color baseColor;
  final bool isMobile;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0.001) return;

    final tau = math.pi * 2;
    final breath = reducedMotion ? 0.5 : (0.5 + 0.5 * math.sin(t * tau));
    final harmonic = reducedMotion
        ? 0.0
        : (0.25 * math.sin(t * 2 * tau + math.pi / 4));

    final double baseSpread = isMobile ? 20.0 : 26.0;
    double spread;
    double alpha;

    if (isAssistantSpeaking) {
      final pulse = (breath + harmonic).clamp(0.0, 1.0);
      spread = baseSpread * (1.35 + 0.3 * pulse);
      alpha = (0.36 + 0.24 * pulse) * fade;
    } else if (isUserSpeaking) {
      final prob = probability.clamp(0.2, 1.0);
      spread = baseSpread * (1.1 + 0.2 * prob);
      alpha = (0.22 + 0.14 * prob) * fade;
    } else {
      spread = baseSpread * (0.88 + 0.16 * breath);
      alpha = (0.12 + 0.08 * breath) * fade;
    }

    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final primaryColor = isAssistantSpeaking
        ? Color.lerp(baseColor, Colors.white, 0.18)!
        : baseColor;

    final edgePaint = Paint();

    // 1. Top Edge
    final topRect = Rect.fromLTWH(0, 0, w, spread);
    edgePaint.shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(0, spread),
      [
        primaryColor.withValues(alpha: alpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(topRect, edgePaint);

    // 2. Bottom Edge
    final bottomRect = Rect.fromLTWH(0, h - spread, w, spread);
    edgePaint.shader = ui.Gradient.linear(
      Offset(0, h),
      Offset(0, h - spread),
      [
        primaryColor.withValues(alpha: alpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(bottomRect, edgePaint);

    // 3. Left Edge
    final leftRect = Rect.fromLTWH(0, 0, spread, h);
    edgePaint.shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(spread, 0),
      [
        primaryColor.withValues(alpha: alpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(leftRect, edgePaint);

    // 4. Right Edge
    final rightRect = Rect.fromLTWH(w - spread, 0, spread, h);
    edgePaint.shader = ui.Gradient.linear(
      Offset(w, 0),
      Offset(w - spread, 0),
      [
        primaryColor.withValues(alpha: alpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(rightRect, edgePaint);

    // 5. Corners (Radial vignettes for smooth continuous framing)
    final cornerRadius = spread * 1.35;
    final cornerAlpha = (alpha * 1.1).clamp(0.0, 1.0);

    // Top-Left
    edgePaint.shader = ui.Gradient.radial(
      const Offset(0, 0),
      cornerRadius,
      [
        primaryColor.withValues(alpha: cornerAlpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, cornerRadius, cornerRadius), edgePaint);

    // Top-Right
    edgePaint.shader = ui.Gradient.radial(
      Offset(w, 0),
      cornerRadius,
      [
        primaryColor.withValues(alpha: cornerAlpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(w - cornerRadius, 0, cornerRadius, cornerRadius),
      edgePaint,
    );

    // Bottom-Left
    edgePaint.shader = ui.Gradient.radial(
      Offset(0, h),
      cornerRadius,
      [
        primaryColor.withValues(alpha: cornerAlpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h - cornerRadius, cornerRadius, cornerRadius),
      edgePaint,
    );

    // Bottom-Right
    edgePaint.shader = ui.Gradient.radial(
      Offset(w, h),
      cornerRadius,
      [
        primaryColor.withValues(alpha: cornerAlpha),
        primaryColor.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(w - cornerRadius, h - cornerRadius, cornerRadius, cornerRadius),
      edgePaint,
    );

    // 6. Secondary soft ambient bloom when Snippet is speaking
    if (isAssistantSpeaking) {
      final bloomSpread = spread * 1.7;
      final bloomAlpha = alpha * 0.35;
      final bloomColor = baseColor.withValues(alpha: bloomAlpha);
      final bloomEnd = baseColor.withValues(alpha: 0);

      // Top bloom
      edgePaint.shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, bloomSpread),
        [bloomColor, bloomEnd],
      );
      canvas.drawRect(Rect.fromLTWH(0, 0, w, bloomSpread), edgePaint);

      // Bottom bloom
      edgePaint.shader = ui.Gradient.linear(
        Offset(0, h),
        Offset(0, h - bloomSpread),
        [bloomColor, bloomEnd],
      );
      canvas.drawRect(Rect.fromLTWH(0, h - bloomSpread, w, bloomSpread), edgePaint);

      // Left bloom
      edgePaint.shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(bloomSpread, 0),
        [bloomColor, bloomEnd],
      );
      canvas.drawRect(Rect.fromLTWH(0, 0, bloomSpread, h), edgePaint);

      // Right bloom
      edgePaint.shader = ui.Gradient.linear(
        Offset(w, 0),
        Offset(w - bloomSpread, 0),
        [bloomColor, bloomEnd],
      );
      canvas.drawRect(Rect.fromLTWH(w - bloomSpread, 0, bloomSpread, h), edgePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientEdgeGlowPainter old) =>
      old.t != t ||
      old.fade != fade ||
      old.isAssistantSpeaking != isAssistantSpeaking ||
      old.isUserSpeaking != isUserSpeaking ||
      old.probability != probability ||
      old.baseColor != baseColor ||
      old.isMobile != isMobile ||
      old.reducedMotion != reducedMotion;
}
