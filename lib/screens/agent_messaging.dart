import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pick one agent from the directory.
///
/// Returns null when dismissed. Shared by the composer's recipient picker and
/// the "give work" sheet so both offer the same list, in the same order, with
/// the same description.
///
/// Mission Control is listed like any other agent: every session needs to be
/// able to reach the coordinator, so it is never filtered out. [currentAgentId]
/// marks the agent that IS this session, which is the one addressed by simply
/// sending to the chat.
Future<CoordinationAgent?> pickAgentId(
  BuildContext context,
  DaemonClient client, {
  String title = 'Select an agent',
  Set<String> exclude = const {},
  String? currentAgentId,
}) async {
  List<CoordinationAgent> agents;
  try {
    agents = await client.coordinationAgents();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return null;
  }
  final candidates = agents.where((a) => !exclude.contains(a.id)).toList();
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    toast(context, 'No agents available');
    return null;
  }

  // Longest-first by name so the rows read as a stable list.
  candidates.sort((a, b) => a.displayName.compareTo(b.displayName));

  final list = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final a in candidates)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(a.id),
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(children: [
                AppIcon('users',
                    size: 16,
                    color: a.available ? AppColors.accent : AppColors.fg4),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.displayName.trim().isEmpty ? a.id : a.displayName,
                        style:
                            sans(13.5, weight: W.label, color: AppColors.fg1),
                      ),
                      const SizedBox(height: 2),
                      Text('${a.handle} · ${a.role} · ${a.status}',
                          style: mono(10, color: AppColors.fg4)),
                    ],
                  ),
                ),
                // The agent that IS this session: sending to the chat already
                // reaches it, so naming it avoids a confused second path.
                if (currentAgentId != null && a.id == currentAgentId)
                  Text('this chat', style: mono(10, color: AppColors.fg4)),
              ]),
            ),
          ),
        ),
    ],
  );

  // Both platforms go through showAppSheet, which is already a dialog on
  // desktop and a bottom sheet on mobile. The picker only asks for more room
  // than the default, so the chrome stays in one place.
  return showAppSheet<String>(
    context,
    title: title,
    maxWidth: 420,
    maxHeight: 560,
    child: list,
  ).then(_resolvePicked(candidates));
}

/// Map a picked id back to its agent, or null when dismissed.
CoordinationAgent? Function(String?) _resolvePicked(
  List<CoordinationAgent> candidates,
) {
  return (picked) {
    if (picked == null) return null;
    for (final a in candidates) {
      if (a.id == picked) return a;
    }
    return null;
  };
}

/// Give one agent work in one session, in a single step.
///
/// The sheet collects only what a human can decide — who, what, and how the
/// agent knows it is done — plus an optional inference profile for THIS
/// dispatch. The daemon mints the goal, assignment id, and turn lease, so the
/// client never invents server-owned state.
class AgentWorkSheet extends StatefulWidget {
  const AgentWorkSheet({
    super.key,
    required this.client,
    required this.sessionId,
    this.initialAgentId,
    this.workspaceLabel,
  });

  final DaemonClient client;

  /// The durable session the work lands in.
  final String sessionId;

  /// Pre-selected agent, when the sheet was opened from that agent's row.
  final String? initialAgentId;

  /// Shown as read-only context so the user can confirm the target workspace.
  final String? workspaceLabel;

  @override
  State<AgentWorkSheet> createState() => _AgentWorkSheetState();
}

class _AgentWorkSheetState extends State<AgentWorkSheet> {
  final _scope = TextEditingController();
  final _done = TextEditingController();

