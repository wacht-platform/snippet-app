import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api.dart';
import '../../../platform.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import '../../shell_nav.dart';

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

Future<Map<String, dynamic>> loadAutonomy(DaemonClient client) async {
  final loaded = await client.mcAutonomy();
  final local = DateTime.now().timeZoneOffset.inMinutes;
  if ((loaded['utc_offset_minutes'] as num?)?.toInt() != local) {
    return client.mcSetAutonomy({});
  }
  return loaded;
}

String _offsetLabel(int? minutes) {
  final m = minutes ?? DateTime.now().timeZoneOffset.inMinutes;
  final sign = m < 0 ? '−' : '+';
  final h = m.abs() ~/ 60;
  final mm = (m.abs() % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$mm';
}

String autonomyStatusLine(Map<String, dynamic>? autonomy) {
  if (autonomy == null) return '';
  if (autonomy['on'] != true) return 'Wakes off';
  final next = autonomy['next_round_at'] as int?;
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final parts = <String>['Wakes on'];
  if (autonomy['in_quiet_hours'] == true) parts.add('quiet hours');
  if (next != null && next > now)
    parts.add('next wake ${_relative(next, future: true)}');
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
      final autonomy = await loadAutonomy(widget.client);
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
            borderRadius: BorderRadius.circular(R.sm),
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
            Text(on ? 'Wakes on' : 'Wakes off',
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
  final VoidCallback? onBack;
  const AutonomyPanel(
      {super.key,
      required this.client,
      this.initial,
      this.onChanged,
      this.embedded = false,
      this.onBack});

  @override
  State<AutonomyPanel> createState() => _AutonomyPanelState();
}

class _AutonomyPanelState extends State<AutonomyPanel> {
  late Map<String, dynamic> _autonomy =
      widget.initial ?? widget.client.cachedMcAutonomy() ?? const {};

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _load();
  }

  @override
  void didUpdateWidget(covariant AutonomyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.baseUrl != widget.client.baseUrl) {
      _autonomy =
          widget.initial ?? widget.client.cachedMcAutonomy() ?? const {};
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final loaded = await loadAutonomy(widget.client);
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

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface1 : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _stat(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface2 : AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(text, style: sans(12, color: AppColors.fg2)),
      );

  int? get _offset => (_autonomy['utc_offset_minutes'] as num?)?.toInt();

  String _clock(int? at) {
    if (at == null) return '';
    final offset = _offset ?? DateTime.now().timeZoneOffset.inMinutes;
    final t = DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true)
        .add(Duration(minutes: offset));
    final n = DateTime.now().toUtc().add(Duration(minutes: offset));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${sameDay ? hm : '${days[t.weekday - 1]} $hm'} ${_offsetLabel(offset)}';
  }

  Widget _wakeRow(Map w) {
    final at = (w['due_at'] as num?)?.toInt();
    final general = w['next_wake'] == true;
    final meta = [
      _relative(at, future: true),
      _clock(at),
      if (general) 'Next check-in',
    ].where((p) => p.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${w['note'] ?? ''}',
            style: sans(13.5, height: 1.45, color: AppColors.fg1)),
        const SizedBox(height: 4),
        Text(meta, style: sans(12, tabular: true, color: AppColors.fg4)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final on = _autonomy['on'] == true;
    final wakes =
        ((_autonomy['wakes'] ?? _autonomy['followups']) as List? ?? const [])
            .cast<Map>();
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
        Text('Automated wakes', style: TS.sectionTitle()),
        const SizedBox(height: 6),
      ],
      if (!kMobile) ...[
        Text(
            'With automated wakes on, Mission Control is woken on a schedule while you are away, like a chief of staff checking in: it looks at running work, verifies results, retries and re-routes, answers workers when it can, and pings your phone only for decisions, finished work and problems.',
            style: TS.meta().copyWith(height: 1.45)),
        const SizedBox(height: 16),
      ],
      AppToggle(
        flat: kMobile,
        on: on,
        onChanged: (v) => _set({'on': v}),
        label: on ? 'Wakes on' : 'Wakes off',
        sub: on
            ? () {
                final detail = autonomyStatusLine(_autonomy)
                    .replaceFirst(RegExp(r'^Wakes on( · )?'), '');
                return detail.isEmpty
                    ? 'Checks in on running work while you are away'
                    : detail;
              }()
            : 'Mission Control only acts when you message it',
      ),
      const SizedBox(height: 20),
      Text('Wake every', style: TS.label(AppColors.fg2)),
      const SizedBox(height: 8),
      Pills<int>(
        items: _rhythms,
        selected: rhythm,
        onSelect: (v) => _set({'round_minutes': v}),
      ),
      if (!kMobile) ...[
        const SizedBox(height: 6),
        Text(
            'Reports and worker questions wake it at once. A scheduled wake only runs when something changed, so quiet hours cost nothing.',
            style: TS.meta().copyWith(height: 1.4)),
      ],
      const SizedBox(height: 20),
      Text('Quiet hours · ${_offsetLabel(_offset)}',
          style: TS.label(AppColors.fg2)),
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
      if (!kMobile || held > 0) ...[
        const SizedBox(height: 6),
        Text(
            held > 0
                ? '$held ping${held == 1 ? '' : 's'} held until quiet hours end.'
                : 'Non-urgent pings wait until quiet hours end; urgent ones come through.',
            style: TS.meta().copyWith(height: 1.4)),
      ],
      if (lastAt != null) ...[
        const SizedBox(height: 22),
        _card(children: [
          Row(children: [
            AppIcon('activity', size: 13, color: AppColors.fg3),
            const SizedBox(width: 6),
            Text('Last wake', style: TS.label(AppColors.fg2)),
            const Spacer(),
            Text(_relative(lastAt), style: sans(12, color: AppColors.fg4)),
          ]),
          if (summary != null && summary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final part in summary.split(' · '))
                if (part.trim().isNotEmpty) _stat(part.trim()),
            ]),
          ],
        ]),
      ],
      if (wakes.isNotEmpty) ...[
        const SizedBox(height: 12),
        _card(children: [
          Row(children: [
            AppIcon('clock', size: 13, color: AppColors.fg3),
            const SizedBox(width: 6),
            Text('Wake-ups it scheduled', style: TS.label(AppColors.fg2)),
            const Spacer(),
            Text('${wakes.length}', style: sans(12, color: AppColors.fg4)),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < wakes.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _wakeRow(wakes[i]),
          ],
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(_error!, style: TS.meta().copyWith(color: AppColors.danger)),
      ],
    ];
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Automated wakes', onBack: widget.onBack!),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: children,
            ),
          ),
        ],
      );
    }
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
