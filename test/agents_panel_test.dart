import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/shell_nav.dart';
import 'package:snippet/theme.dart';

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

  @override
  Future<List<CoordinationLease>> coordinationActiveLeases() async => const [];
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

  testWidgets('the + action opens the shared create-agent form', (tester) async {
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
}
