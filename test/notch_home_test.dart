import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/notch_home.dart';

void main() {
  test('model puts needs-you first and carries actions', () {
    final targets = <String, NotchTarget>{};
    final m = buildModel(
      sessions: [
        SessionInfo.fromJson({
          'id': 's1',
          'title': 'PR',
          'status': 'waiting_for_input',
          'agent_id': 'r',
          'attention': {'type': 'approval', 'text': 'Run it?'},
        }),
        SessionInfo.fromJson({
          'id': 's2',
          'title': 'Work',
          'status': 'running',
          'running': true,
          'agent_id': 'w'
        }),
      ],
      agents: [
        CoordinationAgent.fromJson({'id': 'r', 'display_name': 'Reviewer'}),
        CoordinationAgent.fromJson({'id': 'w', 'display_name': 'Worker'}),
      ],
      jobs: const [],
      tasks: const [],
      now: DateTime(2026),
      targets: targets,
    );
    expect(m['state'], 'needs');
    expect(m['title'], '1 needs you');
    final items = m['items'] as List;
    expect(items.first['section'], 'Needs you');
    expect((items.first['actions'] as List).first['action'], 'approve');
    expect(targets['crew:r']!.session, 's1');
  });

  test('idle when nothing is happening', () {
    final m = buildModel(
        sessions: const [],
        agents: [
          CoordinationAgent.fromJson({'id': 'a', 'display_name': 'A'})
        ],
        jobs: const [],
        tasks: const [],
        now: DateTime(2026),
        targets: {});
    expect(m['state'], 'idle');
    expect(m['title'], 'All good');
  });
}
