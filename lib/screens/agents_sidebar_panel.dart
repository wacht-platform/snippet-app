import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_card.dart';
import 'create_agent_form.dart';
import 'shell_nav.dart';

/// The agent team, as a sidebar panel — the reference app's "People with
/// access" slot, holding our agents instead of collaborators.
///
/// This is what the shell rail switches to, and it directly answers the two
/// questions the old UI could not: *which agents are active right now*, and
/// *what is each one working on*. Active state comes from live leases, so it
/// reflects reality rather than a stored flag.
/// Open the create-agent sheet (on mobile) or popover (on desktop).
Future<bool?> showCreateAgentDialog(
  BuildContext context,
  DaemonClient client, {
  BuildContext? anchorContext,
}) async {
  final box = anchorContext?.findRenderObject() as RenderBox?;
  final anchor = box == null
      ? const Rect.fromLTWH(16, 96, 0, 0)
      : box.localToGlobal(Offset.zero) & box.size;

  return kMobile
      ? await showAppSheet<bool>(
          context,
          title: 'Create agent',
          child: CreateAgentForm(client: client),
        )
      : await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'create agent',
          barrierColor: Colors.transparent,
          transitionDuration: Motion.quick,
          pageBuilder: (ctx, _, __) => SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: LayoutBuilder(builder: (context, constraints) {
                final origin = (context.findRenderObject() as RenderBox?)
                        ?.localToGlobal(Offset.zero) ??
                    Offset.zero;
                return CustomSingleChildLayout(
                  delegate: _CreateAgentPopoverLayout(anchor.shift(-origin)),
                  child: Material(
                    key: const ValueKey('create-agent-popover'),
                    color: AppColors.overlay,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.lg),
                        side: BorderSide(color: AppColors.line)),
                    clipBehavior: Clip.antiAlias,
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Create agent',
                              style: sans(kMobile ? 14 : 13,
                                  weight: W.label, color: AppColors.fg1)),
                          const SizedBox(height: 12),
                          CreateAgentForm(client: client),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
}

class _CreateAgentPopoverLayout extends SingleChildLayoutDelegate {
  const _CreateAgentPopoverLayout(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth.clamp(0, 340),
        maxWidth: constraints.maxWidth.clamp(0, 340),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + 8;
    final left = right + childSize.width <= size.width
        ? right
        : anchor.right - childSize.width;
    return Offset(
      left.clamp(0, size.width - childSize.width),
      anchor.top.clamp(0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_CreateAgentPopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class AgentsSidebarPanel extends StatefulWidget {
  const AgentsSidebarPanel({
    super.key,
    required this.client,
    this.onOpenAgent,
    this.onOpenMissionControl,
    this.trailingHeader,
    this.searchQuery,
    this.onSearchChanged,
  });

  final DaemonClient client;

  /// Called when a row is tapped. The host decides where detail goes.
  final void Function(CoordinationAgent agent)? onOpenAgent;

  /// Open Mission Control chat when tapped.
  final VoidCallback? onOpenMissionControl;

  /// Rendered in the top mobile header on the right (e.g. machine avatar switcher).
  final Widget? trailingHeader;

  /// External search query (e.g. from mobile bottom bar or screen header).
  final String? searchQuery;

  /// Notifies parent when local search text changes.
  final ValueChanged<String>? onSearchChanged;

  @override
  State<AgentsSidebarPanel> createState() => AgentsSidebarPanelState();
}

class AgentsSidebarPanelState extends State<AgentsSidebarPanel> {
  List<CoordinationAgent> agents = const [];

  String? error;
  bool loading = true;
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

  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchOpen = false;
  String _localQuery = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get effectiveQuery {
    if (widget.searchQuery != null) {
      return widget.searchQuery!.trim();
    }
    return _localQuery.trim();
  }

  bool _agentMatchesMetadata(CoordinationAgent a, String q) {
    if (q.isEmpty) return true;
    if (a.displayName.toLowerCase().contains(q)) return true;
    if (a.id.toLowerCase().contains(q)) return true;
    if (a.handle.toLowerCase().contains(q)) return true;
    if (a.role.toLowerCase().contains(q)) return true;
    if (a.capabilities.any((c) => c.toLowerCase().contains(q))) return true;
    return false;
  }

  /// Open the create agent modal/sheet.
  Future<void> openCreateAgent([BuildContext? btnCtx]) =>
      _openCreateAgent(btnCtx ?? context);

  Future<void> _openCreateAgent(BuildContext btnCtx) async {
    final submitted = await showCreateAgentDialog(context, widget.client,
        anchorContext: btnCtx);
    if (!mounted || submitted != true) return;
    toast(context, 'Building agent — researching your description…');
    await _awaitNewAgent();
  }

  /// Poll until an agent appears that was not in the list at the start.
  Future<void> _awaitNewAgent() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final before = agents.map((a) => a.id).toSet();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        try {
          final latest = (await widget.client.coordinationAgents())
              .where((a) => !a.isMissionControl)
              .toList();
          if (!mounted) return;
          if (latest.any((a) => !before.contains(a.id))) {
            await refresh();
            if (mounted) toast(context, 'New agent is ready');
            return;
          }
          setState(() => agents = latest);
        } catch (_) {}
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
        child: kMobile
            ? const AppLoading(label: 'Loading agents')
            : Spinner(size: 20, color: AppColors.fg3),
      );
    }
    if (error != null && agents.isEmpty) {
      if (kMobile) {
        return Material(
          color: AppColors.bg,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(M.gutter, 24, M.gutter, 32),
              children: [
                Text('Could not load agents',
                    style: sans(13, color: AppColors.fg2)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Btn('Retry', small: true, onTap: refresh),
                ),
              ],
            ),
          ),
        );
      }
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

    final createBtn = Builder(
      builder: (ctx) => ShellSectionAction(
        icon: 'plus',
        tooltip: 'Create agent',
        onTap: busy ? null : () => _openCreateAgent(ctx),
      ),
    );

    final q = effectiveQuery.toLowerCase();
    final ordered = (q.isEmpty
        ? [...agents]
        : agents.where((a) => _agentMatchesMetadata(a, q)).toList())
      ..sort((a, b) {
        if (a.available != b.available) return a.available ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });

    if (kMobile) {
      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 88),
          children: [
            for (final agent in ordered)
              AgentCard(
                key: ValueKey('agent-card-${agent.id}'),
                client: widget.client,
                agent: agent,
                onOpen: () => widget.onOpenAgent?.call(agent),
              ),
            if (ordered.isEmpty)
              q.isNotEmpty ? const _EmptySearch() : _EmptyTeam(),
          ],
        ),
      );
    }

    final desktopChildren = [
      for (final agent in ordered) _agentDesktopRow(agent),
    ];

    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellSectionHeader(
            label: 'Agents',
            actions: [
              ShellSectionAction(
                icon: 'search',
                tooltip: 'Search agents',
                onTap: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _searchCtl.clear();
                      _localQuery = '';
                      widget.onSearchChanged?.call('');
                    }
                  });
                  if (_searchOpen) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _searchFocus.requestFocus();
                    });
                  }
                },
              ),
              createBtn,
              ShellSectionAction(
                icon: 'refresh',
                tooltip: 'Refresh',
                onTap: busy ? null : refresh,
              ),
            ],
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _desktopSearchBar(),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
              children: [
                ...desktopChildren,
                if (ordered.isEmpty && desktopChildren.isEmpty)
                  q.isNotEmpty ? const _EmptySearch() : _EmptyTeam(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopSearchBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Row(
        children: [
          AppIcon('search', size: 13, color: AppColors.fg3),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              focusNode: _searchFocus,
              onChanged: (v) {
                setState(() => _localQuery = v);
                widget.onSearchChanged?.call(v);
              },
              style: sans(12, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search agents…',
                hintStyle: TS.meta(AppColors.fg4),
              ),
            ),
          ),
          if (_localQuery.isNotEmpty)
            IconBtn('x', size: 20, iconSize: 10, tooltip: 'Clear', onTap: () {
              _searchCtl.clear();
              setState(() => _localQuery = '');
              widget.onSearchChanged?.call('');
            }),
        ],
      ),
    );
  }

  Widget _agentDesktopRow(CoordinationAgent agent) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: widget.onOpenAgent == null
            ? null
            : () => widget.onOpenAgent!(agent),
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kNavPadH, 0, 6, 0),
            child: Row(children: [
              AgentStateIcon(active: agent.available, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.ui(AppColors.fg1)),
              ),
              if (agent.role.trim().isNotEmpty)
                Text(agent.role.trim(), style: sans(11, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
        child: Text(
          'No agents match the search.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}

class _EmptyTeam extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
        child: Text(
          'No agents yet.\n\nBuild one and it appears here, along with the '
          'sessions it is working in.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}

/// State icon for agents, visually distinct from the session chat bubble.
class AgentStateIcon extends StatelessWidget {
  final bool active;
  final double size;
  const AgentStateIcon({super.key, this.active = false, this.size = 17});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AppIcon(
          'agent',
          size: size - 1,
          color: active ? AppColors.accent : AppColors.fg3,
        ),
      ),
    );
  }
}
