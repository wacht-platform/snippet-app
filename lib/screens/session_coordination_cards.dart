import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../components.dart';
import '../markdown_widgets.dart';
import '../platform.dart';
import '../transcript_card.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mission_control/mission_control_state.dart'
    show
        AmbientTurn,
        AssignmentEnvelope,
        AutonomousRound,
        BoardMessage,
        DirectMessage,
        MissionEnvelope,
        WorkerQuestion,
        parseTaskOffer;

class _MarkdownBody extends StatefulWidget {
  final String body;
  final String? preview;
  const _MarkdownBody({required this.body, this.preview});

  @override
  State<_MarkdownBody> createState() => _MarkdownBodyState();
}

class _MarkdownBodyState extends State<_MarkdownBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body.trim();
    final long = body.length > 240 || '\n'.allMatches(body).length > 2;
    final text = TranscriptCard.bodyStyle;
    final sheet = markdownStyle(context).copyWith(
      p: text,
      listBullet: text,
      strong:
          text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      em: text.copyWith(fontStyle: FontStyle.italic),
      del: text.copyWith(
          decoration: TextDecoration.lineThrough, color: AppColors.fg3),
      a: text.copyWith(color: AppColors.accent),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.enter,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: double.infinity,
            child: !_open && long && widget.preview != null
                ? Text(widget.preview!,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: text)
                : ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: _open || !long
                            ? double.infinity
                            : text.fontSize! * 1.45 * 3 + 2),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _open || !long
                            ? const [Colors.white, Colors.white]
                            : const [
                                Colors.white,
                                Colors.white,
                                Colors.transparent
                              ],
                        stops: _open || !long ? null : const [0, 0.55, 1],
                      ).createShader(r),
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: MarkdownBody(
                            data: body,
                            selectable: _open || !long,
                            styleSheet: sheet,
                            builders: {'pre': PreBlockBuilder()},
                            onTapLink: (_, href, __) =>
                                openMarkdownLink(href, context),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (long)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: S.s4),
              child: Text(_open ? 'Show less' : 'Show more',
                  style: sans(kMobile ? 13 : 12.5,
                      weight: W.label, color: AppColors.fg3)),
            ),
          ),
      ],
    );
  }
}

