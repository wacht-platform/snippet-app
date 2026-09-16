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
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        // Mission Control is excluded: it has its own pinned chat, so it is not
        // one of the workers this panel lists.
        agents = all.where((a) => !a.isMissionControl).toList();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

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
      transitionDuration: Motion.quick,
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
          // Filtered the SAME way `agents` is. `before` comes from the filtered
          // list, so an unfiltered poll would report Mission Control as a
          // brand-new agent on every check and claim a build had finished.
          final latest = (await widget.client.coordinationAgents())
              .where((a) => !a.isMissionControl)
              .toList();
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

    final active = agents.where((a) => a.available).toList();
    final paused = agents.where((a) => !a.available).toList();
    Widget group(String label, List<CoordinationAgent> members) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(M.gutter, 18, M.gutter, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(label, style: display(M.sectionTitle, color: AppColors.fg1)),
                  const SizedBox(width: 8),
                  Text('${members.length}', style: mono(M.meta, color: AppColors.fg3)),
                ],
              ),
            ),
            for (final a in members)
              _AgentSidebarRow(
                agent: a,
                onTap: widget.onOpenAgent == null ? null : () => widget.onOpenAgent!(a),
              ),
          ],
        );

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
                    padding: EdgeInsets.fromLTRB(kMobile ? 0 : 8, 0, kMobile ? 0 : 8, 18),
                    children: [
                      if (active.isNotEmpty) group('Available now', active),
                      if (paused.isNotEmpty) group('Paused', paused),
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
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}


/// One agent row: avatar, name, and either the sessions it holds or its role.
class _AgentSidebarRow extends StatelessWidget {
  const _AgentSidebarRow({
    required this.agent,
    this.onTap,
  });

  final CoordinationAgent agent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

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
              backgroundColor: AppColors.surface2,
              foregroundColor: AppColors.fg3,
              child: Text(initial,
                  style: sans(kMobile ? 13 : 11,
                      weight: W.title, color: AppColors.fg3)),
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
                    agent.role,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? M.meta : 11,
                        color: AppColors.fg4, height: 1.35),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

}
