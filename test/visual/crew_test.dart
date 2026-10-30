import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/crew_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

SessionInfo _s(String id, String title,
        {String? agent,
        bool run = false,
        String status = 'idle',
        Map<String, dynamic>? ask,
        int at = 0}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': run ? 'running' : status,
      'running': run,
      'last_active': at,
      'agent_id': agent,
      if (ask != null) 'attention': ask,
    });

CoordinationAgent _a(String id, String name, String role, [String? profile]) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': name,
      'role': role,
      if (profile != null) 'profile': profile,
    });

void main() {
  final crew = deriveCrew([
    _a('rust-pr-reviewer', 'Rust PR Reviewer', 'Reviewer', 'sonnet'),
    _a('snippet', 'Snippet', 'Implementer', 'opus'),
    _a('revenue-scout', 'Revenue Scout', 'Researcher', 'haiku'),
    _a('web-researcher', 'Web Research Specialist', 'Researcher', 'sonnet'),
  ], [
    _s('s1', 'PR 412',
        agent: 'rust-pr-reviewer',
        status: 'waiting_for_input',
        ask: {
          'type': 'approval',
          'text': 'Approve the unsafe block in lanes.rs?'
        }),
    _s('s2', 'Desktop UI follow-up', agent: 'snippet', run: true, at: 2),
    _s('s3', 'Notification stack build', agent: 'snippet', run: true, at: 1),
    _s('s4', 'Overnight revenue deep-dive', agent: 'revenue-scout', run: true),
    _s('s5', 'Cisco scan', agent: 'web-researcher'),
  ]);

  for (final (name, platform, width) in [
    ('mobile', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.macOS, 900.0),
  ]) {
    testWidgets('crew roster and board ($name)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (platform != TargetPlatform.android)
                SizedBox(
                  width: 272,
                  child: Container(
                    color: AppColors.surface1,
                    padding: const EdgeInsets.only(top: 12),
                    child: CrewRoster(entries: crew, onOpen: (_) {}),
                  ),
                ),
              Expanded(
                child: CrewBoard(
                  entries: crew,
                  client: DaemonClient('http://x', 't'),
                  onOpen: (_) {},
                ),
              ),
            ]),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectGolden(
            tester, find.byType(Scaffold), 'goldens/crew_$name.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });
  }
}