class _ThreadCard extends StatelessWidget {
  final String icon;
  final Tone tone;
  final String kind;
  final String? title;
  final String? status;
  final String body;
  final String? reference;
  final String? footer;
  final String? preview;
  const _ThreadCard({
    required this.icon,
    required this.tone,
    required this.kind,
    this.title,
    this.status,
    required this.body,
    this.reference,
    this.footer,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final ref = reference?.trim() ?? '';
    final foot = footer?.trim() ?? '';
    return TranscriptCard(
      icon: icon,
      tone: tone,
      kind: ref.isEmpty ? kind : '$kind · $ref',
      status: status,
      title: title,
      footer: foot.isEmpty
          ? null
          : Text(foot,
              style:
                  sans(kMobile ? 13 : 12.5, height: 1.4, color: AppColors.fg3)),
      child: body.trim().isEmpty
          ? null
          : _MarkdownBody(body: body, preview: preview),
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
    final (tone, icon, tag) = envelope.isPlan
        ? (Tone.accent, 'list', 'Plan')
        : switch (envelope.eventKind) {
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
      kind: envelope.isRecurring
          ? 'Scheduled run'
          : envelope.isPlan
              ? 'Worker plan'
              : envelope.isReport
                  ? 'Task report'
                  : 'Task from Mission Control',
      reference: envelope.taskId.isEmpty ? null : _short(envelope.taskId),
      title: envelope.title.isEmpty
          ? (envelope.isRecurring ? 'Scheduled run' : 'Task')
          : envelope.title,
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
        kind: 'Automated wake',
        title: round.headline,
        status: _roundTime(round.time),
        body: round.markdown,
        preview: _roundPreview(round),
      );
}

String _roundTime(String time) {
  final parts = time.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return time.isEmpty ? 'Wake' : time;
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
    this.laneTitle,
  });

  final String agentId;
  final String body;
  final bool outbound;
  final String? laneTitle;

  @override
  Widget build(BuildContext context) {
    final lane = agentId.startsWith('lane ');
    final given = laneTitle?.trim() ?? '';
    final laneName = given.isNotEmpty ? given : agentId.substring(5).trim();
    final who = lane ? 'Lane · $laneName' : agentId;
    return _ThreadCard(
      icon: outbound ? 'send' : (lane ? 'message' : 'corner-down-right'),
      tone: outbound ? Tone.neutral : Tone.accent,
      kind: outbound
          ? 'To ${lane ? who : agentId}'
          : (lane ? who : 'Message from $agentId'),
      status: outbound ? 'Sent' : null,
      body: body,
    );
  }
}

class ParentMessageCard extends StatelessWidget {
  const ParentMessageCard({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => _ThreadCard(
        icon: 'corner-down-right',
        tone: Tone.accent,
        kind: 'From the agent that handed this over',
        status: 'Message',
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

class AmbientTurnCard extends StatefulWidget {
  const AmbientTurnCard({super.key, required this.turn});
  final AmbientTurn turn;

  @override
  State<AmbientTurnCard> createState() => _AmbientTurnCardState();
}

class _AmbientTurnCardState extends State<AmbientTurnCard> {
  bool _open = false;

  AmbientTurn get turn => widget.turn;

  String get _where {
    final os = turn.device.split('-').first;
    return switch (os) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'macos' => 'Mac',
      'linux' => 'Linux',
      'windows' => 'Windows',
      _ => turn.device,
    };
  }

  bool get _hasDetail =>
      turn.context.isNotEmpty ||
      turn.interruptedReply.isNotEmpty ||
      turn.judged.isNotEmpty ||
      turn.addressed != null;

  @override
  Widget build(BuildContext context) {
    final at = turn.at;
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final meta = [
      _where,
      if (time.isNotEmpty) time,
      if (turn.mode == 'passive') 'passive',
      if (turn.wake) 'wake word',
      if (turn.continuation) 'continuation',
      if (turn.interruptedReply.isNotEmpty) 'interrupted a reply',
      if (turn.context.isNotEmpty)
        '${turn.context.length} earlier ${turn.context.length == 1 ? 'line' : 'lines'}',
    ].join(' · ');
    final detail = sans(kMobile ? 13 : 12.5, height: 1.4, color: AppColors.fg3);
    return LayoutBuilder(builder: (context, box) {
      final inset = kMobile
          ? 48.0
          : (box.maxWidth.isFinite ? box.maxWidth * 0.18 : 140.0)
              .clamp(24.0, 140.0);
      return Padding(
        padding: EdgeInsets.only(left: inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hasDetail ? () => setState(() => _open = !_open) : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                child: SelectableText(turn.text,
                    style: sans(kMobile ? 16 : 14,
                        height: 1.4, color: AppColors.fg1)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: S.s4, right: 2),
              child: Text(meta,
                  textAlign: TextAlign.end,
                  style: sans(kMobile ? 12.5 : 12, color: AppColors.fg4)),
            ),
            if (_open) ...[
              const SizedBox(height: S.s6),
              if (turn.judged.isNotEmpty || turn.addressed != null)
                Text(
                    [
                      if (turn.judged.isNotEmpty) 'Judged ${turn.judged}',
                      if (turn.addressed != null)
                        'reply expected ${(turn.addressed! * 100).round()}%',
                      if (turn.expects.isNotEmpty)
                        'answering a ${turn.expects} question',
                    ].join(' · '),
                    textAlign: TextAlign.end,
                    style: detail),
              if (turn.interruptedReply.isNotEmpty) ...[
                const SizedBox(height: S.s4),
                Text('Heard of its last reply: ${turn.interruptedReply}',
                    textAlign: TextAlign.end, style: detail),
              ],
              for (final line in turn.context) ...[
                const SizedBox(height: S.s4),
                Text('Earlier, not sent: $line',
                    textAlign: TextAlign.end, style: detail),
              ],
            ],
          ],
        ),
      );
    });
  }
}

class SpeakCard extends StatelessWidget {
  const SpeakCard({super.key, required this.text, this.expecting = ''});
  final String text;
  final String expecting;

  @override
  Widget build(BuildContext context) {
    final asking = expecting.isNotEmpty && expecting != 'none';
    return TranscriptCard(
      icon: 'volume',
      tone: asking ? Tone.accent : Tone.neutral,
      kind: 'Said aloud',
      status: asking ? 'Waiting for you' : null,
      body: text,
    );
  }
}
