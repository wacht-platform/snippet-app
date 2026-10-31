import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';
import 'agent_wake_panel.dart';
import 'shell_nav.dart';

/// Every agent and session wake schedule, with keep-warm status below.
class WakesScreen extends StatefulWidget {
  const WakesScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;

  /// Phone drill-down back action; the screen then draws its own header.
  final VoidCallback? onBack;

  @override
  State<WakesScreen> createState() => _WakesScreenState();
}

class _WakesScreenState extends State<WakesScreen> {
  late Future<(WakeList, KeepWarmList?, List<CoordinationAgent>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(WakeList, KeepWarmList?, List<CoordinationAgent>)> _load() async {
    final c = widget.client;
    final wakes = await c.wakes();
    final warm = await c
        .keepWarm()
        .then<KeepWarmList?>((v) => v)
        .catchError((_) => null);
    final agents =
        await c.coordinationAgents().catchError((_) => <CoordinationAgent>[]);
    return (wakes, warm, agents);
  }

  void _refresh() => setState(() => _future = _load());

  String _name(String owner, List<CoordinationAgent> agents) {
    for (final a in agents) {
      if (a.id == owner) {
        return a.displayName.trim().isEmpty ? a.id : a.displayName.trim();
      }
    }
    return owner;
  }

  void _open(BuildContext ctx, String owner, String name,
      List<CoordinationAgent> agents) {
    final agent = agents.where((a) => a.id == owner).firstOrNull;
    showAgentWakeSettings(ctx,
        client: widget.client,
        owner: owner,
        name: name,
        agent: agent,
        point: lastPointerDown,
        onChanged: _refresh);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final body =
        FutureBuilder<(WakeList, KeepWarmList?, List<CoordinationAgent>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ListSkeleton();
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Text('${snap.error}',
                style: sans(13, height: 1.4, color: AppColors.danger)),
          );
        }
        final (wakes, warm, agents) = snap.data!;
        final warmOn = [
          for (final e in warm?.entries ?? const <KeepWarmEntry>[])
            if (e.enabled) e
        ];
        return PageBody(children: [
          if (wakes.wakes.isEmpty)
            const EmptyState(
              icon: 'calendar-clock',
              title: 'No wakes yet',
              body:
                  'Give an agent a timetable and a brief from its menu in the crew list. It reports back to Mission Control.',
            )
          else
            ListGroup(children: [
              for (final w in wakes.wakes) _wakeRow(context, w, agents),
            ]),
          if (warmOn.isNotEmpty) ...[
            const SizedBox(height: S.s20),
            const SectionLabel('Keep warm'),
            ListGroup(children: [
              for (final e in warmOn) _warmRow(context, e, agents),
            ]),
            if (warm != null && warm.calls7d > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.s4, S.s8, S.s4, 0),
                child: Text(
                    '${warm.calls7d} warm calls in the last 7 days, ${tokensLabel(warm.cacheReadTokens7d)} tokens read from cache.',
                    style: sans(12.5, color: AppColors.fg4)),
              ),
          ],
        ]);
      },
    );
    if (widget.onBack == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavBackRow(title: 'Wakes', onBack: widget.onBack!),
        Expanded(child: body),
      ],
    );
  }

  Widget _wakeRow(
      BuildContext context, WakeSchedule w, List<CoordinationAgent> agents) {
    final name = _name(w.owner, agents);
    final next = !w.enabled
        ? 'paused'
        : w.nextRunAt > 0
            ? 'next ${wakeWhen(w.nextRunAt)}'
            : '';
    final sub = [
      w.scheduleText.isEmpty ? w.schedule : w.scheduleText,
      if (next.isNotEmpty) next,
    ].join(' · ');
    return Builder(
      builder: (ctx) => ListRow(
        key: ValueKey('wake-${w.owner}'),
        title: name,
        subtitle: w.lastError != null ? '$sub · ${w.lastError}' : sub,
        leading: AppIcon('calendar-clock',
            size: 19, color: w.enabled ? AppColors.fg3 : AppColors.fg4),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (w.lastStatus != null)
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: wakeStatusColor(w.lastStatus),
                    shape: BoxShape.circle)),
          const SizedBox(width: S.s6),
          Text(w.ownerKind, style: sans(12.5, color: AppColors.fg4)),
        ]),
        onTap: () => _open(ctx, w.owner, name, agents),
      ),
    );
  }

  Widget _warmRow(
      BuildContext context, KeepWarmEntry e, List<CoordinationAgent> agents) {
    final name = _name(e.owner, agents);
    return Builder(
      builder: (ctx) => ListRow(
        key: ValueKey('warm-${e.owner}'),
        title: name,
        subtitle: e.reason ??
            (e.lastWarmAt != null
                ? 'Warmed ${wakeWhen(e.lastWarmAt!)}'
                : 'Every ${e.intervalMinutes} min'),
        leading: AppIcon('gauge', size: 19, color: AppColors.fg3),
        trailing:
            Text('${e.warms} warms', style: sans(12.5, color: AppColors.fg4)),
        onTap: () => _open(ctx, e.owner, name, agents),
      ),
    );
  }
}
