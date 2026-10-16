import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_widgets.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup(
      {super.key, this.header, this.footer, required this.children});
  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: kMobile ? 16 : 14),
          child: Container(height: 1, color: AppColors.line),
        ));
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? 26 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.fromLTRB(kMobile ? 16 : 4, 0, 4, 6),
            child: Text(header!.toUpperCase(),
                style: sans(kMobile ? 12 : 11,
                    spacing: 0.7, color: AppColors.fg4)),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(kMobile ? 16 : 4, 7, 4, 0),
            child: Text(footer!,
                style: sans(kMobile ? 12.5 : 12,
                    height: 1.5, color: AppColors.fg4)),
          ),
      ]),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.sub,
    this.trailing,
    this.leading,
    this.onTap,
    this.chevron = false,
    this.danger = false,
    this.labelWidget,
  });
  final String label;
  final String? sub;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: kMobile ? 52 : 40),
      child: Padding(
        padding: kMobile
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  labelWidget ??
                      Text(label,
                          style: sans(kMobile ? 15 : 13,
                              color: danger
                                  ? AppColors.danger
                                  : AppColors.fg1)),
                  if (sub != null && sub!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub!,
                        style: sans(kMobile ? 12.5 : 12,
                            height: 1.4, color: AppColors.fg4)),
                  ],
                ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (chevron) ...[
            const SizedBox(width: 8),
            AppIcon('chevron-right', size: 13, color: AppColors.fg4),
          ],
        ]),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: MouseRegion(
          cursor: onChanged == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: kMobile ? 44 : 34,
            height: kMobile ? 26 : 20,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? AppColors.accent : AppColors.surface3,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Container(
              width: kMobile ? 22 : 16,
              height: kMobile ? 22 : 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? AppColors.bg : AppColors.fg3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPopup<T> extends StatelessWidget {
  const SettingsPopup({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.leading,
  });
  final String label;
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => Material(
        color: kMobile ? Colors.transparent : AppColors.surface2,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () async {
            final picked = await showAppMenu<T>(context,
                anchor: anchor,
                items: [
                  for (final (v, l) in items)
                    appMenuItem(value: v, label: l, selected: v == selected),
                ]);
            if (picked != null) onSelected(picked);
          },
          child: Container(
            height: kMobile ? 32 : 26,
            padding: EdgeInsets.fromLTRB(kMobile ? 4 : 10, 0, kMobile ? 0 : 8, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 7)],
              Text(label,
                  style: sans(kMobile ? 15 : 12.5,
                      color: kMobile ? AppColors.fg3 : AppColors.fg1)),
              const SizedBox(width: 6),
              AppIcon(kMobile ? 'chevron-right' : 'chevrons-up-down',
                  size: kMobile ? 14 : 12, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    this.hint,
    this.width = 240,
    this.mono = false,
    this.obscure = false,
    this.number = false,
    this.onChanged,
    this.suffix,
  });
  final TextEditingController controller;
  final String? hint;
  final double width;
  final bool mono;
  final bool obscure;
  final bool number;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? mono_(kMobile ? 14 : 12.5)
        : sans(kMobile ? 15 : 12.5, color: AppColors.fg1);
    return SizedBox(
      width: kMobile ? (width > 170 ? 170 : width) : width,
      child: Container(
        height: kMobile ? 34 : 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: kMobile
            ? null
            : BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.border),
              ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              onChanged: onChanged,
              textAlign: kMobile ? TextAlign.right : TextAlign.left,
              keyboardType: number ? TextInputType.number : null,
              inputFormatters:
                  number ? [FilteringTextInputFormatter.digitsOnly] : null,
              style: style,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: style.copyWith(color: AppColors.fg4),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 6), suffix!],
        ]),
      ),
    );
  }
}

TextStyle mono_(double size) => mono(size, color: AppColors.fg1);

class SettingsPill extends StatelessWidget {
  const SettingsPill(this.label,
      {super.key, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
        color: danger ? Colors.transparent : AppColors.surface2,
        shape: StadiumBorder(
            side: BorderSide(
                color: danger
                    ? AppColors.danger.withValues(alpha: 0.3)
                    : Colors.transparent)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(12.5,
                    color: danger ? AppColors.danger : AppColors.fg2)),
          ),
        ),
      );
}
