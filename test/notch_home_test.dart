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
    expect(m['title'], 'Team status');
    expect(m['subtitle'], startsWith('1 needs you'));
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
    expect(m['title'], 'Team status');
    expect(m['subtitle'], '0 working \u00b7 1 standing by');
  });

  test('recent notifications appear last and open their payload', () {
    final targets = <String, NotchTarget>{};
    final now = DateTime(2026, 1, 1, 12);
    final m = buildModel(
        sessions: const [],
        agents: const [],
        jobs: const [],
        tasks: const [],
        now: now,
        targets: targets,
        recent: [
          NotchNote(
              title: 'Rust PR',
              subtitle: 'Approve?',
              kind: 'waiting',
              payload: {'session': 's1'},
              at: now.millisecondsSinceEpoch ~/ 1000 - 300),
        ]);
    final item = (m['items'] as List).single as Map;
    expect(item['section'], 'Recent');
    expect(item['meta'], '5m');
    expect(targets['note:0']!.payload, {'session': 's1'});
  });
}