  List<InferenceProfile> _profiles = const [];
  String? _agentId;
  String? _agentName;
  String? _profile;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _agentId = widget.initialAgentId;
    _load();
  }

  @override
  void dispose() {
    _scope.dispose();
    _done.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Profiles come from the same config the model picker reads, so the sheet
      // offers exactly the profiles the daemon knows about.
      final results = await Future.wait([
        widget.client.coordinationAgents(),
        widget.client.getConfig(),
      ]);
      final agents = results[0] as List<CoordinationAgent>;
      final cfg = results[1] as ServerConfig;
      if (!mounted) return;
      setState(() {
        _profiles = cfg.profiles;
        _loading = false;
        // Resolve a display name for a pre-selected agent; leave the choice
        // open otherwise.
        for (final a in agents) {
          if (a.id == _agentId) {
            _agentName = a.displayName.trim().isEmpty ? a.id : a.displayName;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _chooseAgent() async {
    final picked = await pickAgentId(context, widget.client);
    if (picked == null || !mounted) return;
    setState(() {
      _agentId = picked.id;
      _agentName =
          picked.displayName.trim().isEmpty ? picked.id : picked.displayName;
    });
  }

  Future<void> _submit() async {
    final agentId = _agentId;
    if (agentId == null) {
      setState(() => _error = 'Choose an agent');
      return;
    }
    final scope = _scope.text.trim();
    final done = _done.text.trim();
    if (scope.isEmpty || done.isEmpty) {
      setState(() => _error = 'Scope and definition of done are required');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.dispatchAgentWork(
        sessionId: widget.sessionId,
        agentId: agentId,
        scope: scope,
        definitionOfDone: done,
        profile: _profile,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet and its input: a failed dispatch must not cost the
      // user what they just typed.
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final workspace = widget.workspaceLabel?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace.isNotEmpty) ...[
          Text('workspace', style: mono(10, color: AppColors.fg4)),
          const SizedBox(height: 4),
          Text(workspace,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12.5, color: AppColors.fg2)),
          const SizedBox(height: 14),
        ],
        Text('agent', style: mono(10, color: AppColors.fg4)),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: _sending ? null : _chooseAgent,
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(children: [
                AppIcon('users', size: 15, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_agentName ?? 'Choose an agent',
                      style: sans(13,
                          color: _agentName == null
                              ? AppColors.fg4
                              : AppColors.fg1)),
                ),
                AppIcon('chevron-down', size: 13, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'scope',
          controller: _scope,
          hint: 'What should this agent do?',
          minLines: 2,
          maxLines: 5,
          enabled: !_sending,
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'definition of done',
          controller: _done,
          hint: 'How will it know the work is finished?',
          minLines: 2,
          maxLines: 5,
          enabled: !_sending,
        ),
        const SizedBox(height: 14),
        Text('inference profile', style: mono(10, color: AppColors.fg4)),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            onTap: _sending ? null : _chooseProfile,
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(children: [
                AppIcon('sparkles', size: 15, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_profile ?? "session's own profile",
                      style: sans(13,
                          color: _profile == null
                              ? AppColors.fg4
                              : AppColors.fg1)),
                ),
                AppIcon('chevron-down', size: 13, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Applies to this dispatch only; the session keeps its own model.',
          style: sans(11, color: AppColors.fg4),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: sans(12, color: AppColors.danger)),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Btn('Cancel',
                variant: BtnVariant.ghost,
                full: true,
                disabled: _sending,
                onTap: () => Navigator.of(context).pop(false)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Btn(_sending ? 'Dispatching…' : 'Dispatch',
                full: true,
                disabled: _sending,
                onTap: _submit),
          ),
        ]),
      ],
    );
  }

  Future<void> _chooseProfile() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Inference profile',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(''),
              borderRadius: BorderRadius.circular(R.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Text("Session's own profile",
                    style: sans(13.5, color: AppColors.fg2)),
              ),
            ),
          ),
          for (final p in _profiles)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(p.name),
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: sans(13.5,
                                  weight: W.label, color: AppColors.fg1)),
                          const SizedBox(height: 2),
                          Text('${p.provider} · ${p.model}',
                              style: mono(10, color: AppColors.fg4)),
                        ],
                      ),
                    ),
                    // Only a usable profile can actually run the dispatch.
                    if (!p.usable)
                      Text('unusable',
                          style: mono(10, color: AppColors.danger)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _profile = picked.isEmpty ? null : picked);
  }
}

/// A direct conversation with one agent.
///
/// This is conversation, not work control: it shows what was said and lets the
/// user reply. Turning a message into a task happens through the "give work"
/// flow, so a chat can never silently authorise a workspace change.
class AgentThreadScreen extends StatefulWidget {
  const AgentThreadScreen({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.onClose,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;
  final VoidCallback? onClose;

  @override
  State<AgentThreadScreen> createState() => _AgentThreadScreenState();
}

class _AgentThreadScreenState extends State<AgentThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CoordinationEvent> _events = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final events = await widget.client.agentThread(peerId: widget.agentId);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
      // Opening a conversation is what marks it read.
      unawaitedMarkRead();
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void unawaitedMarkRead() {
    widget.client.markAgentThreadRead(peerId: widget.agentId).catchError((_) {});
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: body,
      );
      if (!mounted) return;
      _input.clear();
      setState(() => _sending = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Divider(height: 1, color: AppColors.border),
        Expanded(child: _body()),
        Divider(height: 1, color: AppColors.border),
        _composer(),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(children: [
        AppIcon('message', size: 15, color: AppColors.accent),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.agentName,
                  style: sans(14, weight: W.label, color: AppColors.fg1)),
              const SizedBox(height: 2),
              Text('direct message · conversation only',
                  style: mono(10, color: AppColors.fg4)),
            ],
          ),
        ),
        if (widget.onClose != null)
          IconBtn('x', size: 28, iconSize: 14, tooltip: 'Close', onTap: widget.onClose!),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: sans(12.5, color: AppColors.danger)),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No messages yet. Say something to start.',
              style: sans(12.5, color: AppColors.fg4)),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: _events.length,
      itemBuilder: (_, i) => _bubble(_events[i]),
    );
  }

  Widget _bubble(CoordinationEvent e) {
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(mine ? 'you' : '${e.actorKind}:${e.actorId}',
              style: mono(9.5, color: AppColors.fg4)),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? AppColors.accentBg : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                  color: mine ? AppColors.accentLine : AppColors.border),
            ),
            child: Text(e.body,
                style: sans(13, height: 1.4, color: AppColors.fg1)),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              cursorColor: AppColors.fg1,
              onSubmitted: (_) => _send(),
              style: sans(13.5, color: AppColors.fg1),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Message ${widget.agentName}',
                hintStyle: sans(13.5, color: AppColors.fg4),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.accentLine),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Btn('Send',
              small: true,
              icon: 'send',
              disabled: _sending,
              onTap: _send),
        ],
      ),
    );
  }
}

/// Open the "give work" sheet for a session, reporting whether anything was
/// dispatched so the caller can refresh a roster or board.
Future<bool> showAgentWorkSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? initialAgentId,
  String? workspaceLabel,
}) async {
  final done = await showAppSheet<bool>(
    context,
    title: 'Give an agent work',
    child: AgentWorkSheet(
      client: client,
      sessionId: sessionId,
      initialAgentId: initialAgentId,
      workspaceLabel: workspaceLabel,
    ),
  );
  return done == true;
}

/// Open a direct conversation with one agent.
void openAgentThread(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
}) {
  presentScreen(
    context,
    style: PanelStyle.drawer,
    maxWidth: 720,
    maxHeight: 720,
    builder: (_, close) => AgentThreadScreen(
      client: client,
      agentId: agentId,
      agentName: agentName,
      onClose: close,
    ),
  );
}
