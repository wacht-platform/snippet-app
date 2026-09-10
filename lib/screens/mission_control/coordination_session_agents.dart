import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// "When is an agent active in this session" — the answer, for any session.
///
/// Two halves on purpose: [SessionAgentsList] is pure and therefore testable
/// without a network, and [SessionAgentsPanel] owns fetch/refresh. Leases are
/// per-session, so this works in an ordinary chat too — not just Mission
/// Control.

/// How often the panel re-checks while open. Presence is not worth a poll per
/// second; the lease changes on the scale of a turn.
const _refreshInterval = Duration(seconds: 20);

class SessionAgentsPanel extends StatefulWidget {
  const SessionAgentsPanel({
    super.key,
    required this.client,
    required this.sessionId,
  });

  final DaemonClient client;
  final String sessionId;

  @override
  State<SessionAgentsPanel> createState() => _SessionAgentsPanelState();
}

class _SessionAgentsPanelState extends State<SessionAgentsPanel> {
  List<CoordinationSessionAgent> agents = const [];
  String? error;
  bool loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    refresh();
    // Keep presence honest while the panel is open, and stop when it closes.
    _timer = Timer.periodic(_refreshInterval, (_) => refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!quiet && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final fetched = await widget.client.coordinationSessionAgents(
        widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        agents = fetched;
        error = null;
      });
    } catch (e) {
      // A quiet refresh must not replace good data with an error banner.
      if (mounted && !quiet) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Agents in this session'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: loading && agents.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : error != null && agents.isEmpty
                ? _ErrorState(message: error!, onRetry: refresh)
                : SessionAgentsList(agents: agents),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        children: [
          Text('Could not load agents',
              textAlign: TextAlign.center,
              style: sans(17, weight: W.title, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3)),
          const SizedBox(height: 18),
          Center(child: Btn('Retry', onTap: onRetry)),
        ],
      );
}

/// Pure presentation: active holders first, then history. No fetching, so it
/// can be tested directly with constructed data.
class SessionAgentsList extends StatelessWidget {
  const SessionAgentsList({super.key, required this.agents});

  final List<CoordinationSessionAgent> agents;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        children: [
          Icon(Icons.groups_outlined, size: 44, color: AppColors.fg4),
          const SizedBox(height: 16),
          Text('No agents have worked here',
              textAlign: TextAlign.center,
              style: sans(16, weight: W.title, color: AppColors.fg1)),
          const SizedBox(height: 8),
          Text(
            'Agents appear here while they hold this session\u2019s turn, and stay '
            'as history once they finish.',
            textAlign: TextAlign.center,
            style: sans(13, color: AppColors.fg3, height: 1.45),
          ),
        ],
      );
    }

    final active = agents.where((a) => a.active).toList(growable: false);
    final past = agents.where((a) => !a.active).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _SectionHeader(
          title: 'Active now',
          count: active.length,
          // A running holder is the thing worth noticing.
          accent: active.isNotEmpty,
        ),
        if (active.isEmpty)
          const _Empty('No agent holds this session\u2019s turn right now.')
        else
          for (final a in active) CoordinationAgentRow(agent: a),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionHeader(title: 'History', count: past.length),
          for (final a in past) CoordinationAgentRow(agent: a),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.accent = false,
  });

  final String title;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: sans(11,
                    weight: W.title,
                    color: accent ? AppColors.accent : AppColors.fg4,
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(message,
            style: sans(12.5, color: AppColors.fg4, height: 1.4)),
      );
}

/// One agent's participation: who, what state, and how long.
class CoordinationAgentRow extends StatelessWidget {
  const CoordinationAgentRow({super.key, required this.agent});

  final CoordinationSessionAgent agent;

  @override
  Widget build(BuildContext context) {
    final name = agent.displayName.trim().isEmpty
        ? agent.agentId
        : agent.displayName;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor:
                agent.active ? AppColors.accentBg : AppColors.surface2,
            foregroundColor:
                agent.active ? AppColors.accent : AppColors.fg3,
            child: Text(initial,
                style: sans(12,
                    weight: W.title,
                    color: agent.active
                        ? AppColors.accent
                        : AppColors.fg3)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, weight: W.label, color: AppColors.fg1)),
                  ),
                  _StateChip(active: agent.active, label: agent.outcome),
                ]),
                const SizedBox(height: 2),
                Text(_subtitle(agent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `@handle · role · 2m` while active, `@handle · role · finished 3m ago`
  /// once the hold has ended.
  static String _subtitle(CoordinationSessionAgent a) {
    final parts = <String>[
      if (a.handle.trim().isNotEmpty) '@${a.handle}',
      if (a.role.trim().isNotEmpty) a.role,
      if (a.active)
        'holding ${_age(a.acquiredAt)}'
      else
        '${a.outcome}  ·  ${_age(a.releasedAt ?? a.acquiredAt)} ago',
    ];
    return parts.join('  ·  ');
  }
}

/// State is carried by colour AND a word, so it never depends on colour alone.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: active ? AppColors.okBg : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(
          active ? 'active' : label,
          style: sans(11,
              weight: W.label,
              color: active ? AppColors.ok : AppColors.fg4),
        ),
      );
}

/// RFC3339 -> a compact age (`2m`, `1h`, `3d`). Returns the raw string if it
/// can't be parsed, so a bad timestamp is visible rather than blank.
String _age(String value) {
  final then = DateTime.tryParse(value);
  if (then == null) return value.isEmpty ? 'just now' : value;
  final d = DateTime.now().difference(then.toLocal());
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
