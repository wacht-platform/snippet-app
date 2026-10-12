import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';

/// Mission Control pinned at the top of the Chats list: what it is doing, one
/// tap from opening it.
class MissionControlCard extends StatefulWidget {
  final DaemonClient client;
  final SessionInfo session;
  final VoidCallback onOpen;

  const MissionControlCard({
    super.key,
    required this.client,
    required this.session,
    required this.onOpen,
  });

  @override
  State<MissionControlCard> createState() => _MissionControlCardState();
}

class _MissionControlCardState extends State<MissionControlCard> {
  Map<String, dynamic>? _autonomy;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _autonomy = widget.client.cachedMcAutonomy();
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
      final autonomy = await widget.client.mcAutonomy();
      if (!mounted) return;
      setState(() => _autonomy = autonomy);
    } catch (_) {}
  }

  String _statusLine() {
    final status = widget.session.status;
    if (status == 'running') return 'Working now';
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

  @override
  Widget build(BuildContext context) {
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
          child: AnimatedSize(
            duration: Motion.base,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
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
                          SwapText(_statusLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12,
                                  height: 16 / 12, color: AppColors.fg3)),
                        ],
                      ),
                    ),
                    AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
