import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Mission Control pinned at the top of the phone's Chats: what it is doing,
/// what it last noted, and what needs you, one tap from opening it.
class MissionControlCard extends StatefulWidget {
  final DaemonClient client;
  final SessionInfo session;
  final int waitingChats;
  final VoidCallback onOpen;

  const MissionControlCard({
    super.key,
    required this.client,
    required this.session,
    required this.waitingChats,
    required this.onOpen,
  });

  @override
  State<MissionControlCard> createState() => _MissionControlCardState();
}

class _MissionControlCardState extends State<MissionControlCard> {
  Map<String, dynamic>? _autonomy;
  List<MissionControlTask> _tasks = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _autonomy = widget.client.cachedMcAutonomy();
    _tasks = widget.client.cachedMcTasks() ?? const [];
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(MissionControlCard old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.client.mcAutonomy(),
        widget.client.mcTasks(archived: false),
      ]);
      if (!mounted) return;
      setState(() {
        _autonomy = results[0] as Map<String, dynamic>;
        _tasks = results[1] as List<MissionControlTask>;
      });
    } catch (_) {}
  }

  String _statusLine() {
    final status = widget.session.status;
    if (status == 'running') return 'Working on it now';
    if (status == 'waiting_for_input') return 'Waiting for you';
    final a = _autonomy;
    if (a != null && a['on'] == true) {
      if (a['in_quiet_hours'] == true) return 'Autonomous · quiet hours';
      final next = (a['next_round_at'] as num?)?.toInt();
      if (next != null && next > 0) {
        final t = DateTime.fromMillisecondsSinceEpoch(next * 1000);
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        return 'Autonomous · next round $hh:$mm';
      }
      return 'Autonomous';
    }
    return 'Plans, routes and follows up on your work';
  }

  Widget _chip(String label,
      {Color? dot, bool hollow = false, bool accent = false}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentBg : AppColors.surface2,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hollow ? Colors.transparent : dot,
              border: hollow ? Border.all(color: dot, width: 1.5) : null,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: sans(12,
                height: 16 / 12,
                color: accent ? AppColors.accent : AppColors.fg2)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final working = _tasks.where((t) => t.status == 'in_progress').length;
    final blocked = _tasks.where((t) => t.status == 'blocked').length;
    final needsYou = widget.waitingChats + blocked;
    final doneToday = _tasks
        .where((t) =>
            t.status == 'done' &&
            DateTime.fromMillisecondsSinceEpoch(t.updatedAt * 1000)
                .isAfter(today))
        .length;
    final note = (_autonomy?['last_round_summary'] as String?)?.trim() ?? '';
    final chips = <Widget>[
      if (working > 0) _chip('$working working', dot: AppColors.run),
      if (needsYou > 0)
        _chip('$needsYou needs you',
            dot: AppColors.accent, hollow: true, accent: true),
      if (doneToday > 0) _chip('$doneToday done today'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.border2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                        child: AppIcon('layers',
                            size: 17, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mission Control',
                            style: sans(16,
                                weight: FontWeight.w700,
                                spacing: -0.2,
                                height: 20 / 16,
                                color: AppColors.fg1)),
                        Text(_statusLine(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16 / 12, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                ]),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: serif(15, height: 23 / 15, color: AppColors.fg2)
                          .copyWith(fontStyle: FontStyle.italic)),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
