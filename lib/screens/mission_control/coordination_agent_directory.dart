import 'package:flutter/material.dart';

import '../../api.dart';
import '../../desktop_layout.dart';
import '../../models.dart';
import '../../crew_status.dart';
import '../../crew_widgets.dart';
import 'dart:async';
import '../../panel.dart';
import '../../theme.dart';
import '../../widgets.dart';

import '../create_agent_form.dart';
import 'coordination_agent_detail.dart';
import '../../platform.dart';
import '../../pull_refresh.dart';
import '../../mochi.dart';

class CoordinationAgentDirectory extends StatefulWidget {
  const CoordinationAgentDirectory({
    super.key,
    required this.client,
    this.embedded = false,
    this.refreshSignal,
  });

  final DaemonClient client;

  /// When embedded in the hub, suppress our own Scaffold/AppBar and let the
  /// host supply chrome.
  final bool embedded;

  /// Bumped by the host to request a refetch.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<CoordinationAgentDirectory> createState() =>
      _CoordinationAgentDirectoryState();
}

class _CoordinationAgentDirectoryState
    extends State<CoordinationAgentDirectory> {
  List<CoordinationAgent> agents = const [];
  String? error;
  bool loading = true;
  String? _selectedId;
  List<SessionInfo> sessions = const [];
  Timer? _poll;

  Future<void> _loadSessions() async {
    try {
      final l = await widget.client.sessions();
      if (mounted) setState(() => sessions = l);
    } catch (_) {}
  }

  List<CrewEntry> get _crew => deriveCrew(agents, sessions);

  @override
  void initState() {
    super.initState();
    refresh();
    _loadSessions();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _loadSessions());
    widget.refreshSignal?.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    refresh();
    _loadSessions();
  }

  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    List<CoordinationAgent>? next;
    String? failure;
    try {
      // Mission Control has its own pinned chat, so it is not one of the agents
      // offered here — this list is the workers a user dispatches to.
      next = (await widget.client.coordinationAgents())
          .where((a) => !a.isMissionControl)
          .toList();
    } catch (e) {
      failure = '$e';
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      if (next != null) agents = next;
      error = failure;
      loading = false;
    });
  }

  Future<void> _awaitNewAgent() async {
    final before = agents.map((a) => a.id).toSet();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final latest = await widget.client.coordinationAgents();
        if (latest.any((a) => !a.isMissionControl && !before.contains(a.id))) {
          await refresh();
          if (mounted) toast(context, 'New agent is ready');
          return;
        }
      } catch (_) {}
    }
    if (mounted) {
      toast(context, 'Still building — check Mission Control for progress.');
    }
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context,
      title: 'Create agent',
      child: CreateAgentForm(client: widget.client),
    );
    if (created != true || !mounted) return;
    toast(context, 'Building agent — it appears here when ready');
    await _awaitNewAgent();
  }

  static const _wideMin = 900.0;

  @override
  Widget build(BuildContext context) {
    if (kMobile) return _stacked(context);
    return LayoutBuilder(
      builder: (context, c) =>
          c.maxWidth >= _wideMin ? _wide() : _stacked(context),
    );
  }

  Widget _wide() {
    CoordinationAgent? selected;
    for (final a in agents) {
      if (a.id == _selectedId) selected = a;
    }
    Widget? empty;
    if (loading) {
      empty = Center(child: Spinner(size: 20, color: AppColors.fg3));
    } else if (error != null) {
      empty = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Could not load agents', style: sans(13, color: AppColors.fg2)),
        const SizedBox(height: 10),
        Btn('Retry', small: true, onTap: refresh),
      ]);
    } else {
      empty = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Build your agent team',
            style: sans(13, weight: W.label, color: AppColors.fg2)),
        const SizedBox(height: 6),
        Text(
            'Create a specialised agent with its own identity and workspace-independent sessions.',
            textAlign: TextAlign.center,
            style: sans(12.5, color: AppColors.fg3, height: 1.45)),
      ]);
    }
    return Material(
      color: AppColors.windowBg,
      child: MasterDetail(
        master: MasterPane(
          title: 'Agents',
          actions: [HeaderAction('Build agent', onTap: _create)],
          empty: empty,
          children: loading || error != null
              ? const []
              : [
                  for (final a in agents)
                    ListRow(
                      key: ValueKey('agent-${a.id}'),
                      title: a.displayName,
                      subtitle: a.role.trim().isEmpty
                          ? '@${a.handle}'
                          : a.role.trim(),
                      selected: a.id == _selectedId,
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: crewColor(_crew
                              .firstWhere((e) => e.agent.id == a.id)
                              .state),
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () => setState(() => _selectedId = a.id),
                    ),
                ],
        ),
        detail: selected == null
            ? (agents.isEmpty
                ? const DetailEmpty('Select an agent')
                : CrewBoard(
                    entries: _crew,
                    client: widget.client,
                    padding:
                        const EdgeInsets.fromLTRB(S.s32, S.s24, S.s32, S.s32),
                    onOpen: (a) => setState(() => _selectedId = a.id)))
            : _AgentPane(
                key: ValueKey('agent-pane-${selected.id}'),
                agent: selected,
                client: widget.client,
              ),
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    final body = PullToRefresh(
      onRefresh: refresh,
      child: loading
          ? const PageLoader()
          : error != null
              ? _MessageState(
                  title: 'Could not load agents',
                  message: error!,
                  action: Btn('Retry', onTap: refresh),
                )
              : agents.isEmpty
                  ? _MessageState(
                      icon: 'users',
                      title: 'Build your agent team',
                      message:
                          'Create a specialized agent with its own identity and workspace-independent sessions.',
                      action: Btn('Create your first agent',
                          icon: 'add', onTap: _create),
                    )
                  : CrewBoard(
                      entries: _crew,
                      client: widget.client,
                      onOpen: (a) => presentScreen(
                        context,
                        style: PanelStyle.drawer,
                        purpose: ShellPanelPurpose.agent,
                        panelId: a.id,
                        originClient: widget.client,
                        builder: (_, __) => CoordinationAgentDetail(
                            agent: a, client: widget.client),
                      ),
                    ),
    );

    // Embedded in the hub: no app bar (the host owns chrome), but keep the
    // create affordance where users expect it via a transparent nested Scaffold
    // — a FAB otherwise has nowhere to live without nesting one anyway.
    if (widget.embedded) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: AppIcon('plus', size: 18, color: AppColors.accentFg),
          label: const Text('Build agent'),
        ),
        body: body,
      );
    }
    return Scaffold(
      appBar: ShellPanelRoot.inPanel(context)
          ? null
          : AppBar(
              title: const Text('Agents'),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: AppIcon('plus', size: 18, color: AppColors.accentFg),
        label: const Text('Create agent'),
      ),
      body: body,
    );
  }
}

