import 'package:flutter/material.dart';

import '../theme.dart';
import 'mission_control/mission_control_state.dart'
    show AssignmentEnvelope, BoardMessage, DirectMessage, MissionEnvelope;

class MissionEnvelopeCard extends StatelessWidget {
  const MissionEnvelopeCard({super.key, required this.envelope});
  final MissionEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final kind = envelope.eventKind;
    final color = switch (kind) {
      'working' => AppColors.run,
      'done' => AppColors.ok,
      'blocked' || 'failed' => AppColors.danger,
      _ => AppColors.fg3,
    };
    final label = envelope.isReport
        ? (envelope.status.isEmpty ? kind : envelope.status)
        : 'queued';
    final title = envelope.title.isEmpty ? 'Task' : envelope.title;
    final summary = envelope.summary.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  Text(label, style: TS.meta()),
                ]),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(summary,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BoardMessageCard extends StatelessWidget {
  const BoardMessageCard({super.key, required this.message});
  final BoardMessage message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final from = message.fromId.trim().isEmpty ? 'someone' : message.fromId;
    final label =
        message.threadId.isEmpty ? 'board' : 'board · ${message.threadId}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(from,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  Text(label, style: TS.meta()),
                ]),
                if (message.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message.body.trim(),
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DirectMessageCard extends StatelessWidget {
  const DirectMessageCard({super.key, required this.message});
  final DirectMessage message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final from = message.fromLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        message.isReply
                            ? 'Reply from $from'
                            : 'Message from $from',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  Text(message.isReply ? 'reply' : 'direct',
                      style: TS.meta()),
                ]),
                if (message.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message.body.trim(),
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({
    super.key,
    required this.agentId,
    required this.body,
    required this.outbound,
  });

  final String agentId;
  final String body;
  final bool outbound;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        outbound
                            ? 'Sent to $agentId'
                            : 'Reply from $agentId',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  Text(outbound ? 'sent' : 'reply',
                      style: TS.meta()),
                ]),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body.trim(),
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});
  final AssignmentEnvelope assignment;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final agent = assignment.agentId.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.run, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        agent.isEmpty
                            ? 'Work assigned here'
                            : 'Work assigned to $agent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg1)),
                  ),
                  Text('assigned', style: TS.meta()),
                ]),
                if (assignment.scope.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(assignment.scope.trim(),
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
                if (assignment.definitionOfDone.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('done when: ${assignment.definitionOfDone.trim()}',
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
