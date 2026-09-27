import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show AppIcon, StatusDot;

enum Tone { neutral, accent, ok, run, danger }

(Color fg, Color bg) toneColors(Tone tone) => switch (tone) {
      Tone.neutral => (AppColors.fg3, AppColors.hover),
      Tone.accent => (AppColors.accent, AppColors.accentBg),
      Tone.ok => (AppColors.ok, AppColors.okBg),
      Tone.run => (AppColors.run, AppColors.runBg),
      Tone.danger => (AppColors.danger, AppColors.dangerBg),
    };

class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.tone = Tone.neutral,
    this.icon,
    this.dot = false,
    this.live = false,
    this.mono = false,
  });

  final String label;
  final Tone tone;
  final String? icon;
  final bool dot;
  final bool live;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = toneColors(tone);
    final style = mono
        ? TS.codeSmall(fg).copyWith(fontSize: 11, height: 16 / 11)
        : TS.meta(fg).copyWith(fontWeight: W.label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (live) ...[
          StatusDot(status: 'running', size: 6, color: fg),
          const SizedBox(width: S.s6),
        ] else if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: S.s6),
        ] else if (icon != null) ...[
          AppIcon(icon!, size: 12, color: fg),
          const SizedBox(width: S.s4),
        ],
        Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.tone = Tone.neutral});

  final int count;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = toneColors(tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: S.s6),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text('$count',
          style: TS.meta(fg).copyWith(fontWeight: W.label, height: 1)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.count,
    this.tone = Tone.neutral,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, S.s8),
  });

  final String title;
  final int? count;
  final Tone tone;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Text(title, style: TS.label(AppColors.fg2)),
        if (count != null) ...[
          const SizedBox(width: S.s8),
          CountBadge(count!, tone: tone),
        ],
        const Spacer(),
        if (action != null) TextAction(action!, onTap: onAction),
      ]),
    );
  }
}

class TextAction extends StatelessWidget {
  const TextAction(this.label,
      {super.key, this.onTap, this.icon, this.danger = false});

  final String label;
  final bool danger;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.fg4
        : danger
            ? AppColors.danger
            : AppColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        constraints: BoxConstraints(minHeight: kMobile ? M.minTarget : 28),
        padding: const EdgeInsets.symmetric(horizontal: S.s8),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TS.label(color)),
          if (icon != null) ...[
            const SizedBox(width: S.s4),
            AppIcon(icon!, size: 14, color: color),
          ],
        ]),
      ),
    );
  }
}

class SurfaceScope extends InheritedWidget {
  const SurfaceScope({super.key, required this.group, required super.child});

  final Color group;

  static Color groupOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SurfaceScope>()?.group ??
      AppColors.raised;

  @override
  bool updateShouldNotify(SurfaceScope oldWidget) => group != oldWidget.group;
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.s6),
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lineStrong,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.s16, S.s4, S.s6, S.s2),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle(AppColors.fg1)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Tooltip(
                message: 'Close',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.overlay,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: AppIcon('x', size: 13, color: AppColors.fg3),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      );
}

class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.header});

  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SurfaceScope.groupOf(context),
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header!,
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 || header != null)
              Divider(height: 1, thickness: 1, color: AppColors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.titleWidget,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? M.rowHeight : 36),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: S.s12)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget ??
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.rowTitle(
                                selected ? AppColors.fg1 : AppColors.fg1)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.s2),
                        child: Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: S.s8),
                trailing!,
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name,
      {super.key, this.size = 36, this.presence, this.ring});

  final String name;
  final double size;
  final bool? presence;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.hover,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Text(initial,
              style: TS
                  .rowTitle(AppColors.fg1)
                  .copyWith(fontSize: size * 0.42, height: 1)),
        ),
        if (presence != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: presence! ? AppColors.ok : AppColors.fg4,
                shape: BoxShape.circle,
                border: Border.all(color: ring ?? AppColors.base, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon,
      {super.key, this.tone = Tone.neutral, this.size = 36});

  final String icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = toneColors(tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.sm + 2),
      ),
      child: AppIcon(icon, size: size / 2, color: fg),
    );
  }
}

