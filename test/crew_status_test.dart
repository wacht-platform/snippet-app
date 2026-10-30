import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';

SessionInfo s(String id,
        {String? agent,
        String? worker,
        String status = 'idle',
        bool run = false,
        int at = 0,
        Map<String, dynamic>? ask}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': id,
      'status': run ? 'running' : status,
      'running': run,
      'last_active': at,
      'agent_id': agent,
      'worker_agent_id': worker,
      if (ask != null) 'attention': ask,
    });

CoordinationAgent a(String id) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': id});

void main() {
  test('status is derived from sessions only', () {
    final crew = deriveCrew([
      a('r'),
      a('w'),
      a('i'),
      a('x')
    ], [
      s('s1',
          agent: 'r',
          status: 'waiting_for_input',
          ask: {'type': 'approval', 'text': 'Run it?'}),
      s('s2', worker: 'w', run: true),
      s('s3', agent: 'i'),
      s('s4', status: 'waiting_for_input'),
    ]);
    expect(crew.map((e) => e.state), [
      CrewState.needsYou,
      CrewState.working,
      CrewState.standingBy,
      CrewState.standingBy,
    ]);
    expect(crew[0].line, 'Run it?');
    expect(crew[0].isApproval, isTrue);
    expect(crew[3].lead, isNull);
    expect(crewSummary(crew), '1 waiting on you · 1 active task');
  });

  test('worker wins over owner and needs-you outranks working', () {
    final crew = deriveCrew([
      a('r'),
      a('o')
    ], [
      s('s1', agent: 'o', worker: 'r', run: true),
      s('s2', agent: 'r', status: 'waiting_for_input', at: 5),
    ]);
    expect(crew[0].state, CrewState.needsYou);
    expect(crew[0].sessions.map((x) => x.id), ['s2', 's1']);
    expect(crew[0].extra, 1);
    expect(crew[1].state, CrewState.standingBy);
  });
}
