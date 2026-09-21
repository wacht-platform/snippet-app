import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';
import 'package:snippet/screens/files.dart';
import 'package:snippet/screens/git_diff_sidebar_panel.dart';
import 'package:snippet/screens/mission_control/coordination_agent_detail.dart';
import 'package:snippet/screens/mission_control/task_detail_screen.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/screens/session.dart' show TerminalInfo;
import 'package:snippet/screens/terminals_sidebar_panel.dart';
import 'package:snippet/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'golden.dart';

/// The remaining screens as they actually render, with real content.
///
/// Drives the REAL widgets against a fake client in both densities. Two hosting
/// rules matter, and getting either wrong produces a golden that lies:
///
///  * A screen that returns a bare Column (no Scaffold) needs a `Material`
///    ancestor or every Text falls back to `DefaultTextStyle` and Flutter paints
///    the yellow double-underline that means "no Material ancestor".
///  * A screen that starts a timer or socket must be unmounted before the test
///    ends, so `dispose` runs.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  FsListing listing = FsListing.fromJson({'path': '/w', 'entries': []});
  List<Map<String, dynamic>> agents = [];
  Map<String, dynamic> task = {};
  Map<String, dynamic> git = {};
  List<Map<String, dynamic>> changed = [];

  @override
  Future<FsListing> fs(String? path) async => listing;

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content,
          {String? prevHash}) async =>
      {'hash': 'h'};

  @override
  Future<void> deletePath(String path) async {}

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      agents.map(CoordinationAgent.fromJson).toList();

  @override
  Future<TaskItem> getTask(String id) async => TaskItem.fromJson(task);

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int limit = 200}) async =>
      [TaskItem.fromJson(task)];

  @override
  Future<List<TaskAgent>> taskAgents(String id) async => const [];

  @override
  Future<TaskLinks> taskLinks(String id) async =>
      TaskLinks.fromJson({'links': [], 'blocked_by': []});

  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async =>
      TaskItem.fromJson(task);

  @override
  Future<void> addTaskAgent(String id, String agentId, {String role = ''}) async {}

  @override
  Future<void> linkTasks(String fromId, String toId,
      {TaskLinkKind kind = TaskLinkKind.blocks}) async {}

  @override
  Future<GitStatus> gitStatus(String session) async =>
      GitStatus.fromJson(git);

  /// Task detail and the sidebar panels watch a live socket. A fake has no
  /// server, so throwing is the honest stand-in: each caller's own `try`/`catch`
  /// handles it by scheduling a reconnect — the path a device with a dead daemon
  /// takes too — and `dispose` cancels that timer.
  @override
  WebSocketChannel events() => throw UnimplementedError('no live events');

  @override
  WebSocketChannel attach(String sessionId) =>
      throw UnimplementedError('no live socket');

  /// Task detail mounts a `CoordinationThreadState`, which watches its own
  /// coordination socket. Same reasoning as above.
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

