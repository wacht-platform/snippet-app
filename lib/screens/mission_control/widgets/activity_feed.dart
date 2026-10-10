/// Chat-style activity feed using the same Bubble / EmptyState widgets as
/// a regular session. Task events stay as compact status rows.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';
import '../../../platform.dart';
import '../../../pull_refresh.dart';

class ActivityFeed extends StatelessWidget {
  const ActivityFeed({
    super.key,
    required this.state,
    required this.onTapTask,
    required this.onTapQuestion,
  });
  final MissionControlState state;
  final void Function(dynamic task) onTapTask;
  final void Function(QuestionItem q) onTapQuestion;

  @override
  Widget build(BuildContext context) {
    final feed = state.feed;
    if (feed.isEmpty) {
      // The header already says "Connecting…"; the feed shows its shape.
      if (state.loading && state.fatalError == null) {
        return const _FeedSkeleton();
      }
      final err = state.fatalError;
      return Center(
        child: EmptyState(
          icon: err == null ? 'layers' : 'alert-circle',
          title: err == null ? 'Mission Control ready' : 'Could not connect',
          body: err ?? 'Send a task and the agent will figure out the rest.',
        ),
      );
    }
    return PullToRefresh(
      onRefresh: () async {
        await state.refresh(silent: true);
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: feed.length,
        itemBuilder: (context, i) {
          final item = feed[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FeedRow(
              item: item,
              onTapTask: onTapTask,
              onTapQuestion: onTapQuestion,
            ),
          );
        },
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.item,
    required this.onTapTask,
    required this.onTapQuestion,
  });
  final FeedItem item;
  final void Function(dynamic) onTapTask;
  final void Function(QuestionItem) onTapQuestion;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      UserMessageItem m => Bubble(mine: true, text: m.text),
      BoardMessageItem b => _BoardMessageRow(message: b.message),
      AutonomousRoundItem r => _EnvelopeRow(
          color: r.round.due.isNotEmpty ? AppColors.run : AppColors.fg4,
          title: 'Autonomous round',
          meta: r.round.time,
          body: r.round.headline),
      WorkerQuestionItem w => _EnvelopeRow(
          color: AppColors.run,
          title: w.question.task.isEmpty
              ? 'Worker question'
              : 'Worker question · ${w.question.task}',
          meta: 'waiting',
          body: w.question.question),
      AgentTextItem a => Bubble(mine: false, text: a.text),
      TaskEventItem t => _TaskEventRow(item: t, onTap: () => onTapTask(t.task)),
      QuestionItem q => _QuestionRow(item: q, onTap: () => onTapQuestion(q)),
      SystemNoteItem s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: Text(s.text,
                textAlign: TextAlign.center,
                // Information, not a placeholder: `fg3`, never `fg4` (the
                // disabled ramp). Same rule the board's count already states.
                style: TS.meta()),
          ),
        ),
    };
  }
}

class _TaskEventRow extends StatelessWidget {
  const _TaskEventRow({required this.item, required this.onTap});
  final TaskEventItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.kind) {
      'working' || 'stalled' => AppColors.run,
      'done' => AppColors.ok,
      'blocked' || 'failed' => AppColors.danger,
      _ => AppColors.fg3,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.task.title.isEmpty ? item.kind : item.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg1),
              ),
            ),
            Text(item.kind, style: TS.meta()),
          ]),
        ),
      ),
    );
  }
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow(
      {required this.color,
      required this.title,
      required this.meta,
      required this.body});
  final Color color;
  final String title;
  final String meta;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1)),
              ),
              if (meta.isNotEmpty) Text(meta, style: TS.meta()),
            ]),
            if (body.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body.trim(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, height: 1.35, color: AppColors.fg3)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _BoardMessageRow extends StatelessWidget {
  const _BoardMessageRow({required this.message});
  final BoardMessage message;

  @override
  Widget build(BuildContext context) {
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

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.item, required this.onTap});
  final QuestionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Needs input', style: TS.meta()),
                  const SizedBox(height: 4),
                  Text(item.question,
                      style: sans(kMobile ? 16 : 14, color: AppColors.fg1)),
                ],
              ),
            ),
            Text('Reply', style: sans(13, color: AppColors.accent)),
          ]),
        ),
      ),
    );
  }
}

/// A conversation's shape while the feed connects: a message, a reply, a card.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double factor, double h) => FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: Skeleton(height: h, color: AppColors.hover),
        );
    Widget exchange(double a, double b) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Skeleton(height: 44, radius: R.card, color: AppColors.surface1),
            const SizedBox(height: S.s16),
            bar(a, 12),
            const SizedBox(height: S.s8),
            bar(b, 12),
            const SizedBox(height: S.s16),
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface1,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(R.md),
              ),
            ),
          ],
        );
    return Semantics(
      label: 'Loading',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(M.gutter, S.s16, M.gutter, S.s16),
        children: [
          exchange(0.9, 0.6),
          const SizedBox(height: S.s24),
          exchange(0.75, 0.45),
        ],
      ),
    );
  }
}
