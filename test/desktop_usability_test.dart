import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';
import 'package:snippet/screens/git_diff_sidebar_panel.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/shell_shortcuts.dart';
import 'package:snippet/screens/sidebar.dart';

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

  group('Sidebar session list recency ordering', () {
    testWidgets('sessions are ordered strictly by recency across different folders without folder grouping',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemonClient();
        // Create 4 sessions across 3 different folders with different lastActive timestamps:
        // Session A: repo-alpha, lastActive 1000 (oldest)
        // Session B: repo-beta, lastActive 2000
        // Session C: repo-alpha, lastActive 3000
        // Session D: repo-gamma, lastActive 4000 (newest)
        final sessions = [
          SessionInfo.fromJson({
            'id': 'sess-a',
            'title': 'Alpha Session Old',
            'folder': '/workspace/repo-alpha',
            'last_active': 1000,
          }),
          SessionInfo.fromJson({
            'id': 'sess-b',
            'title': 'Beta Session Middle',
            'folder': '/workspace/repo-beta',
            'last_active': 2000,
          }),
          SessionInfo.fromJson({
            'id': 'sess-c',
            'title': 'Alpha Session New',
            'folder': '/workspace/repo-alpha',
            'last_active': 3000,
          }),
          SessionInfo.fromJson({
            'id': 'sess-d',
            'title': 'Gamma Session Newest',
            'folder': '/workspace/repo-gamma',
            'last_active': 4000,
          }),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 900,
              child: Sidebar(
                client: client,
                active: null,
                instances: const [],
                health: const {},
                sessions: sessions,
                sessionsLoading: false,
                onRefreshSessions: () async {},
                selectedSessionId: null,
                onOpenSession: (_, __, ___) {},
                onNewSession: () {},
                onSelectInstance: (_) {},
                onAddInstance: () {},
                onRenameInstance: (_, __) {},
                onRemoveInstance: (_) {},
                onSessionDeleted: (_) {},
                onRefreshHealth: () {},
                onOpenMissionControl: () {},
                topInset: false,
                mobileHome: MobileHome.chats,
                onMobileHome: (_) {},
                settingsSection: null,
                onSettingsSection: (_) {},
                agent: null,
                onAgent: (_) {},
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Check vertical order of sessions on screen:
        // Must be D (4000) -> C (3000) -> B (2000) -> A (1000)
        final posD = tester.getTopLeft(find.text('Gamma Session Newest')).dy;
        final posC = tester.getTopLeft(find.text('Alpha Session New')) .dy;
        final posB = tester.getTopLeft(find.text('Beta Session Middle')).dy;
        final posA = tester.getTopLeft(find.text('Alpha Session Old')) .dy;

        expect(posD, lessThan(posC), reason: 'Gamma (4000) should be above Alpha New (3000)');
        expect(posC, lessThan(posB), reason: 'Alpha New (3000) should be above Beta (2000)');
        expect(posB, lessThan(posA), reason: 'Beta (2000) should be above Alpha Old (1000)');

        // No folder grouping headers
        expect(find.text('repo-alpha'), findsNothing);
        expect(find.text('repo-beta'), findsNothing);
        expect(find.text('repo-gamma'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
