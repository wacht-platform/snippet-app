import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
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
    final status = widget.session.status;
    final dot = status == 'running' ? AppColors.run : AppColors.accent;
    if (!kMobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Mission Control', style: sans(13, color: AppColors.fg1)),
                const SizedBox(width: 8),
                Expanded(
                  child: SwapText(_statusLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11.5, color: AppColors.fg4)),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? 10 : 6),
      child: Material(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 18 : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                kMobile ? 18 : 14, kMobile ? 14 : 11, kMobile ? 12 : 10,
                kMobile ? 14 : 11),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mission Control',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 16 : 14,
                            spacing: -0.2,
                            height: kMobile ? 21 / 16 : 19 / 14,
                            color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: SwapText(_statusLine(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16 / 12, color: AppColors.fg3)),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }
}
