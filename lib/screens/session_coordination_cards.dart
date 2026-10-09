import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../components.dart';
import '../markdown_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mission_control/mission_control_state.dart'
    show
        AssignmentEnvelope,
        AutonomousRound,
        BoardMessage,
        DirectMessage,
        MissionEnvelope,
        WorkerQuestion,
        parseTaskOffer;

/// Work and messages that arrive from another thread (Mission Control, another
/// agent, the coordination board) share one card, in the plan card's idiom: a
/// quiet mono meta line (what it is, a reference, its status), an optional
/// title, and the body as markdown, collapsed to a few lines until expanded.
class _ThreadCard extends StatefulWidget {
  final String icon;
  final Tone tone;
  final String kind;
  final String? title;
  final String status;
  final String body;
  final String? reference;
  final String? footer;
  final String? preview;
  const _ThreadCard({
    required this.icon,
    required this.tone,
    required this.kind,
    this.title,
    required this.status,
    required this.body,
    this.reference,
    this.footer,
    this.preview,
  });

  @override
  State<_ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<_ThreadCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final (toneFg, _) = toneColors(widget.tone);
    final body = widget.body.trim();
    final title = widget.title?.trim() ?? '';
    final ref = widget.reference?.trim() ?? '';
    final footer = widget.footer?.trim() ?? '';
    final long = body.length > 280 || '\n'.allMatches(body).length > 4;
    final text = sans(13, height: 1.45, color: AppColors.fg2);
    final base = markdownStyle(context);
    final sheet = base.copyWith(
      p: text,
      listBullet: text,
      strong: text.copyWith(color: AppColors.fg1, fontWeight: W.strong),
      em: text.copyWith(fontStyle: FontStyle.italic),
      a: text.copyWith(color: AppColors.accent),
    );
    final meta = mono(10, color: AppColors.fg3);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AppIcon(widget.icon, size: 12, color: toneFg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ref.isEmpty ? widget.kind : '${widget.kind} · $ref',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ),
              const SizedBox(width: S.s8),
              Text(widget.status, style: mono(10, color: toneFg)),
            ]),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
            ],
            if (body.isNotEmpty) ...[
              SizedBox(height: title.isEmpty ? 5 : 3),
              AnimatedSize(
                duration: Motion.fast,
                curve: Motion.enter,
                alignment: Alignment.topLeft,
                child: _open || !long
                    ? MarkdownBody(
                        data: body,
                        selectable: true,
                        styleSheet: sheet,
                        builders: {'pre': PreBlockBuilder()},
                        onTapLink: (_, href, __) => openMarkdownLink(href),
                      )
                    : widget.preview != null
                        ? Text(widget.preview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text)
                        : MarkdownPreview(data: body, maxLines: 3, style: text),
              ),
            ],
            if (footer.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(footer, style: sans(12, height: 1.4, color: AppColors.fg3)),
            ],
            if (long)
              InkWell(
                onTap: () => setState(() => _open = !_open),
                borderRadius: BorderRadius.circular(R.xs),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(_open ? 'Show less' : 'Show more', style: meta),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// A board thread id as a short reference: `task:<uuid>` reads `task eaa98084`.
String _threadRef(String id) {
  final i = id.indexOf(':');
  if (i <= 0) return _short(id);
  return '${id.substring(0, i)} ${_short(id.substring(i + 1))}';
}

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
      'stalled' => (Tone.run, 'alert-triangle', 'Stalled'),
      'cancelled' => (Tone.neutral, 'x-circle', 'Cancelled'),
      'message' => (Tone.neutral, 'message', 'Message'),
      'update' => (Tone.neutral, 'info', 'Update'),
      _ => (Tone.accent, 'inbox', 'New task'),
    };
    return _ThreadCard(
      icon: icon,
      tone: tone,
      kind: envelope.isReport ? 'Task report' : 'Task from Mission Control',
      reference: envelope.taskId.isEmpty ? null : _short(envelope.taskId),
      title: envelope.title.isEmpty ? 'Task' : envelope.title,
      status: tag,
      body: envelope.summary,
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
      kind: 'Board · $from',
      reference: message.threadId.isEmpty ? null : _threadRef(message.threadId),
      status: 'Posted',
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
    final who = from == 'you' ? 'You' : from;
    final offer = message.isReply ? null : parseTaskOffer(message.body);
    if (offer != null) {
      return _ThreadCard(
        icon: 'agent',
        tone: Tone.run,
        kind: 'Task offer from $who',
        title: offer.title.isEmpty ? null : offer.title,
        reference: offer.taskId.isEmpty ? null : _short(offer.taskId),
        status: 'Offered',
        body: offer.briefing,
        footer: 'Starts once claimed; the agent can also ask or decline',
      );
    }
    return _ThreadCard(
      icon: message.isReply ? 'corner-down-right' : 'message',
      tone: Tone.accent,
      kind: message.isReply ? 'Reply from $who' : 'Message from $who',
      status: message.isReply ? 'Reply' : 'Message',
      body: message.body,
    );
  }
}

class AutonomousRoundCard extends StatelessWidget {
  const AutonomousRoundCard({super.key, required this.round});
  final AutonomousRound round;

  @override
  Widget build(BuildContext context) => _ThreadCard(
        icon: 'activity',
        tone: round.due.isNotEmpty ? Tone.run : Tone.neutral,
        kind: 'Autonomous round',
        title: round.headline,
        status: _roundTime(round.time),
        body: round.markdown,
        preview: _roundPreview(round),
      );
}

String _roundTime(String time) {
  final parts = time.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return time.isEmpty ? 'Round' : time;
  return '${parts.first} ${parts.last}';
}

String _plain(String line) => line.replaceAll('**', '');

String _roundPreview(AutonomousRound round) {
  if (round.due.isNotEmpty) return 'Due: ${_plain(round.due.first)}';
  if (round.changed.isNotEmpty)
    return 'Changed: ${_plain(round.changed.first)}';
  if (round.open.isNotEmpty) return _plain(round.open.first);
  return 'Nothing changed, nothing open.';
}

class WorkerQuestionCard extends StatelessWidget {
  const WorkerQuestionCard({super.key, required this.question});
  final WorkerQuestion question;

  @override
  Widget build(BuildContext context) => _ThreadCard(
        icon: 'message-text',
        tone: Tone.run,
        kind: 'Worker question',
        title: question.task.isEmpty ? null : question.task,
        status: 'Waiting',
        body: question.question,
        footer: 'Mission Control answers from your brief, or pings you',
      );
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
        kind: outbound ? 'Message to $agentId' : 'Reply from $agentId',
        status: outbound ? 'Sent' : 'Reply',
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
      kind: 'Assignment',
      title: agent.isEmpty ? 'Work assigned here' : 'Assigned to $agent',
      status: 'Assigned',
      body: assignment.scope,
      footer: done.isEmpty ? null : 'Done when: $done',
    );
  }
}
