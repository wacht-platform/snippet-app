import 'package:flutter/material.dart';

import '../../api.dart';
import '../../goal_models.dart';
import '../../panel.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'goal_detail_screen.dart';

Tone attentionTone(GoalAttention a) => switch (a) {
      GoalAttention.stalled => Tone.danger,
      GoalAttention.readyToClose => Tone.ok,
    };

class AttentionChip extends StatelessWidget {
  const AttentionChip(this.attention, {super.key});
  final GoalAttention attention;

  @override
  Widget build(BuildContext context) =>
      Tag(attention.label, tone: attentionTone(attention), dot: true);
}

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar(this.progress, {super.key, this.colour});
  final GoalProgress progress;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: Stack(children: [
        Container(height: 4, color: AppColors.surface3),
        FractionallySizedBox(
          widthFactor: progress.fraction,
          child: Container(height: 4, color: colour ?? AppColors.accent),
        ),
      ]),
    );
  }
}

/// A goal in a list: title, slice progress, evidence and anything needing a look.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.goal, required this.onTap});
  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = goal.progress;
    return HoverSurface(
      onTap: onTap,
      radius: 10,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: kMobile ? 12 : 8, vertical: kMobile ? 12 : 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(goal.title.isEmpty ? '(untitled goal)' : goal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14.5 : 13,
                      weight: W.label, color: AppColors.fg1)),
            ),
            if (goal.attention != null) ...[
              const SizedBox(width: 8),
              AttentionChip(goal.attention!),
            ],
          ]),
          const SizedBox(height: 8),
          GoalProgressBar(p,
              colour: goal.attention == GoalAttention.readyToClose
                  ? AppColors.ok
                  : null),
          const SizedBox(height: 6),
          Row(children: [
            Text('${p.done} of ${p.total} slices',
                style: sans(11.5, color: AppColors.fg3, tabular: true)),
            const Spacer(),
            AppIcon('check', size: 11, color: AppColors.fg4),
            const SizedBox(width: 4),
            Text('${goal.evidence.done} of ${goal.evidence.total} evidenced',
                style: sans(11.5, color: AppColors.fg3, tabular: true)),
          ]),
        ]),
      ),
    );
  }
}

/// Open a goal: a sheet on a phone, a drawer panel on desktop.
Future<void> openGoalDetail(
    BuildContext context, DaemonClient client, String goalId) {
  if (kMobile) {
    return showModalBottomSheet<void>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        return SafeArea(
          top: false,
          child: SizedBox(
            height: (media.size.height - media.padding.top) * 0.9,
            child: Material(
              color: AppColors.bg,
              clipBehavior: Clip.antiAlias,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
              child: Column(children: [
                const SizedBox(height: 8),
                Container(
                  width: 30,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: GoalDetailScreen(
                    client: client,
                    goalId: goalId,
                    onClose: () => Navigator.of(sheet).pop(),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.generic,
    panelId: 'goal-$goalId',
    originClient: client,
    maxWidth: 640,
    maxHeight: 820,
    builder: (_, close) =>
        GoalDetailScreen(client: client, goalId: goalId, onClose: close),
  );
}

/// Open-goal feed shared by the board panel and the Goals tab.
class GoalsList extends StatefulWidget {
  const GoalsList({
    super.key,
    required this.client,
    this.padding = const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 16),
    this.shrinkWrap = false,
    this.onOpen,
  });

  final DaemonClient client;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final void Function(Goal goal)? onOpen;

  @override
  State<GoalsList> createState() => _GoalsListState();
}

class _GoalsListState extends State<GoalsList> {
  List<Goal>? _goals;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GoalsList old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) _load();
  }

  Future<void> _load() async {
    try {
      final goals = await widget.client.goals();
      if (mounted) {
        setState(() {
          _goals = goals;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goals;
    if (goals == null && _error == null) {
      return const Center(child: Spinner(size: 20));
    }
    if (goals == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load goals', style: sans(13, color: AppColors.fg2)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: _load),
        ]),
      );
    }
    if (goals.isEmpty) {
      return const EmptyState(
        icon: 'layers',
        title: 'No open goals',
        body: 'Outcomes your agents are working towards appear here.',
      );
    }
    final order = {
      GoalAttention.stalled: 0,
      GoalAttention.readyToClose: 1,
    };
    final sorted = [...goals]..sort(
        (a, b) => (order[a.attention] ?? 2).compareTo(order[b.attention] ?? 2));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        physics:
            widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: widget.padding,
        children: [
          for (final g in sorted)
            GoalRow(
              goal: g,
              onTap: () => widget.onOpen != null
                  ? widget.onOpen!(g)
                  : openGoalDetail(context, widget.client, g.id),
            ),
        ],
      ),
    );
  }
}
