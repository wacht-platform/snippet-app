import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/shell_nav.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

/// The agents panel must read like every other sidebar panel.
///
/// It did not: it drew its own 15px title while Terminals, Git Diff and the file
/// tree all render the shared `ShellSectionHeader`, and its row names were
/// hard-coded `W.label` while the canonical `ShellNavRow` is
/// `selected ? W.label : W.body`. So an idle agent was heavier than an idle
/// session in the same rail — which is what "looks like it had bold font"
/// describes. `flutter analyze` cannot see any of it.
class _FakeAgentsClient extends DaemonClient {
  _FakeAgentsClient() : super('https://daemon.invalid', 'test-token');

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Ada',
          'handle': 'ada',
          'role': 'reviewer',
          'status': 'active',
        }),
      ];

}

void main() {
  Future<void> asDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpPanel(WidgetTester tester, {double width = 320}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentsSidebarPanel(client: _FakeAgentsClient()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an idle agent name is not heavier than an idle session row',
      (tester) async {
    await asDesktop(() async {
      await pumpPanel(tester);

      final name = tester.widget<Text>(find.text('Ada'));
      final style = name.style!;
      expect(style.fontWeight, W.body,
          reason: 'the canonical ShellNavRow is '
              '`selected ? W.label : W.body`; an idle row must be 400');
    });
  });

  testWidgets('desktop uses the shared section header, not a bespoke title',
      (tester) async {
    await asDesktop(() async {
      await pumpPanel(tester);

      // Every sibling panel renders this; a panel with its own header is how the
      // rail drifted into two different section styles.
      expect(find.byType(ShellSectionHeader), findsOneWidget);
      // The shared header renders the label uppercased.
      expect(find.text('AGENTS'), findsOneWidget);
    });
  });

  testWidgets('the + action opens the shared create-agent form',
      (tester) async {
    await asDesktop(() async {
      await pumpPanel(tester);

      expect(find.byType(CreateAgentForm), findsNothing);
      await tester.tap(find.byTooltip('Create agent'));
      await tester.pumpAndSettle();

      // The SAME form Mission Control's directory presents, so the two cannot
      // offer different fields.
      expect(find.byType(CreateAgentForm), findsOneWidget);
      expect(find.text('Build agent'), findsOneWidget);
    });
  });

  testWidgets('rows land on the same left inset as every sibling panel',
      (tester) async {
    await asDesktop(() async {
      await pumpPanel(tester);

      // Canonical content x is list inset 8 + kNavPadH 12 = 20. Rows used to sit
      // at 16 (8 + this panel's own 8), which is what read as inset differently
      // from the rest of the rail. The active/idle grouping is gone — a lease is
      // never acquired, so every row is idle — leaving one flat list.
      const expected = kSidebarContentInset + kNavPadH;

      final avatar = tester.getTopLeft(find.byType(AgentStateIcon)).dx;
      expect(avatar, closeTo(expected, 0.5),
          reason: 'row content must share the same x as the header above it');
    });
  });

  testWidgets('the refresh glyph is scaled down to match its neighbours',
      (tester) async {
    await asDesktop(() async {
      await pumpPanel(tester);

      // The glyphs do not share a fill: at size 16 the circular arrow inks about
      // 40% more than a plus, so it read as oversized beside it. Measure the
      // actual ink (`HugeIcon.size`), not the widget's declared size — the
      // correction is deliberately applied to the ink so layout is unaffected.
      double inkOf(String name) {
        final huge = find.descendant(
          of: find.byWidgetPredicate((w) => w is AppIcon && w.name == name),
          matching: find.byType(HugeIcon),
        );
        return tester.widget<HugeIcon>(huge.first).size!;
      }

      final refreshInk = inkOf('refresh');
      final plusInk = inkOf('plus');

      expect(refreshInk, lessThan(plusInk),
          reason: 'the heavier glyph must be scaled down, not the other up');
      // Both keep the same BOX, so the row's layout cannot shift.
      final plusBox = tester.getSize(
          find.byWidgetPredicate((w) => w is AppIcon && w.name == 'plus'));
      final refreshBox = tester.getSize(
          find.byWidgetPredicate((w) => w is AppIcon && w.name == 'refresh'));
      expect(refreshBox, plusBox);
    });
  });

  testWidgets('agents show nested assigned folders without @ tags or roles',
      (tester) async {
    await asDesktop(() async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final assignedClient = _CustomAgentsClient([
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Builder',
          'handle': 'builder',
          'role': 'developer',
          'status': 'active',
          'assigned_sessions': [
            {
              'id': 's1',
              'title': 'feature/auth',
              'conversation': 'feature/auth',
              'last_active': nowSec - 120,
            },
          ],
        }),
      ]);

      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AgentsSidebarPanel(client: assignedClient),
        ),
      ));
      await tester.pumpAndSettle();

      // Shows agent name and nested folder title
      expect(find.text('Builder'), findsOneWidget);
      expect(find.text('feature/auth'), findsOneWidget);

      // Shows relative time for the assignment
      expect(find.text('2m'), findsWidgets);

      // Does NOT show @handle or role
      expect(find.text('@builder'), findsNothing);
      expect(find.text('developer'), findsNothing);
    });
  });

  testWidgets('tapping chevron collapses and expands nested sessions in tree view',
      (tester) async {
    await asDesktop(() async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final assignedClient = _CustomAgentsClient([
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Builder',
          'handle': 'builder',
          'role': 'developer',
          'status': 'active',
          'assigned_sessions': [
            {
              'id': 's1',
              'title': 'feature/auth',
              'conversation': 'feature/auth',
              'last_active': nowSec - 120,
            },
          ],
        }),
      ]);

      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AgentsSidebarPanel(client: assignedClient),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('feature/auth'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      // Tap chevron to collapse
      await tester.tap(find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == 'chevron-down'));
      await tester.pumpAndSettle();

      expect(find.text('feature/auth'), findsNothing);
      expect(find.text('1'), findsOneWidget);

      // Tap chevron to expand again
      await tester.tap(find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == 'chevron-right'));
      await tester.pumpAndSettle();

      expect(find.text('feature/auth'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });
  });

  testWidgets('tapping agent name opens agent conversation even if agent has sessions',
      (tester) async {
    CoordinationAgent? openedAgent;
    final assignedClient = _CustomAgentsClient([
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Builder',
          'handle': 'builder',
          'role': 'developer',
          'status': 'active',
          'assigned_sessions': [
            {
              'id': 's1',
              'title': 'feature/auth',
              'conversation': 'feature/auth',
              'last_active': 1000,
            },
          ],
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AgentsSidebarPanel(
            client: assignedClient,
            onOpenAgent: (a) => openedAgent = a,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Builder'), findsOneWidget);
      await tester.tap(find.text('Builder'));
      await tester.pumpAndSettle();

      expect(openedAgent, isNotNull);
      expect(openedAgent?.id, 'a1');
    });

  testWidgets('agent inbox sessions are not shown under assigned sessions',
      (tester) async {
    final assignedClient = _CustomAgentsClient([
      CoordinationAgent.fromJson({
        'id': 'a1',
        'display_name': 'Builder',
        'handle': 'builder',
        'role': 'developer',
        'status': 'active',
        'assigned_sessions': [
          {
            'id': 'inbox-a1',
            'title': 'Agent Inbox',
            'conversation': 'default',
            'last_active': 2000,
          },
          {
            'id': 's1',
            'title': 'feature/auth',
            'conversation': 'feature/auth',
            'last_active': 1000,
          },
        ],
      }),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentsSidebarPanel(
          client: assignedClient,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Builder'), findsOneWidget);
    expect(find.text('feature/auth'), findsOneWidget);
    expect(find.text('Agent Inbox'), findsNothing);
    expect(find.text('inbox-a1'), findsNothing);
  });
}

class _CustomAgentsClient extends DaemonClient {
  final List<CoordinationAgent> _agents;
  _CustomAgentsClient(this._agents)
      : super('https://daemon.invalid', 'test-token');

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;
}
