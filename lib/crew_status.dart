import 'models.dart';

enum CrewState { needsYou, working, standingBy }

class CrewEntry {
  const CrewEntry({
    required this.agent,
    required this.state,
    required this.sessions,
    required this.lead,
  });

  final CoordinationAgent agent;
  final CrewState state;

  /// Every session the agent owns or is working in, most recent first.
  final List<SessionInfo> sessions;

  /// The session that decided [state]: the one asking, else the first running
  /// one, else the latest.
  final SessionInfo? lead;

  int get extra => sessions.length > 1 ? sessions.length - 1 : 0;

  Map<String, dynamic>? get attention =>
      state == CrewState.needsYou ? lead?.attention : null;

  bool get isApproval => attention?['type'] == 'approval';

  /// One line for the row: the question, else the running session, else idle.
  String get line => switch (state) {
        CrewState.needsYou => _askText,
        CrewState.working => _title(lead),
        CrewState.standingBy =>
          lead == null ? 'Standing by' : 'Finished ${_title(lead)}',
      };

  String get _askText {
    final t = '${attention?['text'] ?? ''}'.trim();
    return t.isEmpty ? _title(lead) : t;
  }

  static String _title(SessionInfo? s) {
    final t = s?.title.trim() ?? '';
    return t.isEmpty ? 'Untitled session' : t;
  }
}

String? crewOwner(SessionInfo s) {
  final id = s.displayAgentId;
  return id == null || id.isEmpty ? null : id;
}

/// Status comes only from sessions: any waiting -> needs you, else any running
/// -> working, else standing by. Nothing is read from the agent itself.
List<CrewEntry> deriveCrew(
    List<CoordinationAgent> agents, List<SessionInfo> sessions) {
  final by = <String, List<SessionInfo>>{};
  for (final s in sessions) {
    final id = crewOwner(s);
    if (id != null) (by[id] ??= []).add(s);
  }
  final out = <CrewEntry>[];
  for (final a in agents) {
    final ss = (by[a.id] ?? const <SessionInfo>[]).toList()
      ..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    final asking = ss.where((s) => s.needsInput).firstOrNull;
    final running = ss.where((s) => s.running).firstOrNull;
    out.add(CrewEntry(
      agent: a,
      state: asking != null
          ? CrewState.needsYou
          : running != null
              ? CrewState.working
              : CrewState.standingBy,
      sessions: ss,
      lead: asking ?? running ?? ss.firstOrNull,
    ));
  }
  return out;
}

int crewCount(List<CrewEntry> c, CrewState s) =>
    c.where((e) => e.state == s).length;

String crewSummary(List<CrewEntry> c) {
  final n = crewCount(c, CrewState.needsYou);
  final w = crewCount(c, CrewState.working);
  return [
    if (n > 0) '$n waiting on you',
    '$w active task${w == 1 ? '' : 's'}',
  ].join(' · ');
}
