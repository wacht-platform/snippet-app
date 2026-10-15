import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> showMochiColorPicker(
    BuildContext context, DaemonClient client, String agentId, String name) {
  return showAppSheet<void>(
    context,
    title: '$name colour',
    child: _Picker(client: client, agentId: agentId),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.client, required this.agentId});

  final DaemonClient client;
  final String agentId;

  Future<void> _pick(BuildContext context, Color? color) async {
    try {
      await client.setAgentColor(agentId, color == null ? null : colorHex(color));
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) toast(context, 'Could not change colour', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = mochiColorFor(agentId);
    final size = kMobile ? 44.0 : 36.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(kMobile ? M.gutter : 16, 4, kMobile ? M.gutter : 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, color) in mochiPalette)
                Tooltip(
                  message: label,
                  child: Material(
                    color: color == current ? AppColors.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _pick(context, color),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: MochiIcon(color: color, size: size),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (agentColors.value.containsKey(agentId)) ...[
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
}
