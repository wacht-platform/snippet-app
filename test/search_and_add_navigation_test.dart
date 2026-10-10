import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/mission_control_card.dart';
import 'package:snippet/theme.dart';

class _FakeTestClient extends DaemonClient {
  _FakeTestClient(this._agents)
      : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  final List<CoordinationAgent> _agents;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int limit = 200}) async =>
      [];
}

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Finder _tab(String label) => find.descendant(
    of: find.byType(SidebarMobileBar), matching: find.text(label));

void main() {
  test('agent icon maps to strokeRoundedBot', () {
    expect(hugeIconFor('agent'), HugeIcons.strokeRoundedBot);
    expect(hugeIconFor('bot'), HugeIcons.strokeRoundedBot);
  });

  testWidgets(
      'four tabs, a filter under each header, and a New in the bar that follows the tab',
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
        }),
        CoordinationAgent.fromJson({
          'id': 'a2',
          'display_name': 'Reviewer',
          'handle': 'reviewer',
          'role': 'security review',
          'status': 'active',
        }),
      ]);

      var newSessionCalled = false;
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
                  onOpenMissionControl: () {},
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

      // 1. Chats: the four tabs, Mission Control pinned at the top, and a New
      // that starts a chat.
      await tester.pumpWidget(buildTestWidget(home: MobileHome.chats));
      await tester.pumpAndSettle();

      for (final label in ['Chats', 'Tasks', 'Agents', 'Settings']) {
        expect(_tab(label), findsOneWidget);
      }
      expect(find.byType(MissionControlCard), findsOneWidget);
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      expect(newSessionCalled, isTrue);

      // The filter sits under the header, always visible.
      await tester.enterText(_field('Search chats'), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('No chats match the search.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear').first);
      await tester.pumpAndSettle();
      expect(find.text('Feature Setup'), findsOneWidget);

      // 2. Tasks is a tab of its own, with its own New.
      await tester.tap(_tab('Tasks'));
      await tester.pumpAndSettle();
      expect(currentHome, MobileHome.tasks);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.byTooltip('New task'), findsOneWidget);

      // 3. Agents: one card per agent, and filtering narrows the agents.
      await tester.tap(_tab('Agents'));
      await tester.pumpAndSettle();
      expect(find.text('Snippet'), findsOneWidget);
      expect(find.text('Reviewer'), findsOneWidget);
      expect(find.byTooltip('Mission Control'), findsNothing);

      await tester.enterText(_field('Search agents'), 'security');
      await tester.pumpAndSettle();
      expect(find.text('Reviewer'), findsOneWidget);
      expect(find.text('Snippet'), findsNothing);
      await tester.enterText(_field('Search agents'), 'nonexistentquery');
      await tester.pumpAndSettle();
      expect(find.text('No agents match the search.'), findsOneWidget);
      await tester.enterText(_field('Search agents'), '');
      await tester.pumpAndSettle();

      expect(find.byType(CreateAgentForm), findsNothing);
      await tester.tap(find.byTooltip('New agent'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateAgentForm), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // 4. Settings keeps the tabs, and its New offers what Settings makes.
      await tester.tap(_tab('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byTooltip('Add machine'), findsOneWidget);
      expect(_tab('Chats'), findsOneWidget);
      for (final tip in ['New chat', 'New task', 'New agent']) {
        expect(find.byTooltip(tip), findsNothing);
      }
      await tester.tap(find.byTooltip('Create'));
      await tester.pumpAndSettle();
      for (final item in ['Connect another computer running snippet', 'Inference profile', 'Vault secret', 'Scheduled job']) {
        expect(find.text(item), findsOneWidget);
      }
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.text('WORKSPACE'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'mobile sessions list shows sessions chronologically with trailing folder name and handles empty state and search',
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

      // Recent header is removed; folder name is on trailing session card; no duplicates
      expect(find.text('Recent'), findsNothing);
      expect(find.text('10'), findsNothing);
      expect(find.text('project'), findsWidgets);

      // Top recent items are visible once each:
      expect(find.text('Session Title 0'), findsOneWidget);
      expect(find.text('Session Title 1'), findsOneWidget);
      expect(find.text('Session Title 2'), findsOneWidget);

      // Search reaches past the visible rows to every matching chat.
      await tester.enterText(_field('Search chats'), 'Title 13');
      await tester.pumpAndSettle();
      expect(find.text('Session Title 13'), findsOneWidget);

      // Search for nonexistent chat
      await tester.enterText(_field('Search chats'), 'Session Title 99');
      await tester.pumpAndSettle();
      expect(find.text('No chats match the search.'), findsOneWidget);
      await tester.enterText(_field('Search chats'), '');
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

