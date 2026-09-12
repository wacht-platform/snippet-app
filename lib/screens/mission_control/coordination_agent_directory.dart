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
      agents = await widget.client.coordinationAgents();
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
                      separatorBuilder: (_, __) =>
                          Divider(color: AppColors.border, height: 1),
                      itemBuilder: (_, index) => _AgentRow(agents[index]),
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

class _AgentRow extends StatelessWidget {
  const _AgentRow(this.agent);
  final CoordinationAgent agent;

  @override
  Widget build(BuildContext context) {
    final initial = agent.displayName.trim().isEmpty
        ? '?'
        : agent.displayName.trim()[0].toUpperCase();
    final detail = agent.capabilities.isEmpty
        ? '${agent.role} · @${agent.handle}'
        : '${agent.role} · ${agent.capabilities.take(3).join(' · ')}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      onTap: () => presentScreen(
        context,
        style: PanelStyle.drawer,
        builder: (_, __) => CoordinationAgentDetail(agent: agent),
      ),
      leading: CircleAvatar(
        backgroundColor: AppColors.accentBg,
        foregroundColor: AppColors.accent,
        child: Text(initial),
      ),
      title: Text(agent.displayName,
          style: sans(15, weight: FontWeight.w500, color: AppColors.fg1)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('@${agent.handle} · $detail',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(12.5, color: AppColors.fg3)),
      ),
      trailing: Text(agent.status,
          style: sans(12, weight: FontWeight.w500, color: AppColors.ok)),
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
              style: sans(19, weight: FontWeight.w500, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3, height: 1.45)),
          const SizedBox(height: 22),
          Center(child: action),
        ],
      );
}
