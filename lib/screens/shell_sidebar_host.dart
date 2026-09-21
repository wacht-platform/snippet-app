import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../shells.dart' show GlobalShell;
import '../theme.dart';
import 'agents_sidebar_panel.dart';
import 'file_tree_sidebar_panel.dart';
import 'git.dart';
import 'git_diff_sidebar_panel.dart';
import 'session.dart' show TerminalInfo;
import 'settings_panel.dart' show SettingsPage;
import 'shell_models.dart';
import 'shell_rail.dart' show ShellSection;
import 'sidebar.dart';
import 'terminals_sidebar_panel.dart';

/// Routes between sidebar panels depending on the active [ShellSection] and state.
class ShellSidebarHost extends StatelessWidget {
  const ShellSidebarHost({
    super.key,
    required this.effectiveSection,
    required this.shells,
    required this.focusShellId,
    required this.activeWorkspaceFolder,
    required this.client,
    required this.activeInstance,
    required this.activeTab,
    required this.sidebarGit,
    required this.onCloseGit,
    required this.onNewTerminal,
    required this.onOpenTerminal,
    required this.onCloseTerminal,
    required this.onOpenRightAgent,
    required this.onOpenSession,
    required this.onOpenDiff,
    required this.onOpenFile,
    required this.instances,
    required this.selectedSessionId,
    required this.sessions,
    required this.sessionsLoading,
    required this.sessionsError,
    required this.onRefreshSessions,
    required this.onSessionAction,
    required this.onNewSession,
    required this.onSelectInstance,
    required this.onOpenMissionControl,
    required this.onAddInstance,
    required this.onRenameInstance,
    required this.onRemoveInstance,
    required this.onSessionDeleted,
    required this.health,
    required this.onRefreshHealth,
    required this.mobileHome,
    required this.onMobileHome,
    required this.mobileSettingsSection,
    required this.onSettingsSection,
    required this.mobileAgent,
    required this.onMobileAgent,
    this.topInset = true,
    this.onAfterPick,
    this.onSettingsClose,
  });

  final ShellSection effectiveSection;
  final List<GlobalShell> shells;
  final String? focusShellId;
  final String? activeWorkspaceFolder;
  final DaemonClient? client;
  final Instance? activeInstance;
  final ShellTab? activeTab;
  final bool sidebarGit;
  final VoidCallback onCloseGit;
  final VoidCallback onNewTerminal;
  final ValueChanged<int> onOpenTerminal;
  final ValueChanged<String> onCloseTerminal;
  final ValueChanged<CoordinationAgent> onOpenRightAgent;
  final void Function(String id, String title, String? profile) onOpenSession;
  final ValueChanged<GitFile> onOpenDiff;
  final void Function(String path, String name) onOpenFile;

  // Sidebar props:
  final bool topInset;
  final VoidCallback? onAfterPick;
  final List<Instance> instances;
  final String? selectedSessionId;
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final String? sessionsError;
  final VoidCallback onRefreshSessions;
  final void Function(String action, [String? extra]) onSessionAction;
  final VoidCallback onNewSession;
  final ValueChanged<Instance> onSelectInstance;
  final VoidCallback onOpenMissionControl;
  final VoidCallback onAddInstance;
  final void Function(Instance inst, String name) onRenameInstance;
  final ValueChanged<Instance> onRemoveInstance;
  final ValueChanged<String> onSessionDeleted;
  final Map<String, bool> health;
  final VoidCallback onRefreshHealth;
  final MobileHome mobileHome;
  final ValueChanged<MobileHome> onMobileHome;
  final SettingsPage? mobileSettingsSection;
  final ValueChanged<SettingsPage?> onSettingsSection;
  final CoordinationAgent? mobileAgent;
  final ValueChanged<CoordinationAgent?> onMobileAgent;
  final VoidCallback? onSettingsClose;

  @override
  Widget build(BuildContext context) {
    if (effectiveSection == ShellSection.terminal) {
      return TerminalsSidebarPanel(
        workspacePath: activeWorkspaceFolder ?? '',
        terminals: [
          for (final s in shells)
            TerminalInfo(
              id: s.id,
              title: s.title,
              alive: s.alive,
              live: s.live,
            ),
        ],
        focus: shells.indexWhere((s) => s.id == focusShellId),
        onNewTerminal: onNewTerminal,
        onOpenTerminal: (idx) {
          if (idx < 0 || idx >= shells.length) return;
          onOpenTerminal(idx);
        },
        onCloseTerminal: onCloseTerminal,
      );
    }

    if (effectiveSection == ShellSection.agents) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(
              message: 'Add a machine to see its agents.')
          : AgentsSidebarPanel(
              client: c,
              onOpenAgent: onOpenRightAgent,
              onOpenSession: (id, title) => onOpenSession(id, title, null),
              onOpenMissionControl: onOpenMissionControl,
            );
    }

    if (effectiveSection == ShellSection.git) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(message: 'Add a machine to see Git diff.')
          : GitDiffSidebarPanel(
              client: c,
              workspacePath: activeWorkspaceFolder ?? '',
              sessionId: activeTab?.sessionId,
              onOpenDiff: onOpenDiff,
            );
    }

    if (effectiveSection == ShellSection.files) {
      final c = client;
      return c == null
          ? const SidebarUnavailable(
              message: 'Add a machine to browse its files.')
          : FileTreeSidebarPanel(
              client: c,
              workspacePath: activeWorkspaceFolder ?? '',
              onOpenFile: onOpenFile,
            );
    }

    final tab = activeTab;
    if (sidebarGit && tab != null && !tab.isFile) {
      final path = tab.filePath;
      final slash = path?.lastIndexOf('/') ?? -1;
      final folder =
          path != null && slash > 0 ? path.substring(0, slash) : null;
      return Container(
        color: AppColors.surface1,
        child: GitScreen(
          client: tab.client,
          sessionId: tab.sessionId ?? '',
          folder: folder,
          embedded: true,
          onClose: onCloseGit,
        ),
      );
    }

    return Sidebar(
      topInset: topInset,
      instances: instances,
      active: activeInstance,
      client: client,
      selectedSessionId: kMobile ? null : selectedSessionId,
      sessions: sessions,
      sessionsLoading: sessionsLoading,
      sessionsError: sessionsError,
      onRefreshSessions: onRefreshSessions,
      onSessionAction: onSessionAction,
      onNewSession: () {
        onNewSession();
      },
      onSelectInstance: onSelectInstance,
      onOpenMissionControl: () {
        onOpenMissionControl();
        onAfterPick?.call();
      },
      onOpenSession: (id, title, profile) {
        onOpenSession(id, title, profile);
        onAfterPick?.call();
      },
      onAddInstance: onAddInstance,
      onRenameInstance: onRenameInstance,
      onRemoveInstance: onRemoveInstance,
      onSessionDeleted: onSessionDeleted,
      health: health,
      onRefreshHealth: onRefreshHealth,
      mobileHome: mobileHome,
      onMobileHome: onMobileHome,
      settingsSection: mobileSettingsSection,
      onSettingsSection: onSettingsSection,
      agent: mobileAgent,
      onAgent: onMobileAgent,
      onSettingsClose: onSettingsClose,
    );
  }
}

/// Fallback banner when a sidebar section requires an active machine connection.
class SidebarUnavailable extends StatelessWidget {
  const SidebarUnavailable({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Text(message, style: sans(12, color: AppColors.fg3, height: 1.5)),
    );
  }
}
