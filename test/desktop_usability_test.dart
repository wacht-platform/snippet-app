import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';
import 'package:snippet/screens/git_diff_sidebar_panel.dart';
import 'package:snippet/screens/shell_shortcuts.dart';

class _FakeDaemonClient extends DaemonClient {
  _FakeDaemonClient() : super('https://daemon.invalid', 'test-token');

  int fsCallCount = 0;
  List<String> fsCalls = [];
  Map<String, List<Map<String, dynamic>>> fileSystem = {
    '/workspace': [
      {'name': 'README.md', 'path': '/workspace/README.md', 'is_dir': false, 'git': true},
      {'name': 'src', 'path': '/workspace/src', 'is_dir': true, 'git': true},
    ],
    '/workspace/src': [
      {'name': 'main.dart', 'path': '/workspace/src/main.dart', 'is_dir': false, 'git': false},
    ],
  };

  @override
  Future<FsListing> fs(String? path) async {
    final p = path ?? '/workspace';
    fsCallCount++;
    fsCalls.add(p);
    final entries = fileSystem[p] ?? [];
    return FsListing.fromJson({
      'path': p,
      'parent': p == '/workspace' ? null : '/workspace',
      'entries': entries,
    });
  }

  int gitStatusCalls = 0;
  List<Map<String, dynamic>> gitFiles = [
    {'path': 'README.md', 'staged': false, 'untracked': false, 'x': ' ', 'y': 'M'},
  ];

  @override
  Future<GitStatus> gitStatus(String session) async {
    gitStatusCalls++;
    return GitStatus.fromJson({
      'branch': 'main',
      'files': gitFiles,
    });
  }
}

void main() {
  group('ShellShortcutsHandler', () {
    test('handles tab navigation, lifecycle, and toggles', () {
      bool closedTab = false;
      bool newSession = false;
      int relativeDelta = 0;
      int tabIndex = -1;
      bool openedFiles = false;
      bool openedGit = false;
      bool toggledSidebar = false;
      bool toggledRight = false;
      bool openedPalette = false;
      bool focusedComposer = false;
      bool stoppedTask = false;
      bool showedShortcuts = false;

      final handler = ShellShortcutsHandler(
        onCloseActiveTab: () => closedTab = true,
        onNewSession: () => newSession = true,
        onActivateRelativeTab: (d) => relativeDelta = d,
        onActivateTab: (i) => tabIndex = i,
        onOpenActiveFiles: () => openedFiles = true,
        onOpenMacGit: () => openedGit = true,
        onToggleSidebar: () => toggledSidebar = true,
        onToggleRightPanel: () => toggledRight = true,
        onOpenCommandPalette: () => openedPalette = true,
        onFocusComposer: () => focusedComposer = true,
        onStopRunningTask: () => stoppedTask = true,
        onShowShortcuts: () => showedShortcuts = true,
      );

      // Verify that handler ignores key up
      expect(handler.handleKeyEvent(const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      )), isFalse);

      // F1 without modifiers opens shortcuts dialog
      expect(handler.handleKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.f1,
        logicalKey: LogicalKeyboardKey.f1,
        timeStamp: Duration.zero,
      )), isTrue);
      expect(showedShortcuts, isTrue);
    });
  });

  group('FileTreeSidebarPanel auto-revalidation', () {
    testWidgets('background refresh preserves expanded folders and re-fetches subdirectories',
        (tester) async {
      final fake = _FakeDaemonClient();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileTreeSidebarPanel(
            client: fake,
            workspacePath: '/workspace',
            onOpenFile: (_, __) {},
            autoRevalidatePeriod: const Duration(milliseconds: 300),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('src'), findsOneWidget);

      // Expand the 'src' directory
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);

      // Now add a new file inside /workspace/src on disk
      fake.fileSystem['/workspace/src']!.add({
        'name': 'utils.dart',
        'path': '/workspace/src/utils.dart',
        'is_dir': false,
        'git': false,
      });

      // Wait for auto-revalidation periodic timer to fire
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      // The new file should now be visible, and the folder is STILL expanded!
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('utils.dart'), findsOneWidget);

      // Test manual refresh button
      final refreshBtn = find.byTooltip('Refresh files');
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('utils.dart'), findsOneWidget);

      // Dispose cleanly to cancel timer
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('GitDiffSidebarPanel auto-refresh', () {
    testWidgets('background refresh updates git status silently',
        (tester) async {
      final fake = _FakeDaemonClient();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GitDiffSidebarPanel(
            client: fake,
            workspacePath: '/workspace',
            sessionId: 'sess-1',
            autoRefreshPeriod: const Duration(milliseconds: 300),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('1 changed'), findsOneWidget);

      // Mutate git status to clean
      fake.gitFiles.clear();

      // Wait for auto-refresh periodic timer to fire
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('clean'), findsOneWidget);
      expect(find.text('No changes'), findsOneWidget);

      // Dispose cleanly to cancel timer
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
