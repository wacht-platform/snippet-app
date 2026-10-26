import 'package:flutter/material.dart';

import 'theme.dart';

class DesktopPage extends StatelessWidget {
  const DesktopPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.maxWidth = 1040,
    this.scroll = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: sans(20,
                weight: W.strong, spacing: -0.2, color: AppColors.fg1)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: S.s4),
          Text(subtitle!, style: sans(13, color: AppColors.fg3)),
        ],
      ],
    );
    final buttons = Wrap(spacing: S.s8, runSpacing: S.s8, children: actions);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: S.s24),
      child: LayoutBuilder(
        builder: (_, c) => actions.isEmpty
            ? titleBlock
            : c.maxWidth < 520
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        titleBlock,
                        const SizedBox(height: S.s12),
                        buttons
                      ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: S.s16),
                    buttons,
                  ]),
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
      children: [header, if (scroll) child else Expanded(child: child)],
    );
    const pad = EdgeInsets.fromLTRB(S.s40, S.s32, S.s40, S.s32);
    final framed = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + pad.horizontal),
        child: Padding(padding: pad, child: body),
      ),
    );
    return scroll ? SingleChildScrollView(child: framed) : framed;
  }
}

class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 320,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) =>
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: c.maxWidth.isFinite
                ? masterWidth.clamp(0, c.maxWidth * 0.4).toDouble()
                : masterWidth,
            child: master),
        VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
        Expanded(child: detail),
      ]),
    );
  }
}

class MasterPane extends StatelessWidget {
  const MasterPane({
    super.key,
    required this.title,
    this.actions = const [],
    this.search,
    required this.children,
    this.empty,
  });

  final String title;
  final List<Widget> actions;
  final Widget? search;
  final List<Widget> children;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s16, S.s12, S.s8),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: sans(15, weight: W.strong, color: AppColors.fg1)),
          ),
          ...actions,
        ]),
      ),
      if (search != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(S.s12, 0, S.s12, S.s8),
          child: search,
        ),
      Expanded(
        child: children.isEmpty && empty != null
            ? Padding(padding: const EdgeInsets.all(S.s16), child: empty)
            : ListView(
                padding: const EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.s16),
                children: children,
              ),
      ),
    ]);
  }
}

class DetailPane extends StatelessWidget {
  const DetailPane({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.maxWidth = 760,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return DesktopPage(
      title: title,
      subtitle: subtitle,
      actions: actions,
      maxWidth: maxWidth,
      child: child,
    );
  }
}

class DetailEmpty extends StatelessWidget {
  const DetailEmpty(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: sans(13.5, color: AppColors.fg3)),
    );
  }
}

class DesktopFormRow extends StatelessWidget {
  const DesktopFormRow({
    super.key,
    required this.label,
    this.description,
    required this.control,
    this.divider = true,
  });

  final String label;
  final String? description;
  final Widget control;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: S.s16),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)))
          : null,
      child: LayoutBuilder(builder: (_, c) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: sans(13.5, weight: W.label, color: AppColors.fg1)),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(description!,
                  style: sans(12.5, height: 1.45, color: AppColors.fg3)),
            ],
          ],
        );
        if (c.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: S.s8),
              Align(alignment: Alignment.centerLeft, child: control),
            ],
          );
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: c.maxWidth < 760 ? 200 : 260, child: text),
          const SizedBox(width: S.s24),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: control),
          ),
        ]);
      }),
    );
  }
}

class SettingsBack extends StatelessWidget {
  const SettingsBack(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chevron_left, size: 16, color: AppColors.fg3),
              const SizedBox(width: 2),
              Text(label, style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.back,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? back;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null) ...[back!, const SizedBox(height: S.s8)],
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(18,
                      weight: W.strong, spacing: -0.2, color: AppColors.fg1)),
            ),
            for (final a in actions) ...[const SizedBox(width: S.s8), a],
          ]),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: S.s4),
            Text(subtitle!, style: sans(13, color: AppColors.fg3)),
          ],
        ],
      ),
    );
  }
}

class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.s32, S.s24, S.s32, S.s32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
