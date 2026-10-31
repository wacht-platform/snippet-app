import 'package:flutter/material.dart';

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

class CardMarkdownBody extends StatefulWidget {
  final String body;
  final String? preview;
  const CardMarkdownBody({super.key, required this.body, this.preview});

  @override
  State<CardMarkdownBody> createState() => _CardMarkdownBodyState();
}

class _CardMarkdownBodyState extends State<CardMarkdownBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body.trim();
    final long = body.length > 160 || '\n'.allMatches(body).length > 1;
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
      h1: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h2: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h3: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h4: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      pPadding: EdgeInsets.zero,
      blockSpacing: 4,
      listIndent: 16,
      listBulletPadding: const EdgeInsets.only(right: 4),
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
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: text)
                : ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: _open || !long
                            ? double.infinity
                            : text.fontSize! * 1.4 * 2 + 2),
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
              padding: const EdgeInsets.only(top: S.s2),
              child: Text(_open ? 'Show less' : 'Show more',
                  style: sans(TranscriptCard.metaSize,
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
  const _ThreadCard({
    required this.icon,
    required this.tone,
    required this.kind,
    this.title,
    this.status,
    required this.body,
    this.reference,
    this.footer,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(TranscriptCard.metaSize,
                  height: 1.35, color: AppColors.fg4)),
      child: body.trim().isEmpty ? null : CardMarkdownBody(body: body),
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
    if (envelope.isPlan) {
      final steps = parsePlanSteps(envelope.summary);
      final done = steps.where((s) => s.$2 == PlanStep.done).length;
      return TranscriptCard(
        icon: 'list',
        tone: Tone.accent,
        kind: envelope.taskId.isEmpty
            ? 'Worker plan'
            : 'Worker plan · ${_short(envelope.taskId)}',
        title: envelope.title.isEmpty ? 'Task' : envelope.title,
        status: steps.isEmpty ? 'Plan' : '$done/${steps.length}',
        child: steps.isEmpty ? null : PlanChecklist(steps: steps),
      );
    }
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

enum PlanStep { done, now, todo }

List<(String, PlanStep)> parsePlanSteps(String summary) => [
      for (final raw in summary.split('\n'))
        if (raw.trim().startsWith('- '))
          switch (raw.trim().substring(2).trim()) {
            final t
                when t.startsWith('~~') && t.endsWith('~~') && t.length > 4 =>
              (t.substring(2, t.length - 2), PlanStep.done),
            final t when t.startsWith('**') && t.endsWith('** · now') => (
                t.substring(2, t.length - '** · now'.length),
                PlanStep.now
              ),
            final t => (t, PlanStep.todo),
          },
    ];

class PlanChecklist extends StatefulWidget {
  const PlanChecklist({super.key, required this.steps});
  final List<(String, PlanStep)> steps;

  @override
  State<PlanChecklist> createState() => _PlanChecklistState();
}

class _PlanChecklistState extends State<PlanChecklist> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    const cap = 4;
    var shown = steps;
    if (!_open && steps.length > cap) {
      final now = steps.indexWhere((s) => s.$2 != PlanStep.done);
      final from =
          (now < 0 ? steps.length - cap : now - 1).clamp(0, steps.length - cap);
      shown = steps.sublist(from, from + cap);
    }
    final style = TranscriptCard.bodyStyle;
    final lineH = style.fontSize! * style.height!;
    Widget mark(PlanStep s) => SizedBox(
          width: 14,
          height: lineH,
          child: Center(
            child: switch (s) {
              PlanStep.done => AppIcon('check', size: 11, color: AppColors.fg4),
              PlanStep.now => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle)),
              PlanStep.todo => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.fg4, width: 1))),
            },
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (text, state) in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark(state),
                const SizedBox(width: S.s6),
                Expanded(
                  child: Text(text,
                      maxLines: _open ? null : 1,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: style.copyWith(
                          color: switch (state) {
                        PlanStep.done => AppColors.fg4,
                        PlanStep.now => AppColors.fg1,
                        PlanStep.todo => AppColors.fg2,
                      })),
                ),
              ],
            ),
          ),
        if (steps.length > cap)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: S.s4, left: 20),
              child: Text(
                  _open ? 'Show less' : 'Show all ${steps.length} steps',
                  style: sans(TranscriptCard.metaSize,
                      weight: W.label, color: AppColors.fg3)),
            ),
          ),
      ],
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
    final typed = message.messageKind.replaceAll('_', ' ');
    final label = typed.isEmpty ? '' : '${typed[0].toUpperCase()}${typed.substring(1)}';
    return _ThreadCard(
      icon: message.isReply ? 'corner-down-right' : 'message',
      tone: message.urgent ? Tone.danger : Tone.accent,
      kind: message.isReply ? 'Reply from $who' : 'Message from $who',
      status: message.urgent
          ? (label.isEmpty ? 'Urgent' : '$label, urgent')
          : (label.isNotEmpty ? label : (message.isReply ? 'Reply' : 'Message')),
      body: message.body,
    );
  }
}

