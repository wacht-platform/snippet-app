import 'package:flutter/material.dart';

import '../../api.dart';
import '../../theme.dart';

import 'coordination_activity_screen.dart';
import 'coordination_agent_directory.dart';
import 'coordination_board_screen.dart';
import 'coordination_handoffs_screen.dart';

/// One home for coordination, instead of four unrelated drawers.
///
/// Was: three sibling rows in the session menu (Agents, Coordination board,
/// Coordination activity) plus Handoffs nested *inside* the board's app bar, so
/// reaching a handoff meant opening a panel and then opening a panel from it.
/// Now: one destination with a segmented header.
enum CoordinationSection {
  active('Active'),
  agents('Agents'),
  board('Board'),
  handoffs('Handoffs');

  const CoordinationSection(this.label);
  final String label;
}

class CoordinationHub extends StatefulWidget {
  const CoordinationHub({
    super.key,
    required this.client,
    this.initialSection = CoordinationSection.active,
  });

  final DaemonClient client;
  final CoordinationSection initialSection;

  @override
  State<CoordinationHub> createState() => _CoordinationHubState();
}

class _CoordinationHubState extends State<CoordinationHub> {
  late CoordinationSection _section = widget.initialSection;

  /// Bumped to ask the visible section to refetch. One shared notifier rather
  /// than a callback per section, so the hub does not need to reach into each
  /// child's state.
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refreshSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Coordination'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _refreshSignal.value++,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: _SectionBar(
              section: _section,
              onSelect: (s) => setState(() => _section = s),
            ),
          ),
        ),
        // IndexedStack keeps every section alive, so switching tabs does not
        // refetch or lose scroll position.
        body: IndexedStack(
          index: _section.index,
          children: [
            CoordinationActivityScreen(
              client: widget.client,
              embedded: true,
              refreshSignal: _refreshSignal,
            ),
            CoordinationAgentDirectory(
              client: widget.client,
              embedded: true,
              refreshSignal: _refreshSignal,
            ),
            CoordinationBoardScreen(
              client: widget.client,
              threadId: 'system',
              actorId: 'human',
              embedded: true,
              refreshSignal: _refreshSignal,
            ),
            CoordinationHandoffsScreen(
              client: widget.client,
              embedded: true,
              refreshSignal: _refreshSignal,
            ),
          ],
        ),
      );
}

/// Compact segmented header. Deliberately not Material chips: a quiet row of
/// labels where only the selected one lifts, so it reads as navigation rather
/// than a row of buttons.
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.section, required this.onSelect});

  final CoordinationSection section;
  final ValueChanged<CoordinationSection> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final s in CoordinationSection.values)
              _Segment(
                label: s.label,
                selected: s == section,
                onTap: () => onSelect(s),
              ),
          ],
        ),
      );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.md),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Text(
                label,
                style: sans(13,
                    weight: selected ? W.label : W.body,
                    color: selected ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
          ),
        ),
      );
}
