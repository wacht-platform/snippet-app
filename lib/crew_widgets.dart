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

String _crewGroup(CrewState s) => switch (s) {
      CrewState.needsYou => 'Needs you',
      CrewState.working => 'Working',
      CrewState.standingBy => 'Standing by',
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

Color _lineColor(CrewState s) => switch (s) {
      CrewState.needsYou => AppColors.run,
      CrewState.working => AppColors.accent,
      CrewState.standingBy => AppColors.fg3,
    };

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
    this.onBoard,
  });

  final List<CrewEntry> entries;
  final ValueChanged<CoordinationAgent> onOpen;
  final VoidCallback? onBoard;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in CrewState.values)
        if (entries.any((e) => e.state == s)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 12, 2),
            child: Text(
                '${_crewGroup(s).toUpperCase()} · ${crewCount(entries, s)}',
                style: sans(10.5, color: AppColors.fg4, spacing: 0.8)),
          ),
          for (final e in entries.where((e) => e.state == s))
            _RosterRow(e, () => onOpen(e.agent)),
        ],
    ]);
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow(this.e, this.onTap);
  final CrewEntry e;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = e.agent.profile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md - 2),
        onTap: onTap,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 6, vertical: kMobile ? 8 : 5),
          child: Row(children: [
            CrewTile(e, size: kMobile ? 40 : 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.agent.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14.5 : 13.5,
                          weight: W.label, color: AppColors.fg1)),
                  Row(children: [
                    Flexible(
                      child: Text(e.line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12.5, color: _lineColor(e.state))),
                    ),
                    if (e.extra > 0)
                      Text(' +${e.extra}',
                          style: sans(12.5, color: AppColors.fg4)),
                  ]),
                ],
              ),
            ),
            if (profile != null) ...[
              const SizedBox(width: 6),
              _Chip(profile),
            ],
          ]),
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
