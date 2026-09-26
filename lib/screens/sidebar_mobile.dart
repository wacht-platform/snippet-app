import 'package:flutter/material.dart';

import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_panel.dart';
import 'shell_models.dart';

/// Empty state when no sessions match the search query, or when no sessions
/// exist in the workspace yet.
class SidebarEmpty extends StatelessWidget {
  final String message;
  const SidebarEmpty(this.message, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(message,
            style: TS.meta(), textAlign: TextAlign.center),
      );
}

class SidebarMobileBar extends StatelessWidget {
  final bool hasClient;
  final bool mobileSearchOpen;
  final MobileHome activeHome;
  final ValueChanged<MobileHome> onMobileHome;
  final VoidCallback onToggleMobileSearch;
  final VoidCallback onHandleMobileNew;
  final TextEditingController searchCtl;
  final FocusNode searchFocus;
  final String filterQuery;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const SidebarMobileBar({
    super.key,
    required this.hasClient,
    required this.mobileSearchOpen,
    required this.activeHome,
    required this.onMobileHome,
    required this.onToggleMobileSearch,
    required this.onHandleMobileNew,
    required this.searchCtl,
    required this.searchFocus,
    required this.filterQuery,
    required this.searchHint,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kMobileBarRadius);
    final searching = mobileSearchOpen && hasClient;
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 6, M.gutter, 8),
      child: AnimatedSwitcher(
        duration: Motion.fast,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        child: searching
            ? _mobileBarPill(radius, key: 'search', child: _mobileSearchRow())
            : _mobileBarPill(radius,
                key: 'bar', child: _mobileBarRow(hasClient)),
      ),
    );
  }

  Widget _mobileBarPill(BorderRadius radius,
      {required String key, required Widget child}) {
    return Container(
      key: ValueKey(key),
      height: kMobileBarHeight,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: AppColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget _mobileBarRow(bool hasClient) {
    return Row(
      children: [
        const SizedBox(width: 4),
        for (final h in MobileHome.values)
          Expanded(
            child: _mobileBarDest(h, activeHome == h, true),
          ),
        const SizedBox(width: 2),
        Container(width: 1, height: 20, color: AppColors.border),
        const SizedBox(width: 2),
        Expanded(
          child: _mobileBarAction('search', 'Search',
              onTap: hasClient ? onToggleMobileSearch : null),
        ),
        Expanded(
          child: _mobileBarAction('plus', 'New',
              onTap: hasClient ? onHandleMobileNew : null),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _mobileSearchRow() {
    return Row(children: [
      const SizedBox(width: 12),
      AppIcon('search', size: 16, color: AppColors.fg3),
      const SizedBox(width: 9),
      Expanded(
        child: TextField(
          controller: searchCtl,
          focusNode: searchFocus,
          autofocus: true,
          cursorColor: AppColors.accent,
          textInputAction: TextInputAction.search,
          onChanged: onSearchChanged,
          style: sans(15, color: AppColors.fg1),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: searchHint,
            hintStyle: sans(15, color: AppColors.fg4),
          ),
        ),
      ),
      if (filterQuery.isNotEmpty)
        IconBtn('x',
            size: 32, iconSize: 14, tooltip: 'Clear', onTap: onClearSearch),
      IconBtn('arrow-down',
          size: 36,
          iconSize: 16,
          tooltip: 'Close search',
          onTap: onToggleMobileSearch),
      const SizedBox(width: 4),
    ]);
  }

  Widget _mobileBarDest(MobileHome h, bool active, bool enabled) {
    return Tooltip(
      message: h.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobileBarRadius - 4),
          onTap: enabled
              ? () {
                  if (activeHome != h) {
                    onMobileHome(h);
                  }
                }
              : null,
          child: SizedBox(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(h.icon,
                      size: 23, color: active ? AppColors.fg1 : AppColors.fg3),
                  const SizedBox(height: 2),
                  Text(h.label,
                      style: caps(10,
                          color: active ? AppColors.fg1 : AppColors.fg3,
                          spacing: 0.35)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileBarAction(String icon, String tooltip, {VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobileBarRadius - 4),
          onTap: onTap,
          child: SizedBox(
            height: kMobileBarHeight,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(icon,
                      size: 23,
                      color: onTap == null ? AppColors.fg4 : AppColors.fg2),
                  const SizedBox(height: 2),
                  Text(tooltip,
                      style: caps(10,
                          color: onTap == null ? AppColors.fg4 : AppColors.fg2,
                          spacing: 0.35)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSidebarMachinesPicker(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<Instance> instances,
  required Instance? active,
  required Map<String, bool> health,
  required ValueChanged<Instance> onSelect,
  required VoidCallback onAdd,
  required void Function(Instance) onManage,
  required VoidCallback onRefreshHealth,
}) async {
  onRefreshHealth();
  final content = MachineList(
    instances: instances,
    active: active,
    health: health,
    onSelect: onSelect,
    onAdd: onAdd,
    onManage: onManage,
  );
  if (kMobile) {
    await showAppSheet(
      context,
      title: 'Machines',
      child: content,
    );
    return;
  }
  final box = anchorKey.currentContext!.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'machines',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.press,
    pageBuilder: (_, __, ___) => Stack(children: [
      Positioned(
        left: origin.dx + 10,
        top: origin.dy + box.size.height + 4,
        width: box.size.width - 20,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.md),
          child: Material(
            color: AppColors.glassSurface,
            elevation: 12,
            shadowColor: AppColors.scrim,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(child: content),
              ),
            ),
          ),
        ),
      ),
    ]),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.enter);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class SidebarKeepAlivePage extends StatefulWidget {
  final Widget child;
  const SidebarKeepAlivePage({super.key, required this.child});

  @override
  State<SidebarKeepAlivePage> createState() => _SidebarKeepAlivePageState();
}

class _SidebarKeepAlivePageState extends State<SidebarKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
