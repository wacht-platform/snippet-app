import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> showMochiColorPicker(
    BuildContext context, DaemonClient client, String agentId, String name,
    {Offset? point}) {
  final picker = _Picker(client: client, agentId: agentId);
  if (kMobile) {
    return showAppSheet<void>(context, title: '$name look', child: picker);
  }
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox?;
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future.value();
  final screen = overlay.size;
  final at = point != null
      ? overlay.globalToLocal(point)
      : box != null
          ? box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay)
          : screen.center(Offset.zero);
  const w = _Picker.desktopWidth;
  final left = at.dx.clamp(8.0, screen.width - w - 8);
  final top = at.dy.clamp(8.0, screen.height - 140);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.fast,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: w,
        child: Material(
          color: AppColors.surface2,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border2),
          ),
          clipBehavior: Clip.antiAlias,
          child: picker,
        ),
      ),
    ]),
    transitionBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.96, end: 1.0).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.client, required this.agentId});

  static const desktopWidth = 4 * 40.0 + 3 * 2 + 16;

  final DaemonClient client;
  final String agentId;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  DaemonClient get client => widget.client;
  String get agentId => widget.agentId;

  Future<void> _pickShape(BuildContext context, MascotShape shape) async {
    final before = agentShapes.value[agentId];
    final value = shape == MascotShape.mochi ? null : shape.name;
    setRememberedAgentShape(agentId, value);
    try {
      await client.setAgentShape(agentId, value);
    } catch (_) {
      setRememberedAgentShape(agentId, before);
      if (context.mounted) toast(context, 'Could not change shape', danger: true);
    }
  }

  Future<void> _pick(BuildContext context, Color? color) async {
    final before = agentColors.value[agentId];
    final hex = color == null ? null : colorHex(color);
    setRememberedAgentColor(agentId, hex);
    Navigator.pop(context);
    try {
      await client.setAgentColor(agentId, hex);
    } catch (_) {
      setRememberedAgentColor(agentId, before);
      if (context.mounted) toast(context, 'Could not change colour', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = mochiColorFor(agentId);
    final custom = agentColors.value.containsKey(agentId);
    final cell = kMobile ? 56.0 : 40.0;
    final icon = kMobile ? 40.0 : 26.0;
    final grid = Wrap(
      spacing: kMobile ? 6 : 2,
      runSpacing: kMobile ? 6 : 2,
      children: [
        for (final (label, color) in mochiPalette)
          Tooltip(
            message: label,
            waitDuration: const Duration(milliseconds: 400),
            child: Material(
              color: color == current ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(kMobile ? 12 : 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(kMobile ? 12 : 8),
                hoverColor: AppColors.surface3,
                onTap: () => _pick(context, color),
                child: SizedBox.square(
                  dimension: cell,
                  child: Center(child: MochiIcon(color: color, size: icon)),
                ),
              ),
            ),
          ),
      ],
    );
    final shapeNow = mascotShapeFor(agentId);
    final shapes = Wrap(
      spacing: kMobile ? 6 : 2,
      runSpacing: kMobile ? 6 : 2,
      children: [
        for (final shape in MascotShape.values)
          Tooltip(
            message: shape.name[0].toUpperCase() + shape.name.substring(1),
            waitDuration: const Duration(milliseconds: 400),
            child: Material(
              color: shape == shapeNow ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(kMobile ? 12 : 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(kMobile ? 12 : 8),
                hoverColor: AppColors.surface3,
                onTap: () => _pickShape(context, shape),
                child: SizedBox.square(
                  dimension: cell,
                  child: Center(
                      child: MochiIcon(color: current, size: icon, shape: shape)),
                ),
              ),
            ),
          ),
      ],
    );
    if (kMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            shapes,
            const SizedBox(height: 12),
            grid,
            if (custom) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Btn('Use default', small: true, onTap: () => _pick(context, null)),
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          shapes,
          const SizedBox(height: 6),
          grid,
          if (custom) ...[
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _pick(context, null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text('Use default', style: sans(12, color: AppColors.fg3)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
