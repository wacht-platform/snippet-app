import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'create_agent_form.dart';
import 'shell_nav.dart';

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

  /// True from submitting a build prompt until the new agent appears.
  ///
  /// `/agents/build` is asynchronous (202): the daemon hands the prompt to the
  /// Mission Control session, which researches and registers the agent. So
  /// there is no id to await — the only honest signal is the agent showing up
  /// in a later list, which is what [_awaitNewAgent] polls for.
  bool busy = false;

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

  /// Open the "describe an agent" popover, anchored under its button.
  ///
  /// A popover rather than a dialog: this is one field that belongs to the "+"
  /// you just pressed, and on desktop it should appear beside the panel instead
  /// of dimming the whole window. `showGeneralDialog` with a transparent barrier
  /// is the same mechanism the shell's goal popover uses.
  Future<void> _openCreateAgent(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox?;
    // A 300px panel cannot host a 340px popover, so on desktop it opens to the
    // RIGHT of the button (where the pane's content is) and falls back to
    // left-aligned-under only if there is no room there.
    const width = 340.0;
    final screen = MediaQuery.sizeOf(context);
    var left = 24.0;
    var top = 96.0;
    if (box != null) {
      final origin = box.localToGlobal(Offset.zero);
      final rightOfButton = origin.dx + box.size.width + 8;
      left = rightOfButton + width <= screen.width - 12
          ? rightOfButton
          : (origin.dx + box.size.width - width).clamp(
              12.0, (screen.width - width - 12).clamp(12.0, double.infinity));
      top = origin.dy
          .clamp(12.0, (screen.height - 320).clamp(12.0, double.infinity));
    }
    final submitted = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'create agent',
      // Transparent: a popover beside the panel, not a modal over the app.
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            elevation: 12,
            shadowColor: Colors.black87,
            // The SHARED form, the same one Mission Control's directory uses. It
            // submits itself and pops `true`, so this host only waits for the
            // agent to appear — a second local copy is how the two drifted.
            child: CreateAgentForm(client: widget.client),
          ),
        ),
      ]),
    );
    if (!mounted || submitted != true) return;
    toast(context, 'Building agent — researching your description…');
    await _awaitNewAgent();
  }

  /// Poll until an agent appears that was not in the list at the start.
  ///
  /// `/agents/build` returns 202 with no id: the prompt is handed to the Mission
  /// Control session, which researches and registers the agent on its own
  /// schedule. So the completion signal is the agent EXISTING, not a response —
  /// and the list refreshes on every pass, so the row appears as soon as it is
  /// registered rather than only at the end.
  ///
  /// Bounded so a failed build cannot spin forever; MC's own session shows what
  /// went wrong.
  Future<void> _awaitNewAgent() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final before = agents.map((a) => a.id).toSet();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        try {
          final latest = await widget.client.coordinationAgents();
          if (!mounted) return;
          if (latest.any((a) => !before.contains(a.id))) {
            await refresh();
            if (mounted) toast(context, 'New agent is ready');
            return;
          }
          // Keep the list live while the build runs.
          setState(() => agents = latest);
        } catch (_) {
          // A transient failure mid-poll is not fatal; keep waiting.
        }
      }
      if (mounted) {
        toast(context, 'Still building — check Mission Control for progress.',
            danger: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
          // The SAME section header every sibling panel uses.
          //
          // This panel drew its own 15px title while Terminals, Git Diff and the
          // file tree all render the shared `ShellSectionHeader` (12px uppercase),
          // which is why the agents panel read as heavier than the rest of the
          // rail. The count is gone from here deliberately: the two group
          // headings below already carry "Active now N" / "Idle N", so it was
          // saying the same thing twice.
          if (!kMobile)
            ShellSectionHeader(
              label: 'Agents',
              actions: [
                // `Builder` so the popover anchors to THIS button — the context's
                // render object is the button's box (same mechanism the file
                // tree's actions use).
                Builder(
                  builder: (ctx) => ShellSectionAction(
                    icon: 'plus',
                    tooltip: 'Create agent',
                    onTap: busy ? null : () => _openCreateAgent(ctx),
                  ),
                ),
                ShellSectionAction(
                  icon: 'refresh',
                  tooltip: 'Refresh',
                  onTap: busy ? null : refresh,
                ),
              ],
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(M.gutter, 12, M.gutter - 6, 8),
              child: Row(children: [
                Text('Agents',
                    style: sans(M.sectionTitle,
                        weight: W.label, color: AppColors.fg1)),
                const Spacer(),
                Builder(
                  builder: (ctx) => IconBtn('plus',
                      size: M.minTarget,
                      iconSize: 18,
                      tooltip: 'Create agent',
                      onTap: busy ? null : () => _openCreateAgent(ctx)),
                ),
                IconBtn('refresh',
                    size: M.minTarget,
                    iconSize: 18,
                    tooltip: 'Refresh',
                    onTap: busy ? null : refresh),
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
        // Desktop: list inset 8 + kNavPadH 12 = content x20, the same x the
        // shared ShellSectionHeader and every sibling panel's rows land on.
        // It was 8 total (x16), which is what read as inset differently from
        // the rest of the rail. Mobile keeps its existing 16 unchanged.
        padding: EdgeInsets.fromLTRB(
            kMobile ? 8 : kNavPadH, 6, kMobile ? 8 : kNavPadH, 6),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: sans(kMobile ? 12 : 10.5,
                  weight: W.title,
                  color: accent ? AppColors.accent : AppColors.fg4,
                  spacing: 0.6)),
          const SizedBox(width: 6),
          Text('$count',
              style: sans(kMobile ? 12 : 10.5, color: AppColors.fg4)),
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
          // Same alignment as _GroupLabel: x20 on desktop (list 8 + 12), so the
          // avatar lines up under the header's own inset instead of sitting
          // 4px left of it. Mobile unchanged.
          padding: EdgeInsets.symmetric(
              horizontal: kMobile ? 8 : kNavPadH, vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 13,
              backgroundColor:
                  isActive ? AppColors.accentBg : AppColors.surface2,
              foregroundColor: isActive ? AppColors.accent : AppColors.fg3,
              child: Text(initial,
                  style: sans(kMobile ? 13 : 11.5,
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
                      // W.body (400), matching the canonical `ShellNavRow` —
                      // which is `selected ? W.label : W.body`. At W.label every
                      // agent name rendered heavier than every session row
                      // beside it, which is most of why this panel read "bold".
                      style: sans(kMobile ? M.rowTitle : 13,
                          weight: W.body, color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? _sessionSummary(sessions) : agent.role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? M.meta : 11.5,
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
