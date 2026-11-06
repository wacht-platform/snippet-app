import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class LiveCaptionFeed {
  LiveCaptionFeed({this.finalHold = const Duration(milliseconds: 2500), this.partialHold = const Duration(seconds: 4)});

  static final LiveCaptionFeed instance = LiveCaptionFeed();

  final Duration finalHold;
  final Duration partialHold;
  final ValueNotifier<String?> text = ValueNotifier(null);
  Timer? _clear;

  void apply(Map<dynamic, dynamic> event) {
    final next = event['text']?.toString().trim() ?? '';
    if (next.isEmpty) return;
    text.value = next;
    _clear?.cancel();
    _clear = Timer(event['final'] == true ? finalHold : partialHold, () => text.value = null);
  }
}

/// Padding around a composer, with the caption floating just above it so the chat never shifts as words arrive.
class LiveCaptionAnchor extends StatelessWidget {
  const LiveCaptionAnchor({super.key, required this.padding, required this.child, this.feed});

  final EdgeInsets padding;
  final Widget child;
  final LiveCaptionFeed? feed;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final motion = media.disableAnimations ? Duration.zero : const Duration(milliseconds: 160);
    final lineHeight = media.textScaler.scale(13) * 1.4;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Padding(padding: padding, child: child),
        Positioned(
          top: 0,
          left: padding.left,
          right: padding.right,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: FractionalTranslation(
                translation: const Offset(0, -1),
                child: ValueListenableBuilder<String?>(
                  valueListenable: (feed ?? LiveCaptionFeed.instance).text,
                  builder: (context, text, _) => AnimatedSwitcher(
                    duration: motion,
                    child: text == null
                        ? const SizedBox.shrink(key: ValueKey('empty'))
                        : SizedBox(
                            key: const ValueKey('caption'),
                            width: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(R.lg),
                                border: Border.all(color: AppColors.border2),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.only(top: (lineHeight - 6) / 2, right: 8),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                                        child: const SizedBox.square(dimension: 6),
                                      ),
                                    ),
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxHeight: lineHeight * 2 + 1),
                                        // Reversed so a long caption stays pinned to its newest line.
                                        child: SingleChildScrollView(
                                          reverse: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          child: Text(
                                            text,
                                            style: sans(13, color: AppColors.fg1).copyWith(decoration: TextDecoration.none, height: 1.4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
