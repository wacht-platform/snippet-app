import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/models.dart';
import 'package:snippet/tool_views.dart';
import 'package:snippet/widgets.dart';

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

  test('Mission Control models mirror the daemon contract', () {
    final task = MissionControlTask.fromJson({
      'id': 'task-1',
      'title': 'Fix lifecycle',
      'description': 'Use the server task contract only.',
      'status': 'in_progress',
      'session_id': 'session-1',
      'created_at': 10,
      'updated_at': 20,
      'archived': false,
      // Intentionally omit old client-only priority, tags, and assignee fields.
    });
    final done = MissionControlTask.fromJson({
      'id': 'task-2',
      'status': 'done',
      'archived': true,
    });
    final session = ManagedSession.fromJson({
      'id': 'session-1',
      'session_id': 'session-1',
      'folder': '/workspace',
      'status': 'active',
      'task_count': 2,
      'archived': false,
    });

    expect(task.isActive, isTrue);
    expect(done.isActive, isFalse);
    expect(session.isActive, isTrue);
    expect(session.taskCount, 2);
  });

  testWidgets('tool preview restores escaped newlines', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => toolDetailView(
              context,
              tool: 'unknown_tool',
              result: {
                'status': 'success',
                'data': {
                  'truncated': true,
                  'preview': r'{"stdout":"first\nsecond"}',
                },
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('first\nsecond'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool panels tolerate malformed result lists', (tester) async {
    final cases = <String, Map<String, dynamic>>{
      'search_content': {
        'results': [
          1,
          'unexpected',
          {'path': 'ok.dart'}
        ]
      },
      'search_files': {
        'results': [
          false,
          {'path': 'ok.dart'}
        ]
      },
      'list_files': {
        'entries': [
          'unexpected',
          {'name': 'ok.dart'}
        ]
      },
      'view_outline': {
        'outline': [
          null,
          {'signature': 'ok()'}
        ]
      },
      'code_map': {
        'files': [
          'unexpected',
          {'path': 'ok.dart', 'symbols': 'not-a-list'},
        ],
      },
      'web_search': {
        'results': [
          42,
          {'title': 'Result', 'url': 'https://example.com'}
        ]
      },
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) => toolDetailView(
                context,
                tool: entry.key,
                result: {'status': 'success', 'data': entry.value},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });

  testWidgets('dynamic transcript bubbles rebuild without selection exceptions',
      (tester) async {
    final messages = ValueNotifier<List<String>>(
      List<String>.generate(24, (i) => 'assistant message $i'),
    );
    addTearDown(messages.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<String>>(
          valueListenable: messages,
          builder: (context, values, _) => ListView.builder(
            itemCount: values.length,
            itemBuilder: (context, index) => Bubble(
              key: ValueKey('message-$index'),
              mine: false,
              text: values[index],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    messages.value = List<String>.generate(7, (i) => 'updated message $i');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    messages.value = List<String>.generate(31, (i) => 'final message $i');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool panels tolerate null optional fields', (tester) async {
    final cases = <String, Map<String, dynamic>>{
      'edit_file': {'note': null},
      'append_file': {'lines_written': null, 'total_lines': null},
      'read_file': {
        'total_lines': null,
        'total_chars': null,
        'truncated': true,
        'hint': null,
      },
      'view_outline': {
        'language': null,
        'symbol_count': null,
        'outline': [
          {'kind': null, 'signature': null, 'depth': null},
        ],
      },
      'code_map': {
        'file_count': null,
        'symbol_count': null,
        'files': [
          {'path': null, 'symbols': null},
        ],
      },
      'web_search': {
        'count': null,
        'results': [
          {
            'title': null,
            'url': null,
            'snippet': null,
            'published_date': null,
          },
        ],
      },
      'web_read': {'published_date': null},
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) => safeToolDetailView(
                context,
                tool: entry.key,
                result: {'status': 'success', 'data': entry.value},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });
}