Map<String, dynamic> _entry(String name, String path,
        {bool isDir = false, bool git = false}) =>
    {'name': name, 'path': path, 'is_dir': isDir, 'git': git};

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
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

    // --- FileExplorer: the file browser with folders and git marks.
    testWidgets('files ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..listing = FsListing.fromJson({
            'path': '/home/snippet',
            'parent': '/home',
            'entries': [
              _entry('code', '/home/snippet/code', isDir: true),
              _entry('apk-serve', '/home/snippet/apk-serve', isDir: true),
              _entry('.gitconfig', '/home/snippet/.gitconfig'),
              _entry('notes.md', '/home/snippet/notes.md'),
              _entry('snippet.db', '/home/snippet/snippet.db'),
            ],
          });

        await tester.pumpWidget(_app(Scaffold(
            body: FileExplorer(client: client, start: '/home/snippet'))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/files_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- NewSessionPicker: breadcrumbs plus a folder list.
    testWidgets('new session picker ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..listing = FsListing.fromJson({
            'path': '/home/snippet',
            'parent': '/home',
            'entries': [
              _entry('code', '/home/snippet/code', isDir: true),
              _entry('apk-serve', '/home/snippet/apk-serve', isDir: true),
              _entry('dist', '/home/snippet/dist', isDir: true),
            ],
          });

        await tester.pumpWidget(_app(Scaffold(
            body: NewSessionPicker(
          client: client,
          machineLabel: 'dev',
          onOpenFolder: (_) async {},
        ))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/new_session_picker_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Task detail: title, status, description, the meta grid.
    testWidgets('task detail ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..task = {
            'id': 't1',
            'title': 'Normalise the type scale',
            'description':
                'Rewrite 255 off-ladder literals onto the nine-step ladder, '
                'then re-render every screen golden.',
            'status': 'in_progress',
            'priority': 1,
            'created_by_kind': 'human',
            'created_by_id': 'you',
            'created_at': '2026-09-15T10:00:00Z',
            'updated_at': '2026-09-15T11:30:00Z',
            'thread_id': 'thread-1',
          };

        await tester.pumpWidget(_app(Scaffold(
            body: TaskDetailScreen(client: client, taskId: 't1'))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/task_detail_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Agent detail: identity, capabilities, and the connect prompt.
    testWidgets('agent detail ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final agent = CoordinationAgent.fromJson(_agent(
            'snippet', 'Snippet', ['code', 'shell', 'browser', 'review']));

        await tester.pumpWidget(_app(Scaffold(
            body: CoordinationAgentDetail(
                agent: agent, client: _FakeDaemon(), embedded: true))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/agent_detail_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Agents sidebar panel: the compact agent list.
    testWidgets('agents panel ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..agents = [
            _agent('snippet', 'Snippet', ['code', 'shell']),
            _agent('reviewer', 'Reviewer', ['review']),
            _agent('researcher', 'Researcher', ['web', 'search']),
          ];

        await tester.pumpWidget(_app(Scaffold(body: Center(
          child: SizedBox(
            width: 260,
            height: 700,
            child: AgentsSidebarPanel(client: client))))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/agents_panel_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- File tree sidebar panel: nested rows at two depths.
    testWidgets('file tree panel ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..listing = FsListing.fromJson({
            'path': '/w',
            'parent': '/',
            'entries': [
              _entry('lib', '/w/lib', isDir: true, git: true),
              _entry('test', '/w/test', isDir: true, git: true),
              _entry('pubspec.yaml', '/w/pubspec.yaml', git: true),
              _entry('README.md', '/w/README.md'),
            ],
          });

        await tester.pumpWidget(_app(Scaffold(body: Center(
          child: SizedBox(
            width: 260,
            height: 700,
            child: FileTreeSidebarPanel(
              client: client,
              workspacePath: '/w',
              onOpenFile: (_, __) {},
            ))))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/file_tree_panel_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Git diff sidebar panel: changed files with counts.
    testWidgets('git diff panel ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        final client = _FakeDaemon()
          ..git = {
            'ok': true,
            'branch': 'snippet/ui-polish',
            'upstream': 'origin/snippet/ui-polish',
            'ahead': 3,
            'behind': 1,
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
                'path': 'test/visual/more_screens_test.dart',
                'x': '?',
                'y': '?',
                'staged': false,
                'unstaged': false,
                'untracked': true,
              },
            ],
          };

        await tester.pumpWidget(_app(Scaffold(body: Center(
          child: SizedBox(
            width: 260,
            height: 700,
            child: GitDiffSidebarPanel(
              client: client,
              workspacePath: '/w',
              sessionId: 's1',
            ))))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/git_diff_panel_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Terminals sidebar panel: live, idle and dead terminals.
    testWidgets('terminals panel ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        sized(tester);
        await tester.pumpWidget(_app(Scaffold(body: Center(
          child: SizedBox(
            width: 260,
            height: 700,
            child: TerminalsSidebarPanel(
              workspacePath: '/w',
              terminals: const [
                TerminalInfo(id: 't1', title: 'cargo watch', alive: true, live: true),
                TerminalInfo(id: 't2', title: 'shell', alive: true, live: false),
                TerminalInfo(id: 't3', title: 'flutter build', alive: false, live: true),
              ],
              focus: 0,
              onNewTerminal: () {},
              onOpenTerminal: (_) {},
              onCloseTerminal: (_) {},
            ))))));
        await tester.pump(const Duration(milliseconds: 120));
        await expectGolden(tester, find.byType(MaterialApp), 'goldens/terminals_panel_$density.png');
        await _teardown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
