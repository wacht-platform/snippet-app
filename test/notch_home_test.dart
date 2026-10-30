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
    expect(m['subtitle'], '0 active tasks \u00b7 1 standing by');
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

  test('a session nobody owns that is asking still gets a card with actions', () {
    final targets = <String, NotchTarget>{};
    final m = buildModel(
      sessions: [
        SessionInfo.fromJson({
          'id': 's9',
          'title': 'Add wakes',
          'status': 'waiting_for_input',
          'attention': {'type': 'approval', 'id': '1:x', 'text': 'uses vault secret(s) [K]'},
        }),
        SessionInfo.fromJson({
          'id': 's10',
          'title': 'Pick one',
          'status': 'waiting_for_input',
          'attention': {
            'type': 'question',
            'id': '2:x',
            'text': 'Which one?',
            'choices': [
              {'label': 'Alpha', 'value': 'a'},
              {'label': 'Beta', 'value': 'b'},
            ],
          },
        }),
      ],
      agents: const [],
      jobs: const [],
      tasks: const [],
      now: DateTime(2026),
      targets: targets,
    );
    expect(m['state'], 'needs');
    final items = (m['items'] as List).cast<Map>();
    final approval = items.firstWhere((i) => i['id'] == 'ask:s9');
    expect((approval['actions'] as List).map((a) => (a as Map)['action']), ['approve', 'deny']);
    final question = items.firstWhere((i) => i['id'] == 'ask:s10');
    expect((question['actions'] as List).map((a) => (a as Map)['action']), ['choice:a', 'choice:b']);
    expect(targets['ask:s10']!.question, 'Which one?');
  });

  test('a recent approval note only offers actions while that approval is still pending', () {
    final now = DateTime(2026, 1, 1, 12);
    final note = NotchNote(
        title: 'Add wakes',
        subtitle: 'uses vault secret(s)',
        kind: 'waiting',
        payload: {
          'session': 's9',
          'attention': {'type': 'approval', 'id': '1:x'}
        },
        at: now.millisecondsSinceEpoch ~/ 1000);
    Map noteItem(List<SessionInfo> sessions) => (buildModel(
            sessions: sessions,
            agents: const [],
            jobs: const [],
            tasks: const [],
            now: now,
            targets: {},
            recent: [note])['items'] as List)
        .cast<Map>()
        .firstWhere((i) => i['id'] == 'note:0');
    final stale = noteItem(const []);
    expect((stale['actions'] as List).map((a) => (a as Map)['action']), ['open']);
    final live = noteItem([
      SessionInfo.fromJson({
        'id': 's9',
        'title': 'Add wakes',
        'status': 'waiting_for_input',
        'attention': {'type': 'approval', 'id': '1:x'},
      })
    ]);
    expect((live['actions'] as List).map((a) => (a as Map)['action']), ['approve', 'deny']);
  });
}
