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
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    final initial = agent.displayName.trim().isEmpty
        ? '?'
        : agent.displayName.trim()[0].toUpperCase();
    final isActive = agent.available;
    final statusColor = isActive ? AppColors.ok : AppColors.fg4;
    final statusText = agent.status.toUpperCase();

    void openDetail() {
      presentScreen(
        context,
        style: PanelStyle.drawer,
        builder: (_, __) =>
            CoordinationAgentDetail(agent: agent, client: client),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: openDetail,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          initial,
                          style: sans(16,
                              weight: FontWeight.w700,
                              color: AppColors.accent),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.surface1, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                agent.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(15,
                                    weight: FontWeight.w600,
                                    color: AppColors.fg1),
                              ),
                            ),
                            if (agent.role.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  agent.role.trim(),
                                  style: mono(9,
                                      weight: FontWeight.w600,
                                      color: AppColors.accent),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${agent.handle}',
                          style: mono(11, color: AppColors.fg3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: mono(10,
                              weight: FontWeight.w600,
                              spacing: 0.4,
                              color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (agent.capabilities.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cap in agent.capabilities)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          cap,
                          style: mono(10, color: AppColors.fg2),
                        ),
                      ),
                  ],
                ),
              ],
              if (agent.assignedSessions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface2.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Row(
                    children: [
                      AppIcon('folder', size: 13, color: AppColors.fg3),
                      const SizedBox(width: 6),
                      Text(
                        '${agent.assignedSessions.length} active ${agent.assignedSessions.length == 1 ? 'session' : 'sessions'}',
                        style: sans(11, color: AppColors.fg3),
                      ),
                      const Spacer(),
                      AppIcon('chevron-right', size: 13, color: AppColors.fg4),
                    ],
                  ),
                ),
              ],
            ],
          ),
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
