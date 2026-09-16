import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/add_instance.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/inference_profile_editor.dart';
import 'package:snippet/screens/session_panels.dart';
import 'package:snippet/screens/shell_rail.dart';
import 'package:snippet/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'golden.dart';

/// The last renderable screens: the section rail, the session side panels, the
/// agent thread, and the three form screens.
///
/// Same approach as the other visual suites — drive the REAL widgets against a
/// fake client, in both densities. Every client method a screen reaches is
/// stubbed, including the sockets: a fake has no server, so throwing is the
/// honest stand-in for "daemon is not there", and each caller's own error path
/// handles it.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> thread = [];
  Map<String, dynamic> config = {};

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      agents.map(CoordinationAgent.fromJson).toList();

  @override
  Future<List<CoordinationEvent>> agentThread({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      thread.map(CoordinationEvent.fromJson).toList();

  @override
  Future<void> markAgentThreadRead({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
  }) async {}

  @override
  Future<void> buildCoordinationAgent(String prompt) async {}

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson(config);

  @override
  Future<List<CatalogModel>> providerModels(
          {String? name, String? provider, String? baseUrl, String? apiKey}) async =>
      const [];

  @override
  Future<String> putProfile({
    String? name,
    required String provider,
    String? baseUrl,
    required String model,
    String? apiKey,
    String? reasoningEffort,
    bool? supportsImages,
    int? contextWindow,
    bool? stream,
    bool? xSearch,
    bool setActive = false,
  }) async =>
      'saved';

  @override
  Future<void> setDelegateProfile(String? name) async {}

  /// Three socket entry points: the shell/session stream, a coordination thread,
  /// and Mission Control's own.
  @override
  WebSocketChannel events() => throw UnimplementedError('no live events');

  @override
  WebSocketChannel attach(String sessionId) =>
      throw UnimplementedError('no live socket');

  @override
  WebSocketChannel attachCoordinationEvents() =>
      throw UnimplementedError('no live socket');
}

Map<String, dynamic> _agent(String id, String name, List<String> caps) => {
      'id': id,
      'display_name': name,
      'handle': id,
      'kind': 'agent',
      'status': 'active',
      'role': 'primary',
      'capabilities': caps,
    };

/// One direct-message event, in the shape `CoordinationEvent.fromJson` reads.
Map<String, dynamic> _msg(String id, String actor, String text, int seq) => {
      'event_id': id,
      'thread_id': 'direct:human:local:agent:snippet',
      'partition_key': 'snippet',
      'sequence': seq,
      'event_type': 'direct_message',
      'actor_kind': actor,
      'actor_id': actor == 'human' ? 'local' : 'snippet',
      'payload_version': 1,
      // `CoordinationEvent.body` reads `payload['body']`. A `text` key renders
      // an empty bubble: the model looks for `body` and finds nothing.
      'payload': {'body': text},
      'idempotency_key': id,
      'created_at': '2026-09-16T09:${seq.toString().padLeft(2, '0')}:00Z',
    };

Map<String, dynamic> _checkpoint(String id, String label, int idx) => {
      'id': id,
      'label': label,
      'created_at': '2026-09-16T09:00:00Z',
      'event_index': idx,
      'message_index': idx,
    };

LaneInfo _lane(String id, String title, String status, {String? summary}) =>
    LaneInfo(
      id: id,
      title: title,
      status: status,
      startedAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 4))
          .toIso8601String(),
      summary: summary,
    );

/// Stub the camera-permission plugin.
///
/// `AddInstanceScreen.initState` requests camera permission whenever `kMobile`,
/// and there is no plugin implementation under `flutter test` —
/// `MissingPluginException(No implementation found for method requestPermissions
/// on channel flutter.baseflow.com/permissions/methods)`. Answering `denied`
/// renders the "Grant camera access" state, which is a real state a person can
/// be in and the one worth reviewing.
void _mockPermissions() {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'requestPermissions':
        // `{permissionIndex: statusIndex}`; 0 is `denied`.
        final args = (call.arguments as List).cast<int>();
        return {for (final p in args) p: 0};
      case 'checkPermissionStatus':
        return 0;
      case 'shouldShowRequestPermissionRationale':
        return false;
      case 'openAppSettings':
        return true;
      default:
        return null;
    }
  });
}

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
    );

