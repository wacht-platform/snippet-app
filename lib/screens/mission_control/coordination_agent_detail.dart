import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../agent_messaging.dart';

/// One coordination agent — shown as its CONVERSATION.
///
/// Tapping an agent opens the message screen, because that is what an agent page
/// is FOR: talking to it. Identity (handle, role, status) is a compact header on
/// the thread rather than a page of its own — it is context for the
/// conversation, not content worth a separate screen.
///
/// The board that used to live here is deliberately gone: an empty list of
/// internal rows is not what anyone opens an agent to see.
class CoordinationAgentDetail extends StatelessWidget {
  const CoordinationAgentDetail({
    super.key,
    required this.agent,
    this.client,
    this.embedded = false,
    this.onClose,
  });

  /// Null only while no machine is connected; the screen says so rather than
  /// pretending the agent has no conversation.
  final DaemonClient? client;
  final CoordinationAgent agent;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = client;
    if (c == null) {
      return _NoConnection(agent: agent, onClose: onClose);
    }
    return AgentThreadScreen(
      client: c,
      agentId: agent.id,
      agentName: agent.displayName.trim().isEmpty
          ? agent.id
          : agent.displayName.trim(),
      onClose: onClose,
      embedded: embedded,
    );
  }
}

/// Shown when the shell has no active machine connection yet.
class _NoConnection extends StatelessWidget {
  const _NoConnection({required this.agent, this.onClose});

  final CoordinationAgent agent;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final name = agent.displayName.trim().isEmpty
        ? agent.id
        : agent.displayName.trim();
    return Material(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(16, weight: W.title, color: AppColors.fg1)),
              ),
              if (onClose != null)
                IconBtn('x',
                    size: 28,
                    iconSize: 15,
                    tooltip: 'Close',
                    onTap: onClose!),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text('Connect to a machine to message this agent.',
                    textAlign: TextAlign.center,
                    style: sans(12, color: AppColors.fg3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
