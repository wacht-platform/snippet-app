import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'golden.dart';

/// The new-chat picker inside a git repository, for review.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 't');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': '/Users/you/code/snippet-app',
        'parent': '/Users/you/code',
        'entries': [
          for (final name in ['android', 'assets', 'lib', 'macos', 'test'])
            {'name': name, 'path': '/Users/you/code/snippet-app/$name', 'is_dir': true},
        ],
      });

  @override
  Future<RepoWorktrees> worktrees(String folder) async => RepoWorktrees.fromJson({
        'repo': '/Users/you/code/snippet-app',
        'worktrees': [
          {'path': '/Users/you/.snippet/worktrees/snippet-app/ab12cd34', 'branch': 'snippet/ab12cd34'},
          {'path': '/Users/you/code/snippet-app-release', 'branch': 'release'},
        ],
      });
}

void main() {
  testWidgets('new chat picker in a repository', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 700) * 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          body: NewSessionPicker(
            client: _FakeDaemon(),
            machineLabel: 'mac',
            onOpenFolder: (_, __) async {},
            onClose: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectGolden(tester, find.byType(MaterialApp), 'goldens/worktree_picker.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