class _AgentPane extends StatelessWidget {
  const _AgentPane({super.key, required this.agent, required this.client});
  final CoordinationAgent agent;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    final status = agent.status.trim().isEmpty
        ? (agent.available ? 'Online' : 'Offline')
        : agent.status.trim()[0].toUpperCase() +
            agent.status.trim().substring(1);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s40, S.s32, S.s40, S.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AgentMochi(agent.id, size: 40),
                    const SizedBox(width: S.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(agent.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(20,
                                  weight: W.strong,
                                  spacing: -0.2,
                                  color: AppColors.fg1)),
                          const SizedBox(height: S.s4),
                          Text(
                            [
                              '@${agent.handle}',
                              if (agent.role.trim().isNotEmpty)
                                agent.role.trim(),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: S.s12),
                    Tag(status,
                        tone: agent.available ? Tone.ok : Tone.neutral,
                        dot: true),
                  ]),
                  if (agent.capabilities.isNotEmpty) ...[
                    const SizedBox(height: S.s16),
                    Wrap(
                      spacing: S.s6,
                      runSpacing: S.s6,
                      children: [
                        for (final cap in agent.capabilities)
                          Tag(cap, mono: true),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.line),
            Expanded(
              child: CoordinationAgentDetail(
                agent: agent,
                client: client,
                embedded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {this.icon = 'alert-circle',
      required this.title,
      required this.message,
      required this.action});
  final String icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 72, 28, 120),
        children: [
          AppIcon(icon, size: 48, color: AppColors.fg3),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: sans(kMobile ? 20 : 17,
                  weight: W.label, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3, height: 1.45)),
          const SizedBox(height: 22),
          Center(child: action),
        ],
      );
}
