import 'package:flutter/material.dart';

import 'api.dart';
import 'crew_status.dart';
import 'mochi.dart';
import 'models.dart';
import 'notifications.dart' show onNotifTap;
import 'platform.dart';
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

Color crewColor(CrewState s) => switch (s) {
      CrewState.needsYou => AppColors.run,
      CrewState.working => AppColors.accent,
      CrewState.standingBy => AppColors.fg4,
    };

class CrewTile extends StatelessWidget {
  const CrewTile(this.entry, {super.key, this.size = 34});
  final CrewEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = crewColor(entry.state);
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(size * .29),
            border: Border.all(
                color: entry.state == CrewState.standingBy
                    ? AppColors.line
                    : c.withValues(alpha: .8)),
          ),
          alignment: Alignment.center,
          child: AgentMochi(entry.agent.id, size: size * .58),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bg, width: 2),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.lineStrong),
          borderRadius: BorderRadius.circular(R.xs + 2),
        ),
        child: Text(text, style: mono(11, color: AppColors.fg3)),
      );
}

/// Needs-you first, then working, then standing by; each group keeps the
/// agent order the daemon gave.
List<CrewEntry> crewOrdered(List<CrewEntry> c) => [
      for (final s in CrewState.values) ...c.where((e) => e.state == s),
    ];

class CrewRoster extends StatelessWidget {
  const CrewRoster({
    super.key,
    required this.entries,
    required this.onOpen,
    this.columns = 3,
  });

  final List<CrewEntry> entries;
  final ValueChanged<CoordinationAgent> onOpen;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final list = crewOrdered(entries);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final e in list)
            SizedBox(width: w, child: _Bubble(e, () => onOpen(e.agent))),
        ]);
      }),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.e, this.onTap);
  final CrewEntry e;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = crewColor(e.state);
    final idle = e.state == CrewState.standingBy;
    final tip = [
      e.agent.displayName,
      e.line,
      if (e.extra > 0) '+${e.extra} more sessions',
      if (e.agent.profile != null) e.agent.profile!,
    ].join('\n');
    return Tooltip(
      message: tip,
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: idle ? AppColors.line : c.withValues(alpha: .8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Stack(clipBehavior: Clip.none, children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                Opacity(
                    opacity: idle ? .75 : 1,
                    child: AgentMochi(e.agent.id, size: 36)),
                const SizedBox(height: 6),
                Text(e.agent.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: sans(11.5,
                        color: idle ? AppColors.fg3 : AppColors.fg1)),
              ]),
              Positioned(
                right: 2,
                top: -4,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class CrewBoard extends StatefulWidget {
  const CrewBoard({
    super.key,
    required this.entries,
    required this.client,
    required this.onOpen,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 96),
  });

  final List<CrewEntry> entries;
  final DaemonClient client;
  final ValueChanged<CoordinationAgent> onOpen;
  final EdgeInsets padding;

  @override
  State<CrewBoard> createState() => _CrewBoardState();
}

class _CrewBoardState extends State<CrewBoard> {
  CrewState? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.entries;
    final shown = crewOrdered(
        all.where((e) => _filter == null || e.state == _filter).toList());
    Widget pill(String label, CrewState? s, int n) {
      final on = _filter == s;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: () => setState(() => _filter = s),
          child: Container(
            constraints: BoxConstraints(minHeight: kMobile ? 36 : 28),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.surface3 : null,
              border: Border.all(color: AppColors.lineStrong),
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text('$label $n',
                style: sans(12.5,
                    weight: W.label,
                    color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 720 ? 2 : 1;
      const gap = 10.0;
      final w =
          (box.maxWidth - widget.padding.horizontal - gap * (cols - 1)) / cols;
      return ListView(padding: widget.padding, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            pill('All', null, all.length),
            pill('Needs you', CrewState.needsYou,
                crewCount(all, CrewState.needsYou)),
            pill('Working', CrewState.working,
                crewCount(all, CrewState.working)),
            pill('Standing by', CrewState.standingBy,
                crewCount(all, CrewState.standingBy)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(kMobile ? 16 : 12),
          ),
          child: Row(children: [
            const MochiIcon(color: Color(0xFFB9C6FF), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mission Control',
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  Text(crewSummary(all),
                      style: sans(12.5, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: gap, runSpacing: gap, children: [
          for (final e in shown)
            SizedBox(
              width: w,
              child: _CrewCard(
                  key: ValueKey('crew-${e.agent.id}'),
                  entry: e,
                  client: widget.client,
                  onOpen: () => widget.onOpen(e.agent)),
            ),
        ]),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
                child: Text('Nobody here right now',
                    style: sans(13, color: AppColors.fg3))),
          ),
      ]);
    });
  }
}

class _CrewCard extends StatefulWidget {
  const _CrewCard(
      {super.key,
      required this.entry,
      required this.client,
      required this.onOpen});
  final CrewEntry entry;
  final DaemonClient client;
  final VoidCallback onOpen;

  @override
  State<_CrewCard> createState() => _CrewCardState();
}

class _CrewCardState extends State<_CrewCard> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _send(QuickAction a) async {
    final s = widget.entry.lead;
    if (s == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await quickSend(client: widget.client, session: s.id, action: a);
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  void _openChat() {
    final s = widget.entry.lead;
    if (s == null) return widget.onOpen();
    onNotifTap?.call({
      'kind': 'waiting',
      'url': widget.client.baseUrl,
      'session': s.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final needs = e.state == CrewState.needsYou;
    final profile = e.agent.profile;
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kMobile ? 16 : 12),
        side: BorderSide(
            color:
                needs ? AppColors.run.withValues(alpha: .8) : AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: EdgeInsets.all(kMobile ? 14 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CrewTile(e, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.agent.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(14, weight: W.label, color: AppColors.fg1)),
                      if (e.agent.role.trim().isNotEmpty)
                        Text(e.agent.role.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5, color: AppColors.fg3)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(e.line,
                  maxLines: needs ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      height: 1.4,
                      color: needs ? AppColors.run : AppColors.fg2)),
              if (needs) ...[
                const SizedBox(height: 10),
                Wrap(spacing: S.s8, runSpacing: S.s8, children: [
                  if (e.isApproval) ...[
                    Btn('Approve',
                        small: true,
                        disabled: _busy,
                        onTap: () => _send(const QuickApprove())),
                    Btn('Deny',
                        small: true,
                        variant: BtnVariant.secondary,
                        disabled: _busy,
                        onTap: () => _send(const QuickDeny())),
                  ] else
                    Btn('Answer', small: true, onTap: _openChat),
                  if (e.isApproval)
                    Btn('Open chat',
                        small: true,
                        variant: BtnVariant.secondary,
                        onTap: _openChat),
                ]),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: S.s6),
                    child: Text("Couldn't send. Open chat",
                        style: sans(12, color: AppColors.danger)),
                  ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Text(
                    '${e.sessions.length} session${e.sessions.length == 1 ? '' : 's'}',
                    style: sans(12, color: AppColors.fg4)),
                const Spacer(),
                if (profile != null) _Chip(profile),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
