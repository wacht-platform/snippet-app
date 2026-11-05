import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../agent_messaging.dart';
import '../../platform.dart';

/// One coordination agent: its conversation, with its inbox, board and settings
/// in the actions menu. Identity is a compact header rather than a page of its own.
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
                    style: sans(kMobile ? 16 : 14, weight: W.title, color: AppColors.fg1)),
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
                    style: TS.meta()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