class AutonomousRoundCard extends StatefulWidget {
  const AutonomousRoundCard({super.key, required this.round});
  final AutonomousRound round;

  @override
  State<AutonomousRoundCard> createState() => _AutonomousRoundCardState();
}

class _AutonomousRoundCardState extends State<AutonomousRoundCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.round;
    final sections = [
      ('Due', r.due),
      ('Changed', r.changed),
      ('Open', r.open),
      ('Scheduled', r.scheduled),
    ].where((s) => s.$2.isNotEmpty).toList();
    final items = [for (final s in sections) ...s.$2.map(_plain)];
    final summary = [
      if (r.firstRound) 'switched on',
      if (r.due.isNotEmpty) '${r.due.length} due',
      if (r.changed.isNotEmpty) '${r.changed.length} changed',
      if (r.open.isNotEmpty) '${r.open.length} open',
      if (r.due.isEmpty && r.changed.isEmpty && r.open.isEmpty) 'nothing new',
    ].join(' · ');
    final meta = TranscriptCard.metaSize;
    final body = TranscriptCard.bodyStyle;
    final more = items.length > 1;
    final content = Padding(
      padding: kMobile
          ? const EdgeInsets.fromLTRB(12, 8, 12, 9)
          : const EdgeInsets.fromLTRB(12, 6, 12, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            AppIcon('activity',
                size: 12,
                color: r.due.isNotEmpty ? AppColors.run : AppColors.fg3),
            const SizedBox(width: S.s6),
            Expanded(
              child: Text('Automated wake · $summary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(meta, color: AppColors.fg3)),
            ),
            const SizedBox(width: S.s8),
            Text(_roundTime(r.time), style: sans(meta, color: AppColors.fg4)),
          ]),
          if (items.isNotEmpty && !_open)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: S.s2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: items.first),
                  if (more)
                    TextSpan(
                        text: '  +${items.length - 1}',
                        style: body.copyWith(color: AppColors.fg4)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body,
              ),
            ),
          if (_open)
            for (final (label, list) in sections) ...[
              Padding(
                padding: const EdgeInsets.only(left: 18, top: S.s4),
                child: Text(label,
                    style: sans(meta, weight: W.label, color: AppColors.fg4)),
              ),
              for (final item in list)
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: S.s2),
                  child: SelectableText(_plain(item), style: body),
                ),
            ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: items.isEmpty
            ? content
            : InkWell(
                onTap: () => setState(() => _open = !_open), child: content),
      ),
    );
  }
}

String _roundTime(String time) {
  final parts = time.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return time.isEmpty ? 'Wake' : time;
  return '${parts.first} ${parts.last}';
}

String _plain(String line) => line.replaceAll('**', '');

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
      turn.addressed != null ||
      turn.userVoice != null;

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
      if (turn.userVoice != null) 'voice ${(turn.userVoice! * 100).round()}%',
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
                padding: kMobile
                    ? const EdgeInsets.fromLTRB(15, 10, 15, 11)
                    : const EdgeInsets.fromLTRB(14, 9, 14, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(kMobile ? 20 : 16),
                    topRight: Radius.circular(kMobile ? 20 : 16),
                    bottomLeft: Radius.circular(kMobile ? 20 : 16),
                    bottomRight: const Radius.circular(6),
                  ),
                ),
                child: SelectionArea(
                  child: Text(
                    turn.text,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: sans(
                      kMobile ? 16 : 14,
                      height: kMobile ? 24 / 16 : 22 / 14,
                      color: AppColors.fg1,
                    ),
                  ),
                ),
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
              if (turn.judged.isNotEmpty ||
                  turn.addressed != null ||
                  turn.userVoice != null)
                Text(
                    [
                      if (turn.judged.isNotEmpty) 'Judged ${turn.judged}',
                      if (turn.userVoice != null)
                        'voice match ${(turn.userVoice! * 100).round()}%',
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
    final asking =
        expecting.isNotEmpty && expecting != 'none' && text.contains('?');
    return TranscriptCard(
      icon: 'volume',
      tone: asking ? Tone.accent : Tone.neutral,
      kind: 'Said aloud',
      status: asking ? 'Waiting for you' : null,
      body: text,
    );
  }
}
