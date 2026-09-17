import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
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
    this.embedded = false,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Identity line under the name (`@handle · role · status`). Supplied by the
  /// caller, which owns the agent record.
  final String? subtitle;

  final VoidCallback? onClose;

  /// Nested under a host that already draws `NavBackRow`.
  final bool embedded;

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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_sending) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _events.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final events = await widget.client.agentThread(peerId: widget.agentId);
      if (!mounted) return;
      final hadNew = events.length > _events.length;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
      unawaitedMarkRead();
      if (hadNew) {
        _jumpToBottom(animated: silent);
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void unawaitedMarkRead() {
    widget.client.markAgentThreadRead(peerId: widget.agentId).catchError((_) {});
  }

  void _jumpToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        if (animated) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: Motion.fast,
            curve: Motion.enter,
          );
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
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
      await _load(silent: true);
      _jumpToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in Material because presentScreen's non-rounded frames are plain
    // Containers — no Material ancestor — while a TextField and the icon buttons
    // here require one.
    final hideChrome = widget.embedded && kMobile;
    return Material(
      color: readingBg,
      child: SafeArea(
        top: !hideChrome,
        bottom: false,
        child: Column(
          children: [
            if (!hideChrome) ...[
              _header(),
              Divider(height: 1, color: AppColors.border),
            ],
            Expanded(child: _body()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final subtitle = widget.subtitle?.trim() ?? '';
    final canGoBack = widget.onClose != null || Navigator.of(context).canPop();
    return Container(
      height: M.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.bg,
      child: Row(
        children: [
          if (canGoBack)
            IconBtn(
              'chevron-left',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Back',
              onTap: () {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          SizedBox(width: canGoBack ? 4 : 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(M.sectionTitle, weight: W.label, color: AppColors.fg1),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(M.monoMeta, color: AppColors.fg3),
                  ),
                ],
              ],
            ),
          ),
          IconBtn(
            'refresh',
            size: M.minTarget,
            iconSize: 18,
            tooltip: 'Refresh',
            onTap: () => _load(silent: false),
          ),
          if (!kMobile && widget.onClose != null) ...[
            const SizedBox(width: 4),
            IconBtn(
              'x',
              size: M.minTarget,
              iconSize: 16,
              tooltip: 'Close',
              onTap: widget.onClose!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('alert-circle', size: 24, color: AppColors.danger),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.danger)),
              const SizedBox(height: 14),
              Btn('Retry', small: true, onTap: () => _load(silent: false)),
            ],
          ),
        ),
      );
    }
    if (_events.isEmpty) {
      return RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: EmptyState(
                  icon: 'message',
                  title: 'Chat with ${widget.agentName}',
                  body: 'Send a message to discuss tasks or coordinate work directly.',
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _events.length,
        itemBuilder: (_, i) => _bubble(_events[i]),
      ),
    );
  }

  Widget _bubble(CoordinationEvent e) {
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    if (mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Bubble(mine: true, text: e.body),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon('users', size: 12, color: AppColors.accent),
                const SizedBox(width: 5),
                Text(
                  widget.agentName,
                  style: sans(11, weight: W.label, color: AppColors.accent),
                ),
              ],
            ),
          ),
          Bubble(mine: false, text: e.body),
        ],
      ),
    );
  }

  Widget _composer() {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
          8,
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
          10 + (keyboard > 0 ? 8 : mq.padding.bottom),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (!kMobile) _send();
                  },
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
                    _send();
                  },
                  const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                    _send();
                  },
                },
                child: TextField(
                  controller: _input,
                  minLines: 2,
                  maxLines: 8,
                  cursorColor: AppColors.fg1,
                  onSubmitted: (_) {
                    if (!kMobile) _send();
                  },
                  style: sans(kMobile ? M.body : 16,
                      height: 1.45, color: AppColors.fg1),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.fromLTRB(2, 2, 8, 10),
                    border: InputBorder.none,
                    hintText: 'Message ${widget.agentName}…',
                    hintStyle: sans(kMobile ? M.body : 16,
                        height: 1.45, color: AppColors.fg4),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon('users', size: 12, color: AppColors.fg3),
                        const SizedBox(width: 5),
                        Text(widget.agentName,
                            style: mono(11, color: AppColors.fg2)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, val, __) {
                      final canSend = val.text.trim().isNotEmpty && !_sending;
                      return _SendBtn(
                        enabled: canSend,
                        sending: _sending,
                        onTap: canSend ? _send : null,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback? onTap;
  const _SendBtn({required this.enabled, this.sending = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = kMobile ? M.minTarget : 28.0;
    return Material(
      color: enabled ? AppColors.fg1 : AppColors.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: sending
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.bg,
                    ),
                  )
                : AppIcon('arrow-up',
                    size: 15,
                    color: enabled ? AppColors.bg : AppColors.fg4),
          ),
        ),
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
  if (kMobile) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AgentThreadScreen(
          client: client,
          agentId: agentId,
          agentName: agentName,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
    return;
  }
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
