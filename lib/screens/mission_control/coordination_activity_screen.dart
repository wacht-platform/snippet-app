import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// "Who is active where": the sessions that currently have a turn holder, plus
/// the outstanding assignments. Answers the question a chat reply can't — which
/// agent is working in which session right now, and what work is queued.
class CoordinationActivityScreen extends StatefulWidget {
  const CoordinationActivityScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.refreshSignal,
  });

  final DaemonClient client;

  /// When embedded in the hub, suppress our own Scaffold/AppBar and let the
  /// host supply chrome.
  final bool embedded;

  /// Bumped by the host to request a refetch.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<CoordinationActivityScreen> createState() =>
      _CoordinationActivityScreenState();
}

class _CoordinationActivityScreenState
    extends State<CoordinationActivityScreen> {
  List<CoordinationLease> leases = const [];
  List<CoordinationAssignment> assignments = const [];

  /// agent id → display name, so the view names people rather than ids.
  Map<String, String> agentNames = const {};
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
    // Host-driven refresh (the hub's toolbar button).
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
      // Fetch together so the view is consistent, and so a failure surfaces
      // rather than showing half the picture.
      final results = await Future.wait([
        widget.client.coordinationActiveLeases(),
        widget.client.coordinationAssignments(),
        widget.client.coordinationAgents(),
      ]);
      leases = results[0] as List<CoordinationLease>;
      assignments = results[1] as List<CoordinationAssignment>;
      agentNames = {
        for (final a in results[2] as List<CoordinationAgent>)
          a.id: a.displayName,
      };
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  String _name(String agentId) {
    final name = agentNames[agentId];
    return (name == null || name.isEmpty) ? agentId : name;
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
                    Text('Could not load activity',
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _SectionHeader(title: 'Active now', count: leases.length),
                    if (leases.isEmpty)
                      _Empty('No session has a turn holder. Agents appear here '
                          'while they hold a lease.')
                    else
                      for (final lease in leases)
                        _LeaseRow(
                          lease: lease,
                          agentName: _name(lease.agentId),
                        ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                        title: 'Assignments', count: assignments.length),
                    if (assignments.isEmpty)
                      _Empty('No work has been handed out yet.')
                    else
                      for (final assignment in assignments)
                        _AssignmentRow(
                          assignment: assignment,
                          agentName: _name(assignment.agentId),
                        ),
                  ],
                ),
    );

    // Embedded in the hub: the host owns the chrome.
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: AppIcon('refresh', size: 19, color: AppColors.fg2),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: sans(11,
                    weight: FontWeight.w600,
                    color: AppColors.fg4,
                    spacing: 0.6)),
            const SizedBox(width: 8),
            Text('$count', style: sans(11, color: AppColors.fg4)),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child:
            Text(message, style: sans(12.5, color: AppColors.fg4, height: 1.4)),
      );
}

/// One active turn holder: which agent, in which session, since when.
class _LeaseRow extends StatelessWidget {
  const _LeaseRow({required this.lease, required this.agentName});

  final CoordinationLease lease;
  final String agentName;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(agentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14,
                          weight: FontWeight.w600, color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Text(lease.sessionId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3, height: 1.35)),
                  const SizedBox(height: 2),
                  Text('holding since ${_shortTime(lease.acquiredAt)}',
                      style: sans(11.5, color: AppColors.fg4)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// One assignment: its state, the agent it belongs to, and its scope.
class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.assignment, required this.agentName});

  final CoordinationAssignment assignment;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final status = assignment.status;
    final color = switch (status) {
      'completed' => AppColors.ok,
      'blocked' || 'failed' || 'cancelled' => AppColors.danger,
      'offered' => AppColors.fg3,
      _ => AppColors.run,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        assignment.scope.isEmpty
                            ? assignment.id
                            : assignment.scope,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13.5, color: AppColors.fg1)),
                  ),
                  Text(status, style: sans(11.5, color: color)),
                ]),
                const SizedBox(height: 3),
                Text('$agentName · ${assignment.sessionId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5, color: AppColors.fg4)),
                if (assignment.definitionOfDone.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(assignment.definitionOfDone,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// RFC3339 → a short local time. Returns the raw value if it can't be parsed,
/// so a bad timestamp is visible rather than silently blank.
String _shortTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return sameDay ? '$hh:$mm' : '${local.month}/${local.day} $hh:$mm';
}
