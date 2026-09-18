import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/theme.dart';

class _FakeTestClient extends DaemonClient {
  _FakeTestClient(this._agents)
      : super('https://daemon.invalid', 'test-token');

  final List<CoordinationAgent> _agents;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;
}

void main() {
  test('agent icon maps to strokeRoundedBot', () {
    expect(hugeIconFor('agent'), HugeIcons.strokeRoundedBot);
    expect(hugeIconFor('bot'), HugeIcons.strokeRoundedBot);
  });

  testWidgets(
      'top headers have no search/add buttons, and bottom bar handles search and add for chats and agents',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      final client = _FakeTestClient([
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Snippet',
          'handle': 'snippet',
          'role': 'assistant',
          'status': 'active',
          'assigned_sessions': [
            {
              'id': 's1',
              'title': 'defenseclaw investigation',
              'conversation': 'defenseclaw investigation',
              'last_active': 1000,
            },
            {
              'id': 's2',
              'title': 'Unrelated project work',
              'conversation': 'Unrelated project work',
              'last_active': 900,
            },
          ],
        }),
      ]);

      var newSessionCalled = false;
      var mcCalled = false;
      var currentHome = MobileHome.chats;

      Widget buildTestWidget({MobileHome home = MobileHome.chats}) {
        currentHome = home;
        return MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Sidebar(
                  client: client,
                  active: null,
                  instances: const [],
                  health: const {},
                  sessions: [
                    SessionInfo.fromJson({
                      'id': 'mission-control',
                      'title': 'Mission Control',
                      'folder': 'my-project',
                      'last_active': 2000,
                    }),
                    SessionInfo.fromJson({
                      'id': 's1',
                      'title': 'Feature Setup',
                      'folder': 'my-project',
                      'last_active':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
                    }),
                  ],
                  sessionsLoading: false,
                  onRefreshSessions: () async {},
                  selectedSessionId: null,
                  onOpenSession: (_, __, ___) {},
                  onNewSession: () => newSessionCalled = true,
                  onSelectInstance: (_) {},
                  onAddInstance: () {},
                  onRenameInstance: (_, __) {},
                  onRemoveInstance: (_) {},
                  onSessionDeleted: (_) {},
                  onRefreshHealth: () {},
                  topInset: false,
                  onOpenMissionControl: () => mcCalled = true,
                  mobileHome: currentHome,
                  onMobileHome: (h) => setState(() => currentHome = h),
                  settingsSection: null,
                  onSettingsSection: (_) {},
                  agent: null,
                  onAgent: (_) {},
                );
              },
            ),
          ),
        );
      }

      // 1. On Chats Screen:
      await tester.pumpWidget(buildTestWidget(home: MobileHome.chats));
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsWidgets);
      // Mission Control button is present in Chats header
      expect(find.byTooltip('Mission Control'), findsOneWidget);
      // Top header has NO search or new chat buttons
      expect(find.byTooltip('Search chats'), findsNothing);
      expect(find.byTooltip('New chat'), findsNothing);

      // Bottom bar has Search and New actions
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('New'), findsOneWidget);

      // Tap bottom bar New action -> calls onNewSession
      await tester.tap(find.byTooltip('New'));
      await tester.pumpAndSettle();
      expect(newSessionCalled, isTrue);

      // Tap bottom bar Search action -> expands search row with 'Search chats'
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search chats'), findsOneWidget);

      // Filter chats
      await tester.enterText(find.byType(TextField), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('No chats match the search.'), findsOneWidget);

      // Close bottom search
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.text('Feature Setup'), findsNWidgets(2));

      // 2. Switch to Agents Screen:
      await tester.tap(find.text('Agents').first);
      await tester.pumpAndSettle();

      expect(find.text('Snippet'), findsOneWidget);
      expect(find.text('defenseclaw investigation'), findsOneWidget);
      expect(find.text('Unrelated project work'), findsOneWidget);

      // Mission Control button is present in Agents header as well
      expect(find.byTooltip('Mission Control'), findsOneWidget);
      await tester.tap(find.byTooltip('Mission Control'));
      await tester.pumpAndSettle();
      expect(mcCalled, isTrue);

      // Top header has NO search or create agent buttons
      expect(find.byTooltip('Search agents'), findsNothing);
      expect(find.byTooltip('Create agent'), findsNothing);

      // 3. Bottom bar search on agents:
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search agents'), findsOneWidget);
      expect(currentHome, MobileHome.agents);

      // Searching for 'defenseclaw' should filter sessions under the agent
      // to only the matching session!
      await tester.enterText(find.byType(TextField), 'defenseclaw');
      await tester.pumpAndSettle();

      expect(find.text('Snippet'), findsOneWidget);
      expect(find.text('defenseclaw investigation'), findsOneWidget);
      // Non-matching session under Snippet should be filtered out:
      expect(find.text('Unrelated project work'), findsNothing);

      // Searching for nonexistent query shows empty search message
      await tester.enterText(find.byType(TextField), 'nonexistentquery');
      await tester.pumpAndSettle();
      expect(find.text('No agents match the search.'), findsOneWidget);
      expect(find.text('defenseclaw investigation'), findsNothing);

      // 4. Close search and tap bottom bar New on agents opens CreateAgentForm:
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      expect(find.byType(CreateAgentForm), findsNothing);
      await tester.tap(find.byTooltip('New'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateAgentForm), findsOneWidget);

      // Close create agent form sheet
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // 5. Switch to Settings destination:
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Top header has Settings title, no Back button, and machine avatar button
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byTooltip('Add machine'), findsOneWidget);

      // Bottom bar is hidden on settings screen
      expect(find.byTooltip('Search'), findsNothing);
      expect(find.byTooltip('New'), findsNothing);

      // Workspace machine picker section is removed from settings screen body
      expect(find.text('WORKSPACE'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'mobile sessions list shows up to 10 recent sessions within 12 hours and handles empty state and search',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final client = _FakeTestClient([]);

      // 15 sessions total:
      // 12 are within the last 12 hours (indices 0..11)
      // 3 are older than 12 hours (indices 12..14)
      final allSessions = List.generate(15, (i) {
        final hoursAgo = i < 12 ? (i * 0.5) : (13.0 + (i - 12));
        return SessionInfo.fromJson({
          'id': 'sess-$i',
          'title': 'Session Title $i',
          'folder': 'project',
          'last_active': (now - (hoursAgo * 3600).round()),
        });
      });

      Widget buildWidget(List<SessionInfo> sessions) {
        return MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Sidebar(
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
        );
      }

      // Render with 15 sessions
      await tester.pumpWidget(buildWidget(allSessions));
      await tester.pumpAndSettle();

      // Recent header and project folder header are present (no count next to Recent):
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('10'), findsNothing);
      expect(find.text('project'), findsOneWidget);

      // Top recent items are visible:
      expect(find.text('Session Title 0'), findsWidgets);
      expect(find.text('Session Title 1'), findsWidgets);
      expect(find.text('Session Title 2'), findsWidgets);

      // Now search for an older session: search searches across all matching chats
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Title 13');
      await tester.pumpAndSettle();
      expect(find.text('Session Title 13'), findsOneWidget);

      // Search for nonexistent chat
      await tester.enterText(find.byType(TextField), 'Session Title 99');
      await tester.pumpAndSettle();
      expect(find.text('No chats match the search.'), findsOneWidget);

      // Close search
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      // When all sessions are older than 12 hours, Recent header is absent but folder shows them
      final oldSessionsOnly = [
        SessionInfo.fromJson({
          'id': 'old-1',
          'title': 'Ancient Chat',
          'folder': 'project',
          'last_active': now - (15 * 3600), // 15 hours ago
        }),
      ];
      await tester.pumpWidget(buildWidget(oldSessionsOnly));
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsNothing);
      expect(find.text('Ancient Chat'), findsOneWidget);

      // Empty sessions
      await tester.pumpWidget(buildWidget([]));
      await tester.pumpAndSettle();
      expect(find.text('No chats yet.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('agent inbox sessions are not shown in chats list',
      (tester) async {
    final client = _FakeTestClient([]);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessions = [
      SessionInfo.fromJson({
        'id': 'inbox-builder',
        'title': 'Agent Mailbox',
        'folder': 'inbox',
        'conversation': 'default',
        'last_active': now - 60,
      }),
      SessionInfo.fromJson({
        'id': 'sess-normal',
        'title': 'Real User Chat',
        'folder': 'project',
        'conversation': 'default',
        'last_active': now - 120,
      }),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Sidebar(
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
    ));
    await tester.pumpAndSettle();

    expect(find.text('Real User Chat'), findsWidgets);
    expect(find.text('Agent Mailbox'), findsNothing);
    expect(find.text('inbox-builder'), findsNothing);
  });
}

