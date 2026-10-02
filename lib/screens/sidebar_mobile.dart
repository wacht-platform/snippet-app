import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        child: Text(message, style: TS.meta(), textAlign: TextAlign.center),
      );
}

/// The phone's tab bar: the four top-level places, in a raised pill, with the
/// New button in the middle. What New makes depends on the tab, which
/// [newLabel] names; on Settings it offers everything Settings can create.
///
/// The selected tab gets a surface step behind its icon rather than a colour,
/// so selection reads at a glance; the accent is kept for New, the one action.
class SidebarMobileBar extends StatelessWidget {
  final MobileHome activeHome;
  final ValueChanged<MobileHome> onMobileHome;
  final String newLabel;
  final VoidCallback? onNew;

  const SidebarMobileBar({
    super.key,
    required this.activeHome,
    required this.onMobileHome,
    this.newLabel = 'New',
    this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kMobileBarRadius);
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 8),
      child: Container(
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
        child: Material(
          color: AppColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              for (final (i, h) in MobileHome.values.indexed) ...[
                if (i == MobileHome.values.length ~/ 2 && onNew != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.s4),
                    child: _newButton(onNew!),
                  ),
                Expanded(child: _tab(h, activeHome == h)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _newButton(VoidCallback onTap) => Tooltip(
        message: newLabel,
        child: Semantics(
          button: true,
          label: newLabel,
          child: Material(
            color: AppColors.accentFill,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: AppIcon('plus', size: 22, color: AppColors.accentFg),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _tab(MobileHome h, bool active) {
    final ink = active ? AppColors.fg1 : AppColors.fg3;
    return Semantics(
      selected: active,
      button: true,
      label: h.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(kMobileBarRadius - 6),
        onTap: active
            ? null
            : () {
                HapticFeedback.selectionClick();
                onMobileHome(h);
              },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.enter,
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: active ? AppColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Center(child: AppIcon(h.icon, size: 21, color: ink)),
            ),
            const SizedBox(height: 3),
            Text(h.label,
                style: sans(11,
                    weight: active ? W.label : W.body, color: ink)),
          ],
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
          borderRadius: BorderRadius.circular(R.lg),
          child: Material(
            color: AppColors.overlay,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.4),
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
