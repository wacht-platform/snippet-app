import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'create_agent_form.dart';
import 'mission_control.dart';
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
  const width = 340.0;
  final screen = MediaQuery.sizeOf(context);
  var left = 24.0;
  var top = 96.0;
  if (anchorContext != null) {
    final box = anchorContext.findRenderObject() as RenderBox?;
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
  }

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
                child: CreateAgentForm(client: client),
              ),
            ),
          ]),
        );
}

class AgentsSidebarPanel extends StatefulWidget {
  const AgentsSidebarPanel({
    super.key,
    required this.client,
    this.onOpenAgent,
    this.onOpenSession,
    this.onOpenMissionControl,
    this.trailingHeader,
    this.searchQuery,
    this.onSearchChanged,
  });

  final DaemonClient client;

  /// Called when a row is tapped. The host decides where detail goes.
  final void Function(CoordinationAgent agent)? onOpenAgent;

  /// Open an assigned session when tapped.
  final void Function(String sessionId, String title)? onOpenSession;

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
  final Set<String> _collapsed = {};

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

  bool _matchesSession(AgentAssignedSession s, String q) {
    if (q.isEmpty) return true;
    return s.title.toLowerCase().contains(q) ||
        s.conversation.toLowerCase().contains(q) ||
        s.id.toLowerCase().contains(q);
  }

  List<AgentAssignedSession> _sessionsForAgent(CoordinationAgent a, String q) {
    final all = a.assignedSessions
        .where((s) => !isInboxSession(s.id))
        .toList()
      ..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    if (q.isEmpty) return all;
    final direct = _agentMatchesMetadata(a, q);
    final matching = all.where((s) => _matchesSession(s, q)).toList();
    if (matching.isNotEmpty) return matching;
    if (direct) return all;
    return const [];
  }

