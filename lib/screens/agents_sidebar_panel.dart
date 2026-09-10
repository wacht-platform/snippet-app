import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// The agent team, as a sidebar panel — the reference app's "People with
/// access" slot, holding our agents instead of collaborators.
///
/// This is what the shell rail switches to, and it directly answers the two
/// questions the old UI could not: *which agents are active right now*, and
/// *what is each one working on*. Active state comes from live leases, so it
/// reflects reality rather than a stored flag.
class AgentsSidebarPanel extends StatefulWidget {
  const AgentsSidebarPanel({
    super.key,
    required this.client,
    this.onOpenAgent,
  });

  final DaemonClient client;

  /// Called when a row is tapped. The host decides where detail goes.
  final void Function(CoordinationAgent agent)? onOpenAgent;

  @override
  State<AgentsSidebarPanel> createState() => _AgentsSidebarPanelState();
}

class _AgentsSidebarPanelState extends State<AgentsSidebarPanel> {
  List<CoordinationAgent> agents = const [];

  /// session id → agent id, for the sessions that currently have a holder.
  Map<String, String> activeBySession = const {};
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      // Both in one pass so the active/idle split is internally consistent.
      final results = await Future.wait([
        widget.client.coordinationAgents(),
        widget.client.coordinationActiveLeases(),
      ]);
      if (!mounted) return;
      final leases = results[1] as List<CoordinationLease>;
      setState(() {
        agents = results[0] as List<CoordinationAgent>;
        activeBySession = {
          for (final l in leases) l.sessionId: l.agentId,
        };
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Sessions this agent currently holds. An agent can hold more than one.
  List<String> _sessionsFor(String agentId) => activeBySession.entries
      .where((e) => e.value == agentId)
      .map((e) => e.key)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (loading && agents.isEmpty) {
      return Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.fg3)),
      );
    }
    if (error != null && agents.isEmpty) {
      return Container(
        color: AppColors.bg,
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load agents',
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg2)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: refresh),
        ]),
      );
    }

    // Active first: the only rows that need attention.
    final active = <(CoordinationAgent, List<String>)>[];
    final idle = <(CoordinationAgent, List<String>)>[];
    for (final a in agents) {
      final sessions = _sessionsFor(a.id);
      (sessions.isEmpty ? idle : active).add((a, sessions));
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 10),
            child: Row(children: [
              Text('Agents',
                  style: sans(15, weight: W.title, color: AppColors.fg1)),
              const SizedBox(width: 8),
              Text('${agents.length}', style: sans(12, color: AppColors.fg4)),
              const Spacer(),
              IconBtn('refresh',
                  size: 28, iconSize: 15, tooltip: 'Refresh', onTap: refresh),
            ]),
          ),
          Expanded(
            child: agents.isEmpty
                ? _EmptyTeam()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                    children: [
                      if (active.isNotEmpty) ...[
                        _GroupLabel('Active now', active.length, accent: true),
                        for (final (a, sessions) in active)
                          _AgentSidebarRow(
                            agent: a,
                            sessions: sessions,
                            onTap: widget.onOpenAgent == null
                                ? null
                                : () => widget.onOpenAgent!(a),
                          ),
                      ],
                      if (idle.isNotEmpty) ...[
                        if (active.isNotEmpty) const SizedBox(height: 14),
                        _GroupLabel('Idle', idle.length),
                        for (final (a, _) in idle)
                          _AgentSidebarRow(
                            agent: a,
                            sessions: const [],
                            onTap: widget.onOpenAgent == null
                                ? null
                                : () => widget.onOpenAgent!(a),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTeam extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Text(
          'No agents yet.\n\nBuild one and it appears here, along with the '
          'sessions it is working in.',
          style: sans(12.5, color: AppColors.fg4, height: 1.5),
        ),
      );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, this.count, {this.accent = false});

  final String label;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: sans(10.5,
                  weight: W.title,
                  color: accent ? AppColors.accent : AppColors.fg4,
                  spacing: 0.6)),
          const SizedBox(width: 6),
          Text('$count', style: sans(10.5, color: AppColors.fg4)),
        ]),
      );
}

/// One agent row: avatar, name, and either the sessions it holds or its role.
class _AgentSidebarRow extends StatelessWidget {
  const _AgentSidebarRow({
    required this.agent,
    required this.sessions,
    this.onTap,
  });

  final CoordinationAgent agent;
  final List<String> sessions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final isActive = sessions.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 13,
              backgroundColor:
                  isActive ? AppColors.accentBg : AppColors.surface2,
              foregroundColor: isActive ? AppColors.accent : AppColors.fg3,
              child: Text(initial,
                  style: sans(11.5,
                      weight: W.title,
                      color: isActive ? AppColors.accent : AppColors.fg3)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: W.label, color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? _sessionSummary(sessions) : agent.role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5,
                        color: isActive ? AppColors.ok : AppColors.fg4,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// `snippet-service/…` — the tail of the session id is the readable part,
  /// since ids are workspace-relative paths.
  static String _sessionSummary(List<String> sessions) {
    if (sessions.length == 1) return _shortSession(sessions.first);
    return '${sessions.length} sessions';
  }

  static String _shortSession(String id) {
    final parts = id.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return id;
    if (parts.length == 1) return parts.first;
    // Keep the folder plus the file, dropping the middle of a long path.
    return '${parts.first}/…/${parts.last}';
  }
}