class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          strokeWidth: size <= 14 ? 1.6 : 2,
          strokeCap: StrokeCap.round,
          color: color ?? AppColors.fg3,
        ),
      );
}

class DelayedSpinner extends StatefulWidget {
  const DelayedSpinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  State<DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<DelayedSpinner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: Motion.quick,
        child: Spinner(size: widget.size, color: widget.color),
      );
}

class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label ?? 'Loading',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const DelayedSpinner(),
            if (label != null) ...[
              const SizedBox(height: S.s12),
              Text(label!, style: TS.meta()),
            ],
          ]),
        ),
      );
}

class Skeleton extends StatelessWidget {
  const Skeleton(
      {super.key, this.width, this.height = 12, this.radius = R.xs, this.color});

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AppColors.raised,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 3, this.subtitle = true});

  final int rows;
  final bool subtitle;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: PageBody(children: [
          Material(
            color: SurfaceScope.groupOf(context),
            borderRadius: BorderRadius.circular(R.md),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < rows; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: kMobile ? M.rowHeight : 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.s12, vertical: S.s12),
                    child: Row(children: [
                      Skeleton(width: 20, height: 20, radius: R.sm, color: AppColors.hover),
                      const SizedBox(width: S.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.55 : 0.4,
                              child: Skeleton(height: 12, color: AppColors.hover),
                            ),
                            if (subtitle) ...[
                              const SizedBox(height: S.s6),
                              FractionallySizedBox(
                                widthFactor: i.isEven ? 0.35 : 0.5,
                                child: Skeleton(height: 10, color: AppColors.hover),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      );
}

class InsetPanel extends StatelessWidget {
  const InsetPanel({
    super.key,
    required this.child,
    this.tone,
    this.padding = const EdgeInsets.all(S.s12),
  });

  final Widget child;
  final Tone? tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bg = tone == null ? AppColors.overlay : toneColors(tone!).$2;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.sm + 2),
      ),
      child: child,
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 720});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final side = kMobile ? S.s16 : S.s24;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + side * 2),
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, S.s8, side, S.s40),
          children: children,
        ),
      ),
    );
  }
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, 0),
        child: Text(text, style: TS.meta()),
      );
}

class SelectCheck extends StatelessWidget {
  const SelectCheck(this.selected, {super.key, this.size = 18});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: Motion.quick,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.accentFill : Colors.transparent,
          border: Border.all(
              color: selected ? AppColors.accentFill : AppColors.lineStrong,
              width: 1.5),
        ),
        child: selected
            ? AppIcon('check', size: size * 0.66, color: AppColors.accentFg)
            : null,
      );
}

class InlineEditField extends StatelessWidget {
  const InlineEditField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSubmit,
    required this.onCancel,
    this.hint,
    this.dense = false,
    this.showActions,
    this.commitOnTapOutside = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final String? hint;
  final bool dense;
  final bool? showActions;
  final bool commitOnTapOutside;

  @override
  Widget build(BuildContext context) {
    final actions = showActions ?? !kMobile;
    Widget action(String icon, String tip, VoidCallback onTap, Color color) =>
        Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.xs),
            onTap: onTap,
            child: SizedBox.square(
              dimension: dense ? 24 : 28,
              child: Center(child: AppIcon(icon, size: 14, color: color)),
            ),
          ),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Container(
        height: dense ? 30 : (kMobile ? 40 : 34),
        padding: EdgeInsets.fromLTRB(S.s8, 0, actions ? S.s2 : S.s8, 0),
        decoration: BoxDecoration(
          color: AppColors.overlay,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.accent, width: 1.5),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              maxLines: 1,
              style: dense
                  ? TS.label(AppColors.fg1).copyWith(fontWeight: W.body)
                  : TS.ui(AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TS.ui(AppColors.fg4),
              ),
              onSubmitted: (_) => onSubmit(),
              onTapOutside: commitOnTapOutside ? (_) => onSubmit() : null,
            ),
          ),
          if (actions) ...[
            action('check', 'Save', onSubmit, AppColors.accent),
            action('x', 'Cancel', onCancel, AppColors.fg3),
          ],
        ]),
      ),
    );
  }
}
