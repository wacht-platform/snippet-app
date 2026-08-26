import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/session.dart';
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

  test('Mission Control is the dedicated home session', () {
    expect(isDedicatedMcSession(null), isFalse);
    expect(isDedicatedMcSession(''), isFalse);
    expect(
      isDedicatedMcSession('snippet-service-61c2d836aee8dc5b/state.json'),
      isFalse,
    );
    expect(
      isDedicatedMcSession(
        'gmata-backend-74fcefb69dbc56ca/conversations/deadbeef.json',
      ),
      isFalse,
    );
    expect(isDedicatedMcSession('mission-control'), isTrue);
    expect(isDedicatedMcSession('mission-control/session.json'), isTrue);
    expect(
      isMissionControlTab(
        sessionId: 'gmata-backend-74fcefb69dbc56ca/conversations/ef933a40.json',
        title: 'Mission Control',
      ),
      isTrue,
    );
    expect(
      isMissionControlTab(
        sessionId: 'snippet-service-61c2d836aee8dc5b/state.json',
        title: 'Design Mission Control',
      ),
      isFalse,
    );
    expect(
      isMissionControlListRow(SessionInfo.fromJson({
        'id': 'mission-control',
        'title': 'Mission Control',
      })),
      isTrue,
    );
    expect(
      isMissionControlListRow(SessionInfo.fromJson({
        'id': 'gmata-backend-74fcefb69dbc56ca/conversations/ef933a40.json',
        'title': 'Mission Control',
      })),
      isTrue,
    );
    expect(
      isMissionControlListRow(SessionInfo.fromJson({
        'id': 'snippet-service-61c2d836aee8dc5b/state.json',
        'title': 'Design Mission Control',
      })),
      isFalse,
    );
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

  test('Mission Control hydrates chat rows from harness events', () {
    final items = feedItemsFromEvents([
      {'kind': 'user_input', 'text': 'hi yo mission control'},
      {'kind': 'assistant_text', 'text': 'Hi! How can I help you today?'},
      {'kind': 'steer', 'text': 'keep going'},
      {
        'kind': 'user_question',
        'questions': [
          {'prompt': 'Which repo?'},
        ],
      },
      {'kind': 'model_error', 'message': 'rate limited'},
      {'kind': 'tool_call', 'name': 'bash'},
    ]);
    expect(items, hasLength(5));
    expect(items[0], isA<UserMessageItem>());
    expect((items[0] as UserMessageItem).text, 'hi yo mission control');
    expect(items[1], isA<AgentTextItem>());
    expect((items[1] as AgentTextItem).text, 'Hi! How can I help you today?');
    expect(items[2], isA<UserMessageItem>());
    expect(items[3], isA<QuestionItem>());
    expect((items[3] as QuestionItem).question, 'Which repo?');
    expect(items[4], isA<SystemNoteItem>());
    expect(
      decodeAttachPayload(utf8.encode('{"wire":"snapshot"}')),
      '{"wire":"snapshot"}',
    );
  });

  test('Mission Control stays connecting until the first snapshot', () {
    final state = MissionControlState(
      client: DaemonClient('http://127.0.0.1:1', 'token'),
    );
    expect(state.loading, isTrue);
    expect(state.feed, isEmpty);

    state.applyHarnessFrameForTest({
      'status': 'idle',
      'workspace': '/workspace',
      'events': [
        {'kind': 'user_input', 'text': 'hi yo mission control'},
        {'kind': 'assistant_text', 'text': 'Hi! How can I help you today?'},
      ],
    });

    expect(state.loading, isFalse);
    expect(state.feed, hasLength(2));
    expect((state.feed.first as UserMessageItem).text, 'hi yo mission control');
    state.dispose();
  });

  test('live Mission Control snapshot hydrates the chat feed', () {
    final snapshot = jsonDecode(
      File('/tmp/mc-snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(snapshot['wire'], 'snapshot');
    expect(snapshot['status'], 'idle');

    final state = MissionControlState(
      client: DaemonClient('http://127.0.0.1:1', 'token'),
    );
    state.applyHarnessFrameForTest(snapshot);

    expect(state.loading, isFalse);
    expect(state.feed, isNotEmpty);
    expect(state.feed.first, isA<UserMessageItem>());
    expect((state.feed.first as UserMessageItem).text, 'hi');
    expect(state.feed.whereType<AgentTextItem>(), isNotEmpty);
    state.dispose();
  });

  test('Mission Control formats task reports instead of raw envelopes', () {
    final items = feedItemsFromEvents([
      {
        'kind': 'user_input',
        'text':
            '[mission_control_task]\ntask_id: t-1\ntitle: Fix hydrate\nscope: keep loading until snapshot\n[/mission_control_task]',
      },
      {
        'kind': 'user_input',
        'text':
            '[mission_task_report]\ntask_id: t-1\ntitle: Fix hydrate\nstatus: done\nsummary: Snapshot gate landed\n[/mission_task_report]',
      },
    ]);
    expect(items, hasLength(2));
    expect(items[0], isA<TaskEventItem>());
    expect((items[0] as TaskEventItem).kind, 'queued');
    expect((items[0] as TaskEventItem).task.title, 'Fix hydrate');
    expect(items[1], isA<TaskEventItem>());
    expect((items[1] as TaskEventItem).kind, 'done');
    expect(
        (items[1] as TaskEventItem).task.description, 'Snapshot gate landed');
  });

  test('repeated subset assistant text is discarded', () {
    const first =
        "I'll inspect the hydrate path, keep loading until the first snapshot, then format worker reports.";
    const later =
        "I'll inspect the hydrate path, keep loading until the first snapshot.";
    expect(assistantTextIsRedundant(later, [first]), isTrue);
    expect(assistantTextIsRedundant('Fresh direction now.', [first]), isFalse);
    expect(
      assistantTextIsRedundant(
        "I'll keep going on the MC chat: hide the terminal, make the list row distinct, add a dispatched-task list.",
        [
          "I'll keep going on the MC chat: distinct list row, hide terminal, dispatched-task list, and tool/handoff rows that only expand when they have something to show.",
        ],
      ),
      isTrue,
    );
  });

  test('tool rows expand only when they have content', () {
    expect(toolIsExpandable('read_file', {'path': 'a.dart'}, null), isFalse);
    expect(
      toolIsExpandable('read_file', {
        'path': 'a.dart'
      }, {
        'status': 'success',
        'data': {'content': 'hello'},
      }),
      isTrue,
    );
    expect(toolIsExpandable('bash', {'command': 'ls'}, null), isFalse);
    expect(
      toolIsExpandable('bash', {
        'command': 'ls'
      }, {
        'status': 'success',
        'data': {'stdout': 'ok'},
      }),
      isTrue,
    );
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
