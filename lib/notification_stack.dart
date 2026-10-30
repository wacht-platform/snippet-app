import 'package:flutter/material.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart' show AppIcon;

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

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) return cardBuilder(items.first, false);
    return Material(
        type: MaterialType.transparency,
        child: expanded ? _expanded(context) : _collapsed());
  }

  Widget _link(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.xs),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 6, vertical: kMobile ? 10 : 4),
          child: Text(label,
              style: sans(12.5, weight: W.label, color: AppColors.accent)),
        ),
      );

  Widget _collapsed() {
    final ghosts = (items.length - 1).clamp(0, 2);
    final more = items.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 5.0 * ghosts),
          child: Center(
              child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: kMobile ? 300 : double.infinity),
            child: Stack(clipBehavior: Clip.none, children: [
              for (var i = ghosts; i >= 1; i--)
                Positioned(
                  left: 9.0 * i,
                  right: 9.0 * i,
                  bottom: -5.0 * i,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i == 1 ? AppColors.surface2 : AppColors.surface1,
                      border: Border.all(color: AppColors.lineStrong),
                      borderRadius: BorderRadius.circular(kMobile ? 20 : 10),
                    ),
                  ),
                ),
              cardBuilder(items.first, false),
            ]),
          )),
        ),
        Padding(
          padding: const EdgeInsets.only(top: S.s4),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(R.xs),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 6, vertical: kMobile ? 10 : 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$more more', style: mono(11.5, color: AppColors.fg3)),
                    const SizedBox(width: 4),
                    AppIcon('chevron-down', size: 12, color: AppColors.fg3),
                  ]),
                ),
              ),
              _link('Clear all', onClearAll),
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

    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 2),
          child: Text(t, style: mono(10.5, color: AppColors.fg4)),
        );

    Widget rows(List<Map<String, dynamic>> l) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, p) in l.indexed) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: AppColors.line),
              cardBuilder(p, true),
            ]
          ],
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(kMobile ? 20 : 12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 6, 0),
          child: Row(children: [
            Expanded(
              child: Text('${items.length} notifications',
                  style: mono(11.5, color: AppColors.fg3)),
            ),
            _link('Clear all', onClearAll),
            _link('Collapse', onToggle),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: AppColors.line),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (need.isNotEmpty) ...[label('NEEDS YOU'), rows(need)],
                  if (updates.isNotEmpty) ...[label('UPDATES'), rows(updates)],
                  const SizedBox(height: S.s4),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