/// A sidebar panel needs a `Material` ancestor for its InkWells, and LOOSE width
/// constraints — under a Navigator they are tight, so a bare `SizedBox` would be
/// forced full-screen.
Widget _panel(Widget child, {double width = 260, double height = 700}) =>
    Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    );

/// Unmount and settle, so any timer or socket a screen started is cancelled by
/// its own `dispose` rather than outliving the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    void sized(WidgetTester tester) {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(430, 860) * 2.0;
      addTearDown(tester.view.reset);
    }

    // --- The section rail: the thin band that switches the sidebar's contents.
    testWidgets('shell rail ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        // The rail is a full-width BAND (height 40, width infinity), not a
        // narrow vertical strip: its icons sit centred over the 300px sidebar
        // column and its tools hug the far edge. A 56px box squeezed the Row.
        await tester.pumpWidget(_app(_panel(
          ShellRail(section: ShellSection.sessions, onSelect: (_) {}),
          width: 720,
          height: 40,
        )));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/shell_rail_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Session side panels: checkpoints and lanes, the resume affordances.
    testWidgets('session checkpoints ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(_app(_panel(
          SessionCheckpointsPanel(
            checkpoints: [
              Checkpoint.fromJson(_checkpoint('c1', 'Slate accent', 12)),
              Checkpoint.fromJson(_checkpoint('c2', 'Type scale', 48)),
              Checkpoint.fromJson(_checkpoint('c3', 'Golden harness', 96)),
            ],
            onRewind: (_) {},
            onFork: (_) {},
          ),
        )));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/session_checkpoints_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('session lanes panel ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(_app(_panel(
          SessionLanesPanel(lanes: [
            _lane('1', 'Audit the service store', 'running',
                summary: 'Reading every call site.'),
            _lane('2', 'Refactor the task board', 'completed',
                summary: 'Header treatment unified.'),
            _lane('3', 'Migrate legacy sidecars', 'failed'),
          ]),
        )));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/session_lanes_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- The agent thread: a real conversation with both sides.
    testWidgets('agent thread ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..agents = [_agent('snippet', 'Snippet', ['code', 'shell'])]
          ..thread = [
            _msg('m1', 'human', 'Can you check the TUI still lists sessions?', 1),
            _msg('m2', 'agent', 'Running it now — the cached store cut the '
                'listing from 2.05s to under 100ms.', 2),
            _msg('m3', 'human', 'Good. Does it survive a restart?', 3),
          ];

        await tester.pumpWidget(_app(AgentThreadScreen(
          client: client,
          agentId: 'snippet',
          agentName: 'Snippet',
          subtitle: 'code · shell',
        )));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/agent_thread_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Create-agent form: the brief the builder reads.
    testWidgets('create agent form ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(
            _app(Scaffold(body: CreateAgentForm(client: _FakeDaemon()))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/create_agent_form_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Inference profile editor: provider, model, reasoning.
    testWidgets('inference profile editor ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..config = {
            'profiles': [],
            'active': 'anthropic-prod',
            'delegate': null,
            'manual_approval': false,
            'hostname': 'dev',
          };

        await tester.pumpWidget(_app(Scaffold(
            body: InferenceProfileEditor(
          client: client,
          existing: InferenceProfile.fromJson({
            'name': 'anthropic-prod',
            'provider': 'anthropic',
            'base_url': '',
            'model': 'claude-sonnet-4',
            'has_key': true,
            'active': true,
            'context_window': 200000,
            'reasoning_effort': 'medium',
            'stream': true,
            'supports_images': true,
            'x_search': false,
          }),
        ))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/inference_profile_editor_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Add-machine: the paste-a-connection-string step.
    testWidgets('add machine ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        _mockPermissions();
        sized(tester);
        await tester.pumpWidget(_app(const AddInstanceScreen()));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/add_machine_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
