import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/models.dart';

void main() {
  test('HarnessState preserves title fallback and checkpoints', () {
    final state = HarnessState.fromJson({
      'status': 'idle',
      'workspace': '/workspace',
      'user_request': 'Initial request',
      'checkpoints': [
        {
          'id': 'cp-1',
          'label': 'Start',
          'created_at': '2026-01-01T00:00:00Z',
          'event_index': 1,
          'message_index': 0,
        }
      ],
    });

    final delta = state.applyDelta({
      'status': 'running',
      'workspace': '/workspace',
      'event_count': 1,
      'new_events': [
        {'kind': 'assistant', 'text': 'hello'},
      ],
    });

    expect(state.title, 'Initial request');
    expect(delta.title, 'Initial request');
    expect(delta.checkpoints, hasLength(1));
    expect(delta.checkpoints.single.id, 'cp-1');
    expect(delta.events, hasLength(1));
    expect(delta.status, 'running');
  });

  test('explicit empty title does not fall back during a delta', () {
    final state = HarnessState.fromJson({
      'status': 'idle',
      'workspace': '/workspace',
      'title': 'Old title',
    });

    final delta = state.applyDelta({
      'status': 'idle',
      'workspace': '/workspace',
      'title': '',
    });

    expect(delta.title, isNull);
  });
}
