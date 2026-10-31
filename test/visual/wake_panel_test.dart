import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/screens/wakes_screen.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';

import '../support/wake_fakes.dart';
import 'golden.dart';

FakeWakeClient _client() => FakeWakeClient(
      wakeState: WakeSchedule.fromJson(wakeJson()),
      warmState: KeepWarmEntry.fromJson(keepWarmJson(
          enabled: true,
          skipped:
              'Session is not open, so there is nothing in memory to warm.',
          provider:
              'This provider does not expose a prompt cache, so it cannot be warmed.')),
      runs: sampleRuns(),
    );

final _agent = CoordinationAgent.fromJson({
  'id': 'scout',
  'display_name': 'Revenue Scout',
  'max_context_tokens': 128000,
});

void main() {
  for (final (name, platform, size) in [
    ('mobile', TargetPlatform.android, const Size(390, 844)),
    ('desktop', TargetPlatform.macOS, const Size(1100, 800)),
  ]) {
    testWidgets('wake settings ($name)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      freezeWakeClock();
      try {
        await tester.binding.setSurfaceSize(size);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: Builder(
              builder: (ctx) => Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 30, top: 20),
                  child: TextButton(
                    onPressed: () => showAgentWakeSettings(ctx,
                        client: _client(),
                        owner: 'scout',
                        name: 'Revenue Scout',
                        agent: _agent,
                        point: const Offset(60, 40)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectGolden(
            tester, find.byType(MaterialApp), 'goldens/wake_panel_$name.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });

    testWidgets('wake editor ($name)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      freezeWakeClock();
      try {
        await tester.binding.setSurfaceSize(size);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: platform == TargetPlatform.android ? 390 : 420,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: AgentWakePanel(
                      client: _client(),
                      owner: 'scout',
                      name: 'Revenue Scout',
                      agent: _agent),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectGolden(
            tester, find.byType(MaterialApp), 'goldens/wake_editor_$name.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });

    testWidgets('wakes overview ($name)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      freezeWakeClock();
      try {
        await tester.binding.setSurfaceSize(size);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: WakesScreen(
                client: _client(),
                embedded: true,
                onBack: platform == TargetPlatform.android ? () {} : null),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectGolden(tester, find.byType(MaterialApp),
            'goldens/wakes_overview_$name.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });
  }
}
