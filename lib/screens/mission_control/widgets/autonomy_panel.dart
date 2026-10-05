import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api.dart';
import '../../../theme.dart';
import '../../../widgets.dart';

String _relative(int? epoch, {bool future = false}) {
  if (epoch == null) return '';
  final secs = (epoch - DateTime.now().millisecondsSinceEpoch ~/ 1000).abs();
  final text = secs < 60
      ? 'under a minute'
      : secs < 3600
          ? '${secs ~/ 60}m'
          : secs < 86400
              ? '${secs ~/ 3600}h ${(secs % 3600) ~/ 60}m'
              : '${secs ~/ 86400}d';
  return future ? 'in $text' : '$text ago';
}

String autonomyStatusLine(Map<String, dynamic>? autonomy) {
  if (autonomy == null) return '';
  if (autonomy['on'] != true) return 'Autonomy off';
  final next = autonomy['next_round_at'] as int?;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final parts = <String>['Autonomous'];
  if (autonomy['in_quiet_hours'] == true) parts.add('quiet hours');
  if (next != null && next > now)
    parts.add('next check ${_relative(next, future: true)}');
  return parts.join(' · ');
}

/// Header chip: shows whether Mission Control is autonomous and opens the panel.
class AutonomyChip extends StatefulWidget {
  final DaemonClient client;
  final void Function(Widget panel) open;
  const AutonomyChip({super.key, required this.client, required this.open});

  @override
  State<AutonomyChip> createState() => _AutonomyChipState();
}

class _AutonomyChipState extends State<AutonomyChip> {
  Map<String, dynamic>? _autonomy;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final autonomy = await widget.client.mcAutonomy();
      if (mounted) setState(() => _autonomy = autonomy);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final autonomy = _autonomy;
    if (autonomy == null) return const SizedBox.shrink();
    final on = autonomy['on'] == true;
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.open(AutonomyPanel(
            client: widget.client,
            initial: autonomy,
            onChanged: (d) => setState(() => _autonomy = d))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.okBg : AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: on ? AppColors.ok : AppColors.fg4,
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(on ? 'Autonomous' : 'Autonomy off',
                style: TS.label(on ? AppColors.ok : AppColors.fg3)),
          ]),
        ),
      ),
    );
  }
}

class AutonomyPanel extends StatefulWidget {
  final DaemonClient client;
  final Map<String, dynamic>? initial;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final bool embedded;
  const AutonomyPanel(
      {super.key,
      required this.client,
      this.initial,
      this.onChanged,
      this.embedded = false});

  @override
  State<AutonomyPanel> createState() => _AutonomyPanelState();
}

class _AutonomyPanelState extends State<AutonomyPanel> {
  late Map<String, dynamic> _autonomy = widget.initial ?? const {};

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.client.mcAutonomy();
      if (mounted) setState(() => _autonomy = loaded);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _error;

  static const _rhythms = [
    (15, '15 min'),
    (30, '30 min'),
    (60, '1 hour'),
    (120, '2 hours')
  ];
  static const _quiet = [
    ('', 'None'),
    ('22:00-08:00', '22–08'),
    ('23:00-07:00', '23–07'),
    ('00:00-09:00', '00–09'),
  ];

  Future<void> _set(Map<String, dynamic> changes) async {
    final before = _autonomy;
    setState(() {
      _autonomy = {..._autonomy, ...changes};
      _error = null;
    });
    try {
      final saved = await widget.client.mcSetAutonomy(changes);
      if (!mounted) return;
      setState(() => _autonomy = saved);
      widget.onChanged?.call(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _autonomy = before;
          _error = '$e';
        });
      }
    }
  }

  String get _quietKey {
    final start = _autonomy['quiet_start'] as String?;
    final end = _autonomy['quiet_end'] as String?;
    if (start == null || end == null) return '';
    return '$start-$end';
  }

  @override
  Widget build(BuildContext context) {
    final on = _autonomy['on'] == true;
    final followups = (_autonomy['followups'] as List? ?? const []).cast<Map>();
    final lastAt = _autonomy['last_round_at'] as int?;
    final summary = _autonomy['last_round_summary'] as String?;
    final held = (_autonomy['held_pings'] as num?)?.toInt() ?? 0;
    final rhythm = (_autonomy['round_minutes'] as num?)?.toInt() ?? 30;
    final quietKey = _quietKey;
    final quietItems = [
      ..._quiet,
      if (!_quiet.any((q) => q.$1 == quietKey))
        (quietKey, quietKey.replaceAll('-', '–')),
    ];
    final children = <Widget>[
      if (!widget.embedded) ...[
        Text('Autonomous Mission Control', style: TS.sectionTitle()),
        const SizedBox(height: 6),
      ],
      Text(
          'When autonomous, Mission Control works like a chief of staff while you are away: it checks on running work, verifies results, retries and re-routes, answers workers when it can, and pings your phone only for decisions, finished work and problems.',
          style: TS.meta().copyWith(height: 1.45)),
      const SizedBox(height: 16),
      AppToggle(
        on: on,
        onChanged: (v) => _set({'on': v}),
        label: on ? 'Autonomous' : 'Autonomy off',
        sub: autonomyStatusLine(_autonomy),
      ),
      const SizedBox(height: 20),
      Text('Check in every', style: TS.label(AppColors.fg2)),
      const SizedBox(height: 8),
      Pills<int>(
        items: _rhythms,
        selected: rhythm,
        onSelect: (v) => _set({'round_minutes': v}),
      ),
      const SizedBox(height: 6),
      Text(
          'Reports and worker questions wake it at once. The regular check only runs when something changed, so quiet hours cost nothing.',
          style: TS.meta().copyWith(height: 1.4)),
      const SizedBox(height: 20),
      Text('Quiet hours', style: TS.label(AppColors.fg2)),
      const SizedBox(height: 8),
      Pills<String>(
        items: quietItems,
        selected: quietKey,
        onSelect: (v) {
          final parts = v.split('-');
          _set({
            'quiet_start': parts.length == 2 ? parts[0] : '',
            'quiet_end': parts.length == 2 ? parts[1] : '',
          });
        },
      ),
      const SizedBox(height: 6),
      Text(
          held > 0
              ? '$held ping${held == 1 ? '' : 's'} held until quiet hours end.'
              : 'Non-urgent pings wait until quiet hours end; urgent ones come through.',
          style: TS.meta().copyWith(height: 1.4)),
      if (lastAt != null) ...[
        const SizedBox(height: 20),
        Text('Last round', style: TS.label(AppColors.fg2)),
        const SizedBox(height: 6),
        Text(
            [
              _relative(lastAt),
              if (summary != null && summary.isNotEmpty) summary
            ].join(' · '),
            style: TS.ui()),
      ],
      if (followups.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Follow-ups it scheduled', style: TS.label(AppColors.fg2)),
        const SizedBox(height: 8),
        for (final f in followups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 72,
                child: Text(_relative(f['due_at'] as int?, future: true),
                    style: TS.meta()),
              ),
              Expanded(child: Text('${f['note'] ?? ''}', style: TS.ui())),
            ]),
          ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(_error!, style: TS.meta().copyWith(color: AppColors.danger)),
      ],
    ];
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: children);
  }
}
