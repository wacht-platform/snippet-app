import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'notification_card.dart' show notificationTone;
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show AppIcon, HoverSurface, Reveal;

bool needsYou(Map<String, dynamic> p) =>
    '${p['kind'] ?? ''}'.split('.').last == 'waiting';

typedef StackCardBuilder = Widget Function(
    Map<String, dynamic> payload, bool embedded);

class NotificationStack extends StatelessWidget {
  const NotificationStack({
    super.key,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.onClearAll,
    required this.cardBuilder,
  });

  final List<Map<String, dynamic>> items;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClearAll;
  final StackCardBuilder cardBuilder;

  static double get _pillWidth => 300;
  static double get _panelRadius => kMobile ? 24 : R.lg;
  static double get _ghostRadius => kMobile ? 22 : R.card;
  static const _peek = 7.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final calm = reduceMotion(context);
    final single = items.length == 1;
    final child = single
        ? KeyedSubtree(
            key: const ValueKey('single'),
            child: cardBuilder(items.first, false))
        : expanded
            ? KeyedSubtree(
                key: const ValueKey('expanded'), child: _expanded(context))
            : KeyedSubtree(
                key: const ValueKey('collapsed'),
                child: _collapsed(context, calm));
    final switcher = AnimatedSwitcher(
      duration: calm ? Duration.zero : Motion.base,
      reverseDuration: calm ? Duration.zero : Motion.close,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          for (final p in previous)
            Positioned(top: 0, left: 0, right: 0, child: p),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.topCenter,
          scale: Tween(begin: .97, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
    // A zero-duration AnimatedSize re-dirties itself mid-layout.
    return Material(
      type: MaterialType.transparency,
      child: calm
          ? switcher
          : AnimatedSize(
              duration: Motion.base,
              reverseDuration: Motion.close,
              curve: Motion.enter,
              alignment: Alignment.topCenter,
              child: switcher,
            ),
    );
  }

  Widget _collapsed(BuildContext context, bool calm) {
    final ghosts = math.min(items.length - 1, 2);
    final hidden = items.skip(1).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: _peek * ghosts),
          child: LayoutBuilder(builder: (context, box) {
            final width =
                kMobile ? math.min(box.maxWidth, _pillWidth) : box.maxWidth;
            final side = kMobile ? (box.maxWidth - width) / 2 : 0.0;
            return Stack(clipBehavior: Clip.none, children: [
              for (var i = 2; i >= 1; i--)
                AnimatedPositioned(
                  duration: calm ? Duration.zero : Motion.base,
                  curve: Motion.enter,
                  left: side + (kMobile ? 14.0 : 10.0) * i,
                  right: side + (kMobile ? 14.0 : 10.0) * i,
                  bottom: -_peek * (i <= ghosts ? i : i - 1),
                  height: 28,
                  child: AnimatedOpacity(
                    duration: calm ? Duration.zero : Motion.fast,
                    opacity: i <= ghosts ? 1 : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.lerp(AppColors.surface2, AppColors.bg,
                              i == 1 ? .2 : .5),
                          border: Border.all(
                              color: Color.lerp(AppColors.lineStrong,
                                  AppColors.bg, i == 1 ? 0 : .3)!),
                          borderRadius: BorderRadius.circular(_ghostRadius),
                        ),
                      ),
                    ),
                  ),
                ),
              cardBuilder(items.first, false),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: S.s8),
          child: Wrap(
            alignment: kMobile ? WrapAlignment.center : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: S.s4,
            runSpacing: S.s4,
            children: [
              _Toggle(
                label: '${hidden.length} more',
                icon: 'chevron-down',
                tones: [for (final p in hidden.take(3)) notificationTone(p)],
                onTap: onToggle,
              ),
              _QuietButton('Clear all', onClearAll),
            ],
          ),
        ),
      ],
    );
  }

  Widget _expanded(BuildContext context) {
    final need = items.where(needsYou).toList();
    final updates = items.where((p) => !needsYou(p)).toList();
    final maxH = MediaQuery.sizeOf(context).height * .6;
    final inset = kMobile ? 18.0 : 14.0;
    final calm = reduceMotion(context);

    Widget section(String label, List<Map<String, dynamic>> rows) {
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, S.s12, inset, S.s2),
            child: Row(children: [
              Text(label, style: caps(10.5, color: AppColors.fg4)),
              const SizedBox(width: S.s6),
              Text('${rows.length}', style: mono(10.5, color: AppColors.fg4)),
            ]),
          ),
          for (final (i, p) in rows.indexed) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: inset + 18, right: inset),
                child: Divider(height: 1, thickness: 1, color: AppColors.line),
              ),
            cardBuilder(p, true),
          ],
        ],
      );
      if (calm) return rows.isEmpty ? const SizedBox.shrink() : body;
      return Reveal(show: rows.isNotEmpty, child: body);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(_panelRadius),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, S.s8, S.s8, S.s8),
          child: Row(children: [
            Text('Notifications',
                style: sans(kMobile ? 14 : 13,
                    weight: W.label, color: AppColors.fg1)),
            const SizedBox(width: S.s8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text('${items.length}',
                  style: mono(10.5, color: AppColors.fg2)),
            ),
            const Spacer(),
            _QuietButton('Clear all', onClearAll),
            const SizedBox(width: S.s4),
            _Toggle(
                label: 'Collapse',
                icon: 'chevron-up',
                inPanel: true,
                onTap: onToggle),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: AppColors.line),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: S.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('NEEDS YOU', need),
                  section('UPDATES', updates),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tones = const [],
    this.inPanel = false,
  });

  final String label;
  final String icon;
  final VoidCallback onTap;
  final List<Color> tones;
  final bool inPanel;

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      radius: R.pill,
      rest: inPanel ? AppColors.surface3 : AppColors.surface2,
      hoverColor: inPanel
          ? Color.lerp(AppColors.surface3, AppColors.fg4, .16)
          : AppColors.surface3,
      child: Container(
        constraints: BoxConstraints(minHeight: kMobile ? 36 : 26),
        padding: EdgeInsets.fromLTRB(tones.isEmpty ? 10 : 8, 0, 8, 0),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (tones.isNotEmpty) ...[
            SizedBox(
              width: 8.0 + 5 * (tones.length - 1),
              height: 10,
              child: Stack(children: [
                for (final (i, c) in tones.indexed.toList().reversed)
                  Positioned(
                    left: 5.0 * i - 1,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface2, width: 2),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: S.s6),
          ],
          Text(label,
              style: sans(kMobile ? 13 : 12,
                  weight: W.label, color: AppColors.fg2, tabular: true)),
          const SizedBox(width: S.s4),
          AppIcon(icon, size: 13, color: AppColors.fg3),
        ]),
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      radius: R.pill,
      hoverColor: AppColors.surface3,
      child: Container(
        height: kMobile ? 36 : 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(
          widthFactor: 1,
          child: Text(label,
              style: sans(kMobile ? 13 : 12,
                  weight: W.label, color: AppColors.fg3)),
        ),
      ),
    );
  }
}
