/// Chat-style activity feed using the same Bubble / EmptyState widgets as
/// a regular session. Task events stay as compact status rows.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';

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
      if (state.loading && state.fatalError == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.fg3,
                ),
              ),
              const SizedBox(height: 14),
              Text('Connecting…', style: sans(13, color: AppColors.fg3)),
            ],
          ),
        );
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
    return RefreshIndicator(
      color: AppColors.accent,
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
      AgentTextItem a => Bubble(mine: false, text: a.text),
      TaskEventItem t => _TaskEventRow(item: t, onTap: () => onTapTask(t.task)),
      QuestionItem q => _QuestionRow(item: q, onTap: () => onTapQuestion(q)),
      SystemNoteItem s => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: Text(s.text,
                textAlign: TextAlign.center,
                style: sans(12, color: AppColors.fg4)),
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
      'working' => AppColors.run,
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
                style: sans(13.5, color: AppColors.fg1),
              ),
            ),
            Text(item.kind, style: sans(12, color: AppColors.fg4)),
          ]),
        ),
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
                  Text('Needs input', style: sans(12, color: AppColors.fg3)),
                  const SizedBox(height: 4),
                  Text(item.question, style: sans(15.5, color: AppColors.fg1)),
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