  bool _matchesAgent(CoordinationAgent a, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (_agentMatchesMetadata(a, q)) return true;
    if (a.assignedSessions
        .any((s) => !isInboxSession(s.id) && _matchesSession(s, q))) {
      return true;
    }
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
            : SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.fg3)),
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
    final matchingAgents = q.isEmpty
        ? agents
        : agents.where((a) => _matchesAgent(a, q)).toList();

    final ordered = [...matchingAgents]..sort((a, b) {
        final aSessions = _sessionsForAgent(a, q);
        final bSessions = _sessionsForAgent(b, q);
        final aLast = aSessions.fold<int>(0,
            (latest, session) => session.lastActive > latest ? session.lastActive : latest);
        final bLast = bSessions.fold<int>(0,
            (latest, session) => session.lastActive > latest ? session.lastActive : latest);
        if (aLast != bLast) return bLast.compareTo(aLast);
        return a.displayName.compareTo(b.displayName);
      });

    if (kMobile) {
      final mobileChildren = <Widget>[];
      for (final agent in ordered) {
        final sessions = _sessionsForAgent(agent, q);
        final showSessions = q.isNotEmpty || !_collapsed.contains(agent.id);
        mobileChildren.add(Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _agentHeader(agent, count: sessions.length),
              if (showSessions && sessions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Material(
                  key: ValueKey('agent-sessions-${agent.id}'),
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(R.md),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final s in sessions) _sessionCard(agent, s),
                  ]),
                ),
              ],
            ],
          ),
        ));
      }

      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 28),
          children: [
            ...mobileChildren,
            if (ordered.isEmpty && mobileChildren.isEmpty)
              q.isNotEmpty ? const _EmptySearch() : _EmptyTeam(),
          ],
        ),
      );
    }

    final desktopChildren = <Widget>[];
    var first = true;
    for (final agent in ordered) {
      final sessions = _sessionsForAgent(agent, q);
      desktopChildren.add(
          _agentDesktopHeader(agent, first: first, count: sessions.length));
      first = false;
      final showSessions = q.isNotEmpty || !_collapsed.contains(agent.id);
      if (showSessions) {
        for (final s in sessions) {
          desktopChildren.add(_desktopSessionRow(agent, s));
        }
      }
    }

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
        border: Border.all(color: AppColors.border),
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
                hintStyle: sans(12, color: AppColors.fg4),
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


  Widget _agentHeader(CoordinationAgent agent, {int count = 0}) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final isSearching = effectiveQuery.isNotEmpty;
    final collapsed = isSearching ? false : _collapsed.contains(agent.id);
    final hasSessions = count > 0;
    void toggle() {
      if (hasSessions) {
        setState(() {
          if (collapsed) {
            _collapsed.remove(agent.id);
          } else {
            _collapsed.add(agent.id);
          }
        });
      }
    }
    void openAgent() {
      if (widget.onOpenAgent != null) {
        widget.onOpenAgent!(agent);
      } else {
        toggle();
      }
    }
    final chevron = collapsed ? 'chevron-right' : 'chevron-down';

    final activity = agent.available ? 'Available' : 'Unavailable';
    final metadata = [
      if (agent.role.trim().isNotEmpty) agent.role.trim(),
      activity,
    ].join(' · ');

    return Row(children: [
      Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: openAgent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                      style: sans(16, weight: W.label, color: AppColors.fg2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(16, weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 4),
                      Text(metadata,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(M.meta, color: AppColors.fg3)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      if (hasSessions)
        Tooltip(
          message: '${collapsed ? 'Expand' : 'Collapse'} sessions for $name',
          child: Semantics(
            button: true,
            label: '$count assigned sessions',
            expanded: !collapsed,
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: isSearching ? null : toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: M.minTarget, minHeight: M.minTarget),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 8),
                  Text('$count',
                      style: sans(M.meta, tabular: true, color: AppColors.fg3)),
                  const SizedBox(width: 6),
                  AppIcon(chevron, size: 14, color: AppColors.fg3),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _sessionCard(CoordinationAgent agent, AgentAssignedSession s) {
    final title = s.title.trim().isNotEmpty
        ? s.title.trim()
        : (s.conversation.trim().isNotEmpty
            ? s.conversation.trim()
            : 'Session');
    final isChat = s.conversation.trim().isNotEmpty ||
        s.id.contains('/conversations/');
    final icon = isChat ? 'chat-thread' : 'folder';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: () {
          if (widget.onOpenSession != null) {
            widget.onOpenSession!(s.id, s.title);
          } else if (widget.onOpenAgent != null) {
            widget.onOpenAgent!(agent);
          }
        },
        child: SizedBox(
          height: M.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIcon(icon, size: 16, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(M.rowTitle, color: AppColors.fg2),
                  ),
                ),
                if (s.lastActive > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    relativeTime(s.lastActive),
                    style: sans(M.meta, tabular: true, color: AppColors.fg3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentDesktopHeader(CoordinationAgent agent, {required bool first, int count = 0}) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final isSearching = effectiveQuery.isNotEmpty;
    final collapsed = isSearching ? false : _collapsed.contains(agent.id);
    final hasSessions = count > 0;
    final lastActive = agent.assignedSessions.fold<int>(
      0,
      (latest, s) => s.lastActive > latest ? s.lastActive : latest,
    );
    void toggle() {
      if (hasSessions) {
        setState(() {
          if (collapsed) {
            _collapsed.remove(agent.id);
          } else {
            _collapsed.add(agent.id);
          }
        });
      }
    }
    void openAgent() {
      if (widget.onOpenAgent != null) {
        widget.onOpenAgent!(agent);
      } else {
        toggle();
      }
    }
    final chevron = collapsed ? 'chevron-right' : 'chevron-down';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: openAgent,
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: EdgeInsets.fromLTRB(hasSessions ? 4 : kNavPadH, 0, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasSessions) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkResponse(
                      onTap: toggle,
                      radius: 12,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                        child: AppIcon(chevron, size: 12, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                AgentStateIcon(
                  active: agent.available && hasSessions,
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: sans(12, weight: W.body, color: AppColors.fg1),
                  ),
                ),
                if (collapsed && count > 0) ...[
                  InkWell(
                    onTap: toggle,
                    child: Text('$count',
                        style: sans(10, tabular: true, color: AppColors.fg3)),
                  ),
                  const SizedBox(width: 6),
                ],
                if (lastActive > 0)
                  Text(
                    relativeTime(lastActive),
                    style: sans(10, tabular: true, color: AppColors.fg3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop session row matching `_sessionRow` in desktop_shell.dart.
  Widget _desktopSessionRow(CoordinationAgent agent, AgentAssignedSession s) {
    final title = s.title.trim().isNotEmpty
        ? s.title.trim()
        : (s.conversation.trim().isNotEmpty
            ? s.conversation.trim()
            : 'Session');
    final isChat = s.conversation.trim().isNotEmpty ||
        s.id.contains('/conversations/');
    final icon = isChat ? 'chat-thread' : 'folder';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: () {
          if (widget.onOpenSession != null) {
            widget.onOpenSession!(s.id, s.title);
          } else if (widget.onOpenAgent != null) {
            widget.onOpenAgent!(agent);
          }
        },
        child: Container(
          height: 24,
          padding: const EdgeInsets.fromLTRB(26, 0, 6, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(icon, size: 12, color: AppColors.fg3),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11.5, color: AppColors.fg2),
                ),
              ),
              if (s.lastActive > 0)
                Text(
                  relativeTime(s.lastActive),
                  style: sans(10, tabular: true, color: AppColors.fg3),
                ),
            ],
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
        padding: EdgeInsets.fromLTRB(kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
        child: Text(
          'No agents match the search.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}

class _EmptyTeam extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
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
