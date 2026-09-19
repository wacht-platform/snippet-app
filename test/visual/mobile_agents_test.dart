import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';
import 'golden.dart';

class _AgentsClient extends DaemonClient {
  _AgentsClient({this.fail = false}) : super('https://daemon.invalid', 'test');
  final bool fail;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async {
    if (fail) throw Exception('Offline');
    return [
      CoordinationAgent.fromJson({
        'id': 'ada', 'display_name': 'Ada', 'role': 'Code reviewer',
        'assigned_sessions': [
          {'id': 'auth', 'title': 'Review authentication flow', 'last_active': 0},
          {'id': 'tests', 'title': 'Add regression coverage', 'last_active': 0},
          {'id': 'inbox-ada', 'title': 'Hidden inbox'},
        ],
      }),
      CoordinationAgent.fromJson({
        'id': 'builder', 'display_name': 'Builder', 'role': 'Implementation',
        'assigned_sessions': [
          {'id': 'mobile', 'title': 'Polish the mobile navigation', 'last_active': 0},
        ],
      }),
      CoordinationAgent.fromJson({
        'id': 'research', 'display_name': 'Research', 'role': 'Research and planning',
        'status': 'disabled',
      }),
    ];
  }
}

void main() {
  for (final width in [390.0, 320.0]) {
    testWidgets('mobile Agents screen at $width', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);
        String? openedAgent;
        String? openedSession;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(body: Sidebar(
            instances: const [], active: null, client: _AgentsClient(),
            selectedSessionId: null, sessions: const [], sessionsLoading: false,
            onRefreshSessions: () {}, onNewSession: () {},
            onSelectInstance: (_) {}, onOpenMissionControl: () {},
            onOpenSession: (id, title, profile) => openedSession = id,
            onAddInstance: () {}, onRenameInstance: (_, name) {},
            onRemoveInstance: (_) {}, onSessionDeleted: (_) {},
            health: const {}, onRefreshHealth: () {}, topInset: false,
            mobileHome: MobileHome.agents, onMobileHome: (_) {},
            settingsSection: null, onSettingsSection: (_) {}, agent: null,
            onAgent: (agent) => openedAgent = agent?.id,
          )),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Code reviewer · Available'), findsOneWidget);
        expect(find.text('Research and planning · Unavailable'), findsOneWidget);
        expect(find.text('Hidden inbox'), findsNothing);
        final group = find.byKey(const ValueKey('agent-sessions-ada'));
        expect(tester.getTopLeft(group).dx, M.gutter);
        expect(tester.getSize(group).width, width - 2 * M.gutter);
        await expectGolden(tester, find.byType(Scaffold).first,
            'goldens/mobile_agents_${width.toInt()}.png');

        await tester.tap(find.byTooltip('New'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CreateAgentForm), findsOneWidget);
        Navigator.of(tester.element(find.byType(CreateAgentForm))).pop();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('Ada'));
        expect(openedAgent, 'ada');
        await tester.tap(find.text('Review authentication flow'));
        expect(openedSession, 'auth');
        final collapse = find.byTooltip('Collapse sessions for Ada');
        expect(tester.getSize(collapse).height, greaterThanOrEqualTo(M.minTarget));
        await tester.tap(collapse);
        await tester.pump();
        expect(find.text('Review authentication flow'), findsNothing);
        await tester.tap(find.byTooltip('Search'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), 'authentication');
        await tester.pump();
        expect(find.text('Review authentication flow'), findsOneWidget);
        expect(find.text('Add regression coverage'), findsNothing);
        expect(find.text('Builder'), findsNothing);
        await tester.enterText(find.byType(TextField), 'no match');
        await tester.pump();
        expect(find.text('Ada'), findsNothing);
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text('Review authentication flow'), findsNothing);
        await tester.tap(find.byTooltip('Expand sessions for Ada'));
        await tester.pump();
        expect(find.text('Review authentication flow'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('mobile create sheet and error state do not add a panel title',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final key = GlobalKey<AgentsSidebarPanelState>();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: AgentsSidebarPanel(key: key, client: _AgentsClient(fail: true))),
      ));
      await tester.pump();
      expect(find.text('Could not load agents'), findsOneWidget);
      expect(find.text('Agents'), findsNothing);
      key.currentState!.openCreateAgent();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CreateAgentForm), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
