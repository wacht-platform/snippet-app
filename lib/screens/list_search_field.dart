import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// The filter field at the top of a list: a quiet surface step that narrows
/// the list below it as you type. One widget for every phone tab and desktop
/// panel, so search looks and behaves the same everywhere.
class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final height = kMobile ? 40.0 : 28.0;
    final text = kMobile ? 15.0 : 12.0;
    return Container(
      height: height,
      padding: EdgeInsets.only(left: kMobile ? 12 : 8, right: 2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? R.md : R.xs),
      ),
      child: Row(children: [
        AppIcon('search', size: kMobile ? 16 : 13, color: AppColors.fg3),
        SizedBox(width: kMobile ? 8 : 6),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            cursorColor: AppColors.accent,
            style: sans(text, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: sans(text, color: AppColors.fg4),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (_, __) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconBtn('x',
                  size: kMobile ? 36 : 22,
                  iconSize: kMobile ? 14 : 10,
                  tooltip: 'Clear',
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  }),
        ),
      ]),
    );
  }
}
