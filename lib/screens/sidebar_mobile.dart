import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_panel.dart';

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
