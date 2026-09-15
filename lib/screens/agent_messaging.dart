import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pick one agent from the directory, as an anchored DROPDOWN.
///
/// Returns null when dismissed. Shared by the composer's recipient picker and
/// the message sheet so both offer the same list, in the same order.
///
/// Mission Control is NOT offered. It is the coordinator, reached by opening its
/// own session, so listing it as a recipient elsewhere would be a second path to
/// the same place — and would let a message meant for a worker land on the
/// coordinator. Agents reach Mission Control through their own tools, not here.
Future<CoordinationAgent?> pickAgentId(
  BuildContext context,
  DaemonClient client, {
  String title = 'Select an agent',
  Set<String> exclude = const {},
  String? currentAgentId,
  BuildContext? anchor,
}) async {
  List<CoordinationAgent> agents;
  try {
    agents = await client.coordinationAgents();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return null;
  }
  final candidates = agents
      .where((a) =>
          !exclude.contains(a.id) &&
          // Mission Control is reached through its own chat, not picked here.
          // Offering it would let a message aimed at a worker land on the
          // coordinator.
          !a.isMissionControl)
      .toList();
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    toast(context, 'No agents available');
    return null;
  }
  candidates.sort((a, b) => a.displayName.compareTo(b.displayName));

  // A dropdown, the SAME control as the approval and inference pickers: an
  // anchored popover on desktop, a bottom sheet on mobile. A centered dialog
  // for a short list of destinations was heavier than the thing it replaced.
  final picked = await showAppMenu<String>(
    context,
    anchor: anchor ?? context,
    minWidth: 260,
    maxWidth: 340,
    items: [
      appMenuHeading<String>(title),
      for (final a in candidates)
        appMenuRow<String>(
          value: a.id,
          icon: 'users',
          label: a.displayName.trim().isEmpty ? a.id : a.displayName,
          description: '${a.handle} · ${a.role} · ${a.status}',
          selected: a.id == currentAgentId,
        ),
    ],
  );
  if (picked == null) return null;
  for (final a in candidates) {
    if (a.id == picked) return a;
  }
  return null;
}

/// Message one agent from one session.
///
/// The sheet collects only what a human can decide — who, and what to say. It
/// sends a DIRECT MESSAGE carrying this session as its origin, so the agent
/// knows which session to reply in and which session to request dispatch on.
/// Nothing here creates work: dispatching belongs to Mission Control.
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
  final _message = TextEditingController();

  String? _agentId;
  String? _agentName;
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
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
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

  Future<void> _chooseAgent(BuildContext anchor) async {
    final picked = await pickAgentId(context, widget.client, anchor: anchor);
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
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a message');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.sendAgentMessage(
        toAgentId: agentId,
        body: message,
        // Ask FROM this session. The agent then knows which session to reply in
        // AND which session to request dispatch on — the whole reason this is a
        // message rather than a dispatch.
        originSession: widget.sessionId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet and its input: a failed send must not cost the user what
      // they just typed.
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
          Text('workspace', style: mono(10, color: AppColors.fg3)),
          const SizedBox(height: 4),
          Text(workspace,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg2)),
          const SizedBox(height: 14),
        ],
        Text('agent', style: mono(10, color: AppColors.fg3)),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: Builder(
            builder: (ctx) => InkWell(
              onTap: _sending ? null : () => _chooseAgent(ctx),
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
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'message',
          controller: _message,
          hint: 'What should this agent do?',
          minLines: 3,
          maxLines: 7,
          enabled: !_sending,
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
            child: Btn(_sending ? 'Sending…' : 'Send',
                full: true,
                disabled: _sending,
                onTap: _submit),
          ),
        ]),
      ],
    );
  }
}

/// A direct conversation with one agent.
///
/// This is conversation, not work control: it shows what was said and lets the
/// user reply. A message never authorises a workspace change, so a chat cannot
/// silently start work.
class AgentThreadScreen extends StatefulWidget {
  const AgentThreadScreen({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.subtitle,
    this.onClose,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Identity line under the name (`@handle · role · status`). Supplied by the
  /// caller, which owns the agent record.
  final String? subtitle;

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
    // Wrapped in Material because `presentScreen`'s non-rounded frames are plain
    // Containers — no Material ancestor — while a TextField and the icon buttons
    // here require one. Without this the screen threw "No Material widget found"
    // and rendered blank.
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Column(
        children: [
          _header(),
          Divider(height: 1, color: AppColors.border),
          Expanded(child: _body()),
          Divider(height: 1, color: AppColors.border),
          _composer(),
        ],
        ),
      ),
    );
  }

  Widget _header() {
    final subtitle = widget.subtitle?.trim() ?? '';
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, weight: W.title, color: AppColors.fg1)),
              const SizedBox(height: 2),
              Text(
                  subtitle.isEmpty
                      ? 'direct message · conversation only'
                      : '$subtitle · conversation only',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(10, color: AppColors.fg3)),
            ],
          ),
        ),
        if (widget.onClose != null)
          IconBtn('x',
              size: 28,
              iconSize: 14,
              tooltip: 'Close',
              onTap: widget.onClose!),
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
          child: Text(_error!, style: sans(12, color: AppColors.danger)),
        ),
      );
    }
    if (_events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No messages yet. Say something to start.',
              style: sans(12, color: AppColors.fg3)),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: _events.length,
      itemBuilder: (_, i) => _bubble(_events[i]),
    );
  }

  Widget _bubble(CoordinationEvent e) {
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(mine ? 'you' : '${e.actorKind}:${e.actorId}',
                style: mono(10, color: AppColors.fg3)),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? AppColors.accentBg : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                  color: mine ? AppColors.accentLine : AppColors.border),
            ),
            child: Text(e.body,
                // 1.35 rather than 1.4: a long reply is a wall of text either
                // way, and the tighter leading keeps it from dominating the
                // screen without making it hard to read.
                style: sans(13, height: 1.35, color: AppColors.fg1)),
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
              style: sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Message ${widget.agentName}',
                hintStyle: sans(13, color: AppColors.fg4),
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

/// Open the message sheet for a session, reporting whether anything was sent so
/// the caller can refresh a roster or board.
Future<bool> showAgentWorkSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? initialAgentId,
  String? workspaceLabel,
}) async {
  final done = await showAppSheet<bool>(
    context,
    title: 'Message an agent',
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
