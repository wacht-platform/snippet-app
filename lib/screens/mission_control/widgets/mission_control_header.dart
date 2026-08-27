/// Session-style title row. Status line under the title, same padding as
/// `_mobileHeader` in session.dart. The pulsing avatar and stat pills were
/// a different product — keep the live status as a subtitle instead.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_state.dart';
import '../mobile/mobile_mc.dart' show showNotificationInbox;

class MissionControlHeader extends StatelessWidget {
  const MissionControlHeader.compact({
    super.key,
    required this.state,
  }) : _compact = true;
  const MissionControlHeader.full({
    super.key,
    required this.state,
  }) : _compact = false;

  final MissionControlState state;
  final bool _compact;

  @override
  Widget build(BuildContext context) {
    final agent = state.agent;
    final status = switch (agent.state) {
      AgentState.idle => 'Idle',
      AgentState.working => 'Running',
      AgentState.asking => 'Needs input',
      AgentState.error => 'Error',
    };
    final facts = <String>[status];
    if (agent.detail.isNotEmpty && agent.state != AgentState.idle) {
      facts.add(agent.detail);
    }
    final unread = state.unresolvedNotificationCount;
    return Container(
      padding: EdgeInsets.fromLTRB(_compact ? 12 : 16, 10, 8, 10),
      decoration: BoxDecoration(
        color: readingBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Mission Control',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(_compact ? 17 : 16.5,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Row(children: [
                  if (state.loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: AppColors.fg3,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      state.loading ? 'Connecting…' : facts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        Stack(clipBehavior: Clip.none, children: [
          IconBtn('bell',
              size: 40,
              iconSize: 18,
              tooltip: 'Inbox',
              onTap: () => showNotificationInbox(context, state)),
          if (unread > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle),
              ),
            ),
        ]),
      ]),
    );
  }
}
