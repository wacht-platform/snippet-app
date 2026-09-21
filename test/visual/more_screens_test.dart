import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/editor.dart';
import 'package:snippet/screens/git.dart';
import 'package:snippet/screens/inference_profiles.dart';
import 'package:snippet/screens/mission_control/coordination_agent_directory.dart';
import 'package:snippet/screens/mission_control/mission_control_screen.dart';
import 'package:snippet/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'golden.dart';

/// The remaining screens as they actually render, with real content.
///
/// Same approach as `secondary_screens_test.dart`: drive the REAL screen
/// widgets against a fake client, in both densities, so hierarchy and density
/// problems show up the way a person would hit them. Each screen's data is the
/// JSON shape the daemon returns, so a golden cannot drift into a hand-built
/// approximation of the real thing.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  List<Map<String, dynamic>> agents = [];
  Map<String, dynamic> config = {};
  Map<String, dynamic> file = {};
  Map<String, dynamic> status = {};

  @override
  Future<String> mcOpen({String? profile}) async => 'mission-control';

  // Mission Control's own data calls. `mcTasks`/`mcSessions` take `bool?`, and
  // `fromJson` tolerates an empty map (every field defaults), so an empty
  // overview is a valid overview.
  @override
  Future<MissionControlOverview> mcOverview() async =>
      MissionControlOverview.fromJson(const {});

  @override
  Future<List<MissionControlTask>> mcTasks({bool? archived}) async =>
      const [];

  @override
  Future<List<ManagedSession>> mcSessions({bool? archived}) async =>
      const [];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      agents.map(CoordinationAgent.fromJson).toList();

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson(config);

  @override
  Future<FileContent> readFile(String path) async =>
      FileContent.fromJson(file);

  @override
  Future<GitStatus> gitStatus(String session) async =>
      GitStatus.fromJson(status);

  @override
  Future<String> gitDiff(String session,
          {String? file, bool staged = false, bool untracked = false}) async =>
      'diff --git a/lib/main.dart b/lib/main.dart\n'
      'index 1a2b3c4..5d6e7f8 100644\n'
      '--- a/lib/main.dart\n'
      '+++ b/lib/main.dart\n'
      '@@ -1,4 +1,5 @@\n'
      ' import "package:flutter/material.dart";\n'
      '-import "package:snippet/old_theme.dart";\n'
      '+import "package:snippet/theme.dart";\n';

  @override
  Future<Map<String, dynamic>> gitStage(String session,
          {List<String>? paths, bool all = false}) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> gitUnstage(String session,
          {List<String>? paths}) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> gitCommit(String session, String message,
          {bool amend = false}) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> gitCheckout(String session, String target,
          {bool create = false}) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> gitPush(String session) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> gitPull(String session) async => {'ok': true};

  /// Both the git screen and Mission Control's state watch a live socket. A
  /// fake has no server, so throwing is the honest stand-in: each caller's own
  /// `try`/`catch` handles it by scheduling a reconnect — the same path a device
  /// with a dead daemon takes — and both cancel that timer on dispose.
  @override
  WebSocketChannel events() => throw UnimplementedError('no live events');

  @override
  WebSocketChannel attach(String sessionId) =>
      throw UnimplementedError('no live socket');

  @override
  Future<List<CoordinationEvent>> agentThread({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<void> markAgentThreadRead({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
  }) async {}
}

Map<String, dynamic> _agent(String id, String name, String kind, String status,
        {List<String> caps = const [], String role = ''}) =>
    {
      'id': id,
      'display_name': name,
      'handle': id,
      'kind': kind,
      'status': status,
      'role': role,
      'capabilities': caps,
    };

Map<String, dynamic> _profile(String name, String provider, String model,
        {bool active = false, bool hasKey = true, int ctx = 200000}) =>
    {
      'name': name,
      'provider': provider,
      'base_url': '',
      'model': model,
      'has_key': hasKey,
      'active': active,
      'context_window': ctx,
      'reasoning_effort': '',
      'stream': false,
      'supports_images': true,
      'x_search': false,
    };

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
    );

