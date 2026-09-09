import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

class CoordinationAgentDirectory extends StatefulWidget {
  const CoordinationAgentDirectory({super.key, required this.client});
  final DaemonClient client;

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
  }

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
      child: _CreateAgentForm(client: widget.client),
    );
    if (created == true) await refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Agents'),
          actions: [
            IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('Create agent'),
        ),
        body: RefreshIndicator(
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
                          icon: Icons.groups_outlined,
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
        ),
      );
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
      leading: CircleAvatar(
        backgroundColor: AppColors.accentBg,
        foregroundColor: AppColors.accent,
        child: Text(initial),
      ),
      title: Text(agent.displayName,
          style: sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
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
      {this.icon = Icons.error_outline,
      required this.title,
      required this.message,
      required this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 72, 28, 120),
        children: [
          Icon(icon, size: 48, color: AppColors.fg3),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: sans(19, weight: FontWeight.w600, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3, height: 1.45)),
          const SizedBox(height: 22),
          Center(child: action),
        ],
      );
}

class _CreateAgentForm extends StatefulWidget {
  const _CreateAgentForm({required this.client});
  final DaemonClient client;

  @override
  State<_CreateAgentForm> createState() => _CreateAgentFormState();
}

class _CreateAgentFormState extends State<_CreateAgentForm> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _capabilities = TextEditingController();
  String _role = 'implementer';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _capabilities.dispose();
    super.dispose();
  }

  String _slug(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+'), '')
      .replaceAll(RegExp(r'-+$'), '');

  Future<void> _submit() async {
    final name = _name.text.trim();
    final handle = _handle.text.trim().toLowerCase();
    final id = _slug(handle.isEmpty ? name : handle);
    if (name.isEmpty || id.isEmpty) {
      setState(() => _error = 'Enter a display name and handle.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) {
      setState(() =>
          _error = 'Handle may contain lowercase letters, numbers, - or _.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capabilities = _capabilities.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      await widget.client.createCoordinationAgent(
        id: id,
        displayName: name,
        handle: handle.isEmpty ? id : handle,
        role: _role,
        capabilities: capabilities,
        maxConcurrentAssignments: 1,
        maxConcurrentSessions: 1,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Give this agent a durable identity. You can add tools and research later.',
              style: sans(13, color: AppColors.fg3, height: 1.4)),
          const SizedBox(height: 18),
          AppField(
              controller: _name,
              label: 'Display name',
              hint: 'e.g. Rust reviewer',
              autofocus: true),
          const SizedBox(height: 12),
          AppField(
              controller: _handle,
              label: 'Handle',
              hint: 'e.g. rust-reviewer',
              mono: true),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              'implementer',
              'reviewer',
              'tester',
              'researcher',
              'release',
              'coordinator'
            ]
                .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _role = value);
                  },
          ),
          const SizedBox(height: 12),
          AppField(
              controller: _capabilities,
              label: 'Capabilities',
              hint: 'rust, security, testing'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: sans(12, color: AppColors.danger)),
          ],
          const SizedBox(height: 20),
          Btn(_busy ? 'Creating…' : 'Create agent',
              full: true, disabled: _busy, icon: 'add', onTap: _submit),
        ]),
      );
}
