import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Pending handoffs awaiting acknowledgement. A successor cannot take the turn
/// until it acknowledges the exact recorded context, so this is where a human
/// reviews what is waiting and clears it.
class CoordinationHandoffsScreen extends StatefulWidget {
  const CoordinationHandoffsScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.refreshSignal,
  });

  final DaemonClient client;

  /// When embedded in the hub, suppress our own Scaffold/AppBar.
  final bool embedded;

  /// Bumped by the host to request a refetch.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<CoordinationHandoffsScreen> createState() =>
      _CoordinationHandoffsScreenState();
}

class _CoordinationHandoffsScreenState
    extends State<CoordinationHandoffsScreen> {
  List<CoordinationHandoff> handoffs = const [];
  String? error;
  bool loading = true;

  /// Handoff ids currently being acknowledged, so a row can show progress and
  /// can't be double-submitted.
  final Set<String> acknowledging = {};

  @override
  void initState() {
    super.initState();
    refresh();
    widget.refreshSignal?.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() => refresh();

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      handoffs = await widget.client.coordinationHandoffs();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _acknowledge(CoordinationHandoff handoff) async {
    if (acknowledging.contains(handoff.id)) return;
    setState(() => acknowledging.add(handoff.id));
    try {
      await widget.client.acknowledgeCoordinationHandoff(handoff.id);
      if (!mounted) return;
      toast(context, 'Handoff acknowledged');
      setState(() => handoffs =
          handoffs.where((h) => h.id != handoff.id).toList(growable: false));
    } catch (e) {
      if (mounted) toast(context, 'Could not acknowledge: $e', danger: true);
    } finally {
      if (mounted) setState(() => acknowledging.remove(handoff.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
          onRefresh: refresh,
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                      children: [
                        Text('Could not load handoffs',
                            textAlign: TextAlign.center,
                            style: sans(17,
                                weight: FontWeight.w600, color: AppColors.fg1)),
                        const SizedBox(height: 8),
                        Text(error!,
                            textAlign: TextAlign.center,
                            style: sans(13, color: AppColors.fg3)),
                        const SizedBox(height: 18),
                        Center(child: Btn('Retry', onTap: refresh)),
                      ],
                    )
                  : handoffs.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 48, color: AppColors.fg3),
                            const SizedBox(height: 18),
                            Text('Nothing awaiting acknowledgement',
                                textAlign: TextAlign.center,
                                style: sans(17,
                                    weight: FontWeight.w600,
                                    color: AppColors.fg1)),
                            const SizedBox(height: 8),
                            Text(
                                'Handoffs appear here when one agent transfers work to a successor.',
                                textAlign: TextAlign.center,
                                style: sans(13,
                                    color: AppColors.fg3, height: 1.45)),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          itemCount: handoffs.length,
                          separatorBuilder: (_, __) => Divider(
                              color: AppColors.border, height: 1),
                          itemBuilder: (_, index) => _HandoffCard(
                            handoff: handoffs[index],
                            busy: acknowledging.contains(handoffs[index].id),
                            onAcknowledge: () => _acknowledge(handoffs[index]),
                          ),
                        ),
        );

    // Embedded in the hub: the host owns the chrome.
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Handoffs'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: body,
    );
  }
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({
    required this.handoff,
    required this.busy,
    required this.onAcknowledge,
  });

  final CoordinationHandoff handoff;
  final bool busy;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(handoff.objective,
                      style: sans(15,
                          weight: FontWeight.w600, color: AppColors.fg1)),
                ),
                Text(handoff.contextMode.replaceAll('_', ' '),
                    style: sans(11, color: AppColors.fg4)),
              ],
            ),
            const SizedBox(height: 8),
            _Line('From', handoff.sourceAssignmentId),
            _Line('To', handoff.targetAssignmentId),
            _Line('Session', handoff.sessionId),
            if (handoff.completedSummary.trim().isNotEmpty)
              _Line('Done', handoff.completedSummary),
            if (handoff.nextAction.trim().isNotEmpty)
              _Line('Next', handoff.nextAction),
            if (handoff.risks.isNotEmpty)
              _Line('Risks', handoff.risks.join('; ')),
            if (handoff.blockers.isNotEmpty)
              _Line('Blockers', handoff.blockers.join('; ')),
            const SizedBox(height: 12),
            Btn(
              busy ? 'Acknowledging…' : 'Acknowledge',
              variant: BtnVariant.secondary,
              icon: 'check',
              disabled: busy,
              onTap: onAcknowledge,
            ),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(label, style: sans(12, color: AppColors.fg4)),
            ),
            Expanded(
              child: Text(value,
                  style: sans(12.5, color: AppColors.fg2, height: 1.4)),
            ),
          ],
        ),
      );
}
