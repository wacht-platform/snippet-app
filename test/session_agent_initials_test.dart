import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/models.dart';
import 'package:snippet/screens/desktop_shell.dart';

/// The session rows show which agents are working in each session as inline
/// avatar initials.
///
/// That joins two sources: a LEASE (which says where an agent is working) and
/// the AGENT DIRECTORY (which says what to call it). A wrong key there would
/// silently show nothing, or the wrong letter — and since this is decoration on
/// the session list, no build and no analyzer would catch it.
CoordinationLease _lease(String sessionId, String agentId) =>
    CoordinationLease.fromJson({
      'session_id': sessionId,
      'lease_id': 'l-$agentId',
      'assignment_id': 'a1',
      'agent_id': agentId,
      'fencing_token': 1,
      'acquired_at': '2026-01-01T00:00:00Z',
      'renewed_at': '2026-01-01T00:00:00Z',
      'expires_at': '2026-01-01T00:15:00Z',
    });

CoordinationAgent _agent(String id, String displayName) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': displayName,
      'handle': id,
      'kind': 'worker',
      'status': 'active',
      'role': 'implementer',
    });

void main() {
  test('a lease becomes the initial of the agent\'s display name', () {
    final map = sessionAgentInitialsFrom(
      [_lease('session-a', 'agent-1')],
      [_agent('agent-1', 'Ada')],
    );
    expect(map, {
      'session-a': ['A']
    });
  });

  test('an agent missing from the directory still shows, via its id', () {
    // A lease for an agent the directory does not list YET still means someone
    // is working there, so dropping it would hide live work.
    final map = sessionAgentInitialsFrom(
      [_lease('session-a', 'rust-reviewer')],
      const [],
    );
    expect(map, {
      'session-a': ['R']
    });
  });

  test('several agents in one session all appear, in lease order', () {
    final map = sessionAgentInitialsFrom(
      [
        _lease('session-a', 'agent-1'),
        _lease('session-a', 'agent-2'),
        _lease('session-b', 'agent-3'),
      ],
      [
        _agent('agent-1', 'Ada'),
        _agent('agent-2', 'Grace'),
        _agent('agent-3', 'Linus'),
      ],
    );
    expect(map['session-a'], ['A', 'G']);
    expect(map['session-b'], ['L']);
  });

  test('a blank display name falls back to the id, not to nothing', () {
    final map = sessionAgentInitialsFrom(
      [_lease('session-a', 'agent-1')],
      [_agent('agent-1', '   ')],
    );
    // Whitespace-only is not a name; the id is the only usable label.
    expect(map, {
      'session-a': ['A']
    });
  });

  test('a lease with no session lands in no bucket', () {
    final map = sessionAgentInitialsFrom(
      [_lease('', 'agent-1')],
      [_agent('agent-1', 'Ada')],
    );
    expect(map, isEmpty,
        reason: 'an empty session id would key a row that does not exist');
  });

  test('no leases means no avatars, not an empty shell', () {
    expect(sessionAgentInitialsFrom(const [], [_agent('agent-1', 'Ada')]),
        isEmpty);
  });
}
