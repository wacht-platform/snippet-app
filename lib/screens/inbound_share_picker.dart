import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_models.dart';

/// Modal bottom sheet allowing the user to select which session or Mission Control receives incoming shared content.
Future<String?> showInboundSharePicker({
  required BuildContext context,
  required List<ShellTab> openTabs,
  required List<SessionInfo> restSessions,
  required String machineLabel,
}) {
  return showAppSheet<String>(
    context,
    title: 'Send to',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in openTabs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppIcon(tabIconKind(t),
                size: 18,
                color: t.isMissionControl ? AppColors.accent : AppColors.fg3),
            title: Text(
                t.isMissionControl
                    ? 'Mission Control'
                    : (t.title.trim().isEmpty ? '(untitled)' : t.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(16,
                    weight: t.isMissionControl
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: AppColors.fg1)),
            subtitle: Text(
                t.isMissionControl ? machineLabel : 'Open tab',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg3)),
            onTap: () => Navigator.pop(
                context, t.isMissionControl ? 'mission-control' : t.sessionId),
          ),
        if (openTabs.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppIcon('layers', size: 18, color: AppColors.accent),
            title: Text('Mission Control',
                style: sans(16, weight: W.label, color: AppColors.fg1)),
            subtitle: Text(machineLabel, style: sans(12, color: AppColors.fg3)),
            onTap: () => Navigator.pop(context, 'mission-control'),
          ),
        for (final s in restSessions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppIcon('terminal', size: 18, color: AppColors.fg3),
            title: Text(s.title.trim().isEmpty ? '(untitled)' : s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(16, color: AppColors.fg1)),
            subtitle: Text(
                s.displayAgentId == null || s.displayAgentId!.trim().isEmpty
                    ? (s.folder.trim().isEmpty ? 'session' : s.folder)
                    : '${s.folder.trim().isEmpty ? 'session' : s.folder} · ${s.displayAgentId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg3)),
            onTap: () => Navigator.pop(context, s.id),
          ),
      ],
    ),
  );
}
