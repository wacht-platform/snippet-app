import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../components.dart';
import '../markdown_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mission_control/mission_control_state.dart'
    show AssignmentEnvelope, BoardMessage, DirectMessage, MissionEnvelope;

/// Work and messages that arrive from another thread (Mission Control, another
/// agent, the coordination board) share one card: who or what it is, a status
/// tag, and the body as markdown, collapsed to a few lines until expanded.
class _ThreadCard extends StatefulWidget {
  final String icon;
  final Tone tone;
  final String title;
  final String? subtitle;
  final String tag;
  final String body;
  final String? footer;
  const _ThreadCard({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    required this.tag,
    required this.body,
    this.footer,
  });

  @override
  State<_ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<_ThreadCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final body = widget.body.trim();
    final long = body.length > 280 || '\n'.allMatches(body).length > 4;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(S.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconTile(widget.icon, tone: widget.tone, size: 26),
              const SizedBox(width: S.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.rowTitle()),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                      Text(widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.meta()),
                  ],
                ),
              ),
              const SizedBox(width: S.s8),
              Tag(widget.tag, tone: widget.tone),
            ]),
            if (body.isNotEmpty) ...[
              const SizedBox(height: S.s8),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: AnimatedSize(
                  duration: Motion.fast,
                  curve: Motion.enter,
                  alignment: Alignment.topLeft,
                  child: _open || !long
                      ? MarkdownBody(
                          data: body,
                          selectable: true,
                          styleSheet: markdownStyle(context),
                          builders: {'pre': PreBlockBuilder()},
                          onTapLink: (_, href, __) => openMarkdownLink(href),
                        )
                      : MarkdownPreview(data: body, maxLines: 4),
                ),
              ),
              if (long)
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: S.s6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextAction(_open ? 'Show less' : 'Show more',
                        onTap: () => setState(() => _open = !_open)),
                  ),
                ),
            ],
            if (widget.footer != null && widget.footer!.isNotEmpty) ...[
              const SizedBox(height: S.s6),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(widget.footer!, style: TS.meta()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

class MissionEnvelopeCard extends StatelessWidget {
  const MissionEnvelopeCard({super.key, required this.envelope});
  final MissionEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final (tone, icon, tag) = switch (envelope.eventKind) {
      'working' => (Tone.run, 'activity', 'Working'),
      'done' => (Tone.ok, 'check', 'Done'),
      'blocked' => (Tone.danger, 'alert-triangle', 'Blocked'),
      'failed' => (Tone.danger, 'x-circle', 'Failed'),
      _ => (Tone.accent, 'inbox', 'New task'),
    };
    return _ThreadCard(
      icon: icon,
      tone: tone,
      title: envelope.title.isEmpty ? 'Task' : envelope.title,
      subtitle: envelope.isReport ? 'Task report' : 'Task from Mission Control',
      tag: tag,
      body: envelope.summary,
      footer:
          envelope.taskId.isEmpty ? null : 'Task ${_short(envelope.taskId)}',
    );
  }
}

class BoardMessageCard extends StatelessWidget {
  const BoardMessageCard({super.key, required this.message});
  final BoardMessage message;

  @override
  Widget build(BuildContext context) {
    final from = message.fromId.trim().isEmpty ? 'Someone' : message.fromId;
    return _ThreadCard(
      icon: 'coordination',
      tone: Tone.neutral,
      title: from,
      subtitle: message.threadId.isEmpty
          ? 'Coordination board'
          : 'Board · ${message.threadId}',
      tag: 'Board',
      body: message.body,
    );
  }
}

class DirectMessageCard extends StatelessWidget {
  const DirectMessageCard({super.key, required this.message});
  final DirectMessage message;

  @override
  Widget build(BuildContext context) {
    final from = message.fromLabel;
    return _ThreadCard(
      icon: message.isReply ? 'corner-down-right' : 'message',
      tone: Tone.accent,
      title: from == 'you' ? 'You' : from,
      subtitle: message.isReply ? 'Replied to this session' : 'Direct message',
      tag: message.isReply ? 'Reply' : 'Message',
      body: message.body,
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
  Widget build(BuildContext context) => _ThreadCard(
        icon: outbound ? 'send' : 'corner-down-right',
        tone: outbound ? Tone.neutral : Tone.accent,
        title: outbound ? 'To $agentId' : agentId,
        subtitle:
            outbound ? 'Sent from this session' : 'Replied to this session',
        tag: outbound ? 'Sent' : 'Reply',
        body: body,
      );
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});
  final AssignmentEnvelope assignment;

  @override
  Widget build(BuildContext context) {
    final agent = assignment.agentId.trim();
    final done = assignment.definitionOfDone.trim();
    return _ThreadCard(
      icon: 'agent',
      tone: Tone.run,
      title: agent.isEmpty ? 'Work assigned here' : 'Assigned to $agent',
      subtitle: 'Assignment',
      tag: 'Assigned',
      body: assignment.scope,
      footer: done.isEmpty ? null : 'Done when: $done',
    );
  }
}