void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    // --- Mission Control: the overview with its own tabs.
    testWidgets('mission control ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()..agents = [];

        await tester.pumpWidget(_app(MissionControlScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/mission_control_$density.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Mission Control at a DESKTOP width. `MissionControlScreen` picks its
    // variant by width (>= 720), and the test above renders at 430 — so the
    // wide branch, `DesktopMissionControl`, was never seen.
    testWidgets('mission control, wide ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(1440, 900) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()..agents = [];

        await tester.pumpWidget(_app(MissionControlScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/mission_control_wide_$density.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Agent directory: rows with status, kind and capability chips.
    testWidgets('agent directory ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..agents = [
            _agent('snippet', 'Snippet', 'agent', 'active',
                caps: ['code', 'shell', 'browser'], role: 'primary'),
            _agent('reviewer', 'Reviewer', 'agent', 'idle',
                caps: ['review'], role: 'audit'),
            _agent('researcher', 'Researcher', 'agent', 'paused',
                caps: ['web', 'search'], role: 'research'),
          ];

        await tester.pumpWidget(_app(Scaffold(
            body: CoordinationAgentDirectory(client: client, embedded: true))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/agent_directory_$density.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Inference profiles: the provider cards and the active marker.
    testWidgets('inference profiles ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..config = {
            'profiles': [
              _profile('anthropic-prod', 'anthropic', 'claude-sonnet-4',
                  active: true),
              _profile('openai-fast', 'openai', 'gpt-5', ctx: 400000),
              _profile('local-llama', 'ollama', 'llama-3.3-70b',
                  hasKey: false, ctx: 128000),
            ],
            'active': 'anthropic-prod',
            'delegate': 'openai-fast',
            'manual_approval': false,
            'hostname': 'dev',
          };

        await tester.pumpWidget(_app(InferenceProfilesScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/inference_profiles_$density.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Editor: a real source file with syntax highlighting and line numbers.
    testWidgets('editor ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        const src = '''
import 'package:flutter/material.dart';

/// A small widget so the editor has something realistic to render.
class Greeting extends StatelessWidget {
  final String name;
  const Greeting({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final greeting = 'Hello, \$name';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(greeting, style: const TextStyle(fontSize: 16)),
    );
  }
}
''';

        final client = _FakeDaemon()
          ..file = {
            'path': 'lib/widgets/greeting.dart',
            'content': src,
            'size': src.length,
            'truncated': false,
            'binary': false,
            'hash': 'abc123',
          };

        await tester.pumpWidget(_app(EditorScreen(
          client: client,
          path: 'lib/widgets/greeting.dart',
          name: 'greeting.dart',
        )));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/editor_$density.png');
        // `re_editor` starts a cursor blink while focused, then — on Android
        // only — schedules a bare `Future.delayed(100ms)` inside `startBlink`.
        // `stopBlink` cancels the periodic timer but NOT that delayed future,
        // so it outlives `dispose`. Let it expire before unmounting, otherwise
        // the test fails on a timer the app cannot cancel.
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Git: staged / changed / untracked sections with a diff.
    testWidgets('git ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..status = {
            'ok': true,
            'branch': 'snippet/ui-polish',
            'upstream': 'origin/snippet/ui-polish',
            'ahead': 2,
            'behind': 0,
            'clean': false,
            'files': [
              {
                'path': 'lib/theme.dart',
                'x': 'M',
                'y': ' ',
                'staged': true,
                'unstaged': false,
                'untracked': false,
              },
              {
                'path': 'lib/screens/lanes.dart',
                'x': ' ',
                'y': 'M',
                'staged': false,
                'unstaged': true,
                'untracked': false,
              },
              {
                'path': 'lib/screens/processes.dart',
                'x': ' ',
                'y': 'M',
                'staged': false,
                'unstaged': true,
                'untracked': false,
              },
              {
                'path': 'test/visual/secondary_screens_test.dart',
                'x': '?',
                'y': '?',
                'staged': false,
                'unstaged': false,
                'untracked': true,
              },
            ],
          };

        // An EMBEDDED GitScreen returns a bare Column — no Scaffold. In the app
        // it is always hosted inside one: `presentScreen` frames it in a
        // `Material`, and the desktop shell puts it in a Scaffold. Mounted
        // under a bare MaterialApp instead, every Text falls back to
        // `DefaultTextStyle` and Flutter paints the yellow double-underline
        // that marks "no Material ancestor". Scaffold here, as in the app.
        await tester.pumpWidget(_app(
            Scaffold(body: GitScreen(client: client, sessionId: 's1', embedded: true))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/git_$density.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
