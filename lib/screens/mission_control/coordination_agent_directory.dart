import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../panel.dart';
import '../../theme.dart';
import '../../widgets.dart';

import '../create_agent_form.dart';
import 'coordination_agent_detail.dart';

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

  @override
  void initState() {
    super.initState();
    refresh();
    widget.refreshSignal?.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() => refresh();

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      // Mission Control has its own pinned chat, so it is not one of the agents
      // offered here — this list is the workers a user dispatches to.
      agents = (await widget.client.coordinationAgents())
          .where((a) => !a.isMissionControl)
          .toList();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context,
      title: 'Create agent',
      child: CreateAgentForm(client: widget.client),
    );
    if (created == true) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: refresh,
      child: loading
          ? const Center(child: CircularProgressIndicator())
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
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: agents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: S.s8),
                      itemBuilder: (_, index) =>
                          _AgentCard(agents[index], widget.client),
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
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: AppIcon('refresh', size: 19, color: AppColors.fg2),
          ),
        ],
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

class _AgentCard extends StatelessWidget {
  const _AgentCard(this.agent, this.client);
  final CoordinationAgent agent;
  final DaemonClient client;

  @override
  Widget build(BuildContext context) {
    final sessions = agent.assignedSessions.length;
    return Material(
      color: AppColors.raised,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => presentScreen(
          context,
          style: PanelStyle.drawer,
          builder: (_, __) =>
              CoordinationAgentDetail(agent: agent, client: client),
        ),
        child: Padding(
          padding: const EdgeInsets.all(S.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Avatar(agent.displayName,
                    size: 40,
                    presence: agent.available,
                    ring: AppColors.raised),
                const SizedBox(width: S.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.rowTitle()),
                      const SizedBox(height: S.s2),
                      Text(
                        [
                          '@${agent.handle}',
                          if (agent.role.trim().isNotEmpty) agent.role.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.meta(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: S.s8),
                Tag(_statusLabel(agent.status),
                    tone: agent.available ? Tone.ok : Tone.neutral, dot: true),
              ]),
              if (agent.capabilities.isNotEmpty) ...[
                const SizedBox(height: S.s12),
                Wrap(
                  spacing: S.s6,
                  runSpacing: S.s6,
                  children: [
                    for (final cap in agent.capabilities) Tag(cap, mono: true),
                  ],
                ),
              ],
              if (sessions > 0) ...[
                const SizedBox(height: S.s12),
                Row(children: [
                  AppIcon('folder', size: 14, color: AppColors.fg3),
                  const SizedBox(width: S.s6),
                  Text(
                      '$sessions active ${sessions == 1 ? 'session' : 'sessions'}',
                      style: TS.meta()),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    final t = status.trim();
    if (t.isEmpty) return agent.available ? 'Online' : 'Offline';
    return t[0].toUpperCase() + t.substring(1);
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
              style: sans(20, weight: FontWeight.w500, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3, height: 1.45)),
          const SizedBox(height: 22),
          Center(child: action),
        ],
      );
}
