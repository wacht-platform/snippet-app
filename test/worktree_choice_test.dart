import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon({required this.repo}) : super('https://daemon.invalid', 't');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  final bool repo;

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': '/code/app',
        'parent': '/code',
        'entries': [
          {'name': 'lib', 'path': '/code/app/lib', 'is_dir': true},
        ],
      });

  @override
  Future<RepoWorktrees> worktrees(String folder) async => RepoWorktrees.fromJson(
        repo
            ? {
                'repo': '/code/app',
                'worktrees': [
                  {'path': '/wt/app/ab12', 'branch': 'snippet/ab12'},
                ],
              }
            : {'repo': null, 'worktrees': []},
      );
}

Future<List<(String, WorkspaceMode)>> _pump(
    WidgetTester tester, _FakeDaemon client) async {
  final opened = <(String, WorkspaceMode)>[];
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(390, 844) * 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: NewSessionPicker(
        client: client,
        machineLabel: 'mac',
        onOpenFolder: (folder, mode) async => opened.add((folder, mode)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  Future<void> start(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('in a repo a new chat defaults to a new worktree',
      (tester) async {
    final opened = await _pump(tester, _FakeDaemon(repo: true));
    expect(find.text('Works in'), findsOneWidget);
    await start(tester, 'Start chat in a new worktree');
    expect(opened.single, ('/code/app', WorkspaceMode.worktree));
  });

  testWidgets('the folder itself can be chosen', (tester) async {
    final opened = await _pump(tester, _FakeDaemon(repo: true));
    await tester.tap(find.text('This folder'));
    await tester.pumpAndSettle();
    await start(tester, 'Start chat in app');
    expect(opened.single, ('/code/app', WorkspaceMode.folder));
  });

  testWidgets('an existing worktree can be chosen', (tester) async {
    final opened = await _pump(tester, _FakeDaemon(repo: true));
    await tester.tap(find.text('Existing (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('snippet/ab12').last);
    await tester.pumpAndSettle();
    await start(tester, 'Start chat in snippet/ab12');
    expect(opened.single, ('/wt/app/ab12', WorkspaceMode.folder));
  });

  testWidgets('outside a repo there is nothing to choose', (tester) async {
    final opened = await _pump(tester, _FakeDaemon(repo: false));
    expect(find.text('Works in'), findsNothing);
    await start(tester, 'Start chat in app');
    expect(opened.single, ('/code/app', WorkspaceMode.folder));
  });

  test('a worktree session is known by its project folder', () {
    final s = SessionInfo.fromJson({
      'id': 'x',
      'folder': '/wt/app/ab12',
      'origin_folder': '/code/app',
      'branch': 'snippet/ab12',
    });
    expect(s.projectFolder, '/code/app');
    expect(s.inWorktree, isTrue);
    final plain = SessionInfo.fromJson({'id': 'y', 'folder': '/code/app'});
    expect(plain.projectFolder, '/code/app');
    expect(plain.inWorktree, isFalse);
  });
}
