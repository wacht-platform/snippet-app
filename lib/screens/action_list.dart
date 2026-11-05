import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// A titled block of action rows, as in a session's or an agent's Actions.
class ActionGroup extends StatelessWidget {
  const ActionGroup({super.key, required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    if (kMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 2),
            child: Text(label.toUpperCase(),
                style: sans(12,
                    weight: W.label, spacing: 0.7, color: AppColors.fg4)),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppColors.line),
            rows[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: kMobile
              ? const EdgeInsets.fromLTRB(4, 20, 4, 6)
              : const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(kMobile ? label : label.toUpperCase(),
              style: kMobile
                  ? sans(12, color: AppColors.fg4)
                  : caps(10, color: AppColors.fg3)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? 16 : R.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Container(
                      height: 1,
                      margin:
                          EdgeInsets.symmetric(horizontal: kMobile ? 16 : 0),
                      color: AppColors.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.detail,
    this.value,
    this.expandable = false,
    this.open = false,
    this.danger = false,
    this.onTap,
    this.trailing,
    this.child,
  });

  final String icon;
  final String label;
  final String? detail;
  final String? value;
  final bool expandable;
  final bool open;
  final bool danger;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final value = this.value;
    final trailing = this.trailing;
    final child = this.child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: M.minTarget + 8),
              padding: EdgeInsets.symmetric(
                  horizontal: kMobile ? 4 : 14, vertical: kMobile ? 11 : 0),
              child: Row(children: [
                AppIcon(icon,
                    size: kMobile ? 19 : 17,
                    color: danger ? AppColors.danger : AppColors.fg3),
                SizedBox(width: kMobile ? 14 : 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: kMobile
                              ? sans(15.5,
                                  height: 20 / 15.5,
                                  color: danger ? AppColors.danger : AppColors.fg1)
                              : sans(13,
                                  weight: W.label,
                                  color: danger ? AppColors.danger : AppColors.fg1)),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: kMobile ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: kMobile
                                ? sans(13,
                                    height: 18 / 13, color: AppColors.fg3)
                                : sans(M.meta, color: AppColors.fg3)),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: sans(M.meta, color: AppColors.fg3)),
                  ),
                ],
                const SizedBox(width: 8),
                if (trailing != null)
                  trailing
                else if (expandable || (kMobile && onTap != null))
                  AppIcon(open ? 'chevron-down' : 'chevron-right',
                      size: 15, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
        if (open && child != null)
          Padding(
            padding: kMobile
                ? const EdgeInsets.fromLTRB(4, 0, 4, 14)
                : const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child,
          ),
      ],
    );
  }
}
