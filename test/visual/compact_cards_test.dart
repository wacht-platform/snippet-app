import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';

import 'golden.dart';

final _running = LaneInfo(
  id: 'l1',
  title: 'Audit server barge-in path',
  status: 'running',
  agent: 'reviewer',
  startedAt: DateTime.now()
      .toUtc()
      .subtract(const Duration(seconds: 141))
      .toIso8601String(),
  activity:
      'Heads-up on "nothing persisted before approval". By existing design, every utterance is already written to ambient_events (text, plus FTS when kept) and its audio to disk before any classification.\nSecond line.',
  activityKind: 'tool_call',
);
final _done = LaneInfo(
  id: 'l2',
  title: 'Client notification audit',
  status: 'completed',
  startedAt: '',
  summary:
      '## Findings\n\nRead-only; **no files changed**. Toast timer is 5s on mobile and 7s on desktop, and the notch routes every event.',
);

Widget _cards() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MissionEnvelopeCard(
            envelope: MissionEnvelope(
          isReport: false,
          taskId: 'eaa98084-1c2d',
          title: 'Tighten Mission Control transcript cards',
          status: '',
          summary:
              'Make the coordination cards and lane cards more compact on mobile and desktop. Keep markdown, clamp long bodies.',
        )),
        const MissionEnvelopeCard(
            envelope: MissionEnvelope(
          isReport: true,
          taskId: 'eaa98084-1c2d',
          title: 'Fix login redirect',
          status: 'done',
          summary: 'Merged the redirect fix; **12 tests** pass.',
        )),
        const MissionEnvelopeCard(
            envelope: MissionEnvelope(
          isReport: false,
          isPlan: true,
          taskId: '41132982-aa',
          title: 'Find X posts to reply to (xAI lane)',
          status: '',
          summary:
              '- ~~Search both lanes, last 48h~~\n- ~~oEmbed-verify candidates~~\n- **Deliver shortlist artifact** · now\n- Report back',
        )),
        const DirectMessageCard(
            message: DirectMessage(
          threadId: 't',
          fromId: 'reviewer',
          fromKind: 'agent',
          body: 'Looks good. One nit on the padding in `_ThreadCard`.',
          isReply: true,
        )),
        const WorkerQuestionCard(
            question: WorkerQuestion(
                taskId: 'x',
                task: 'Release notes draft',
                question: 'Which version should the notes cover?')),
        const AutonomousRoundCard(
            round: AutonomousRound(
          time: 'Thu 29 Oct 15:42',
          firstRound: false,
          quiet: false,
          changed: [],
          open: [],
          due: [
            'Check if ambient-voice-film render finished (ambient-voice-launch-v4.mp4); if so, present final video to boss.'
          ],
          scheduled: [],
        )),
        const AutonomousRoundCard(
            round: AutonomousRound(
          time: 'Thu 29 Oct 16:10',
          firstRound: false,
          quiet: true,
          changed: ['Task **Fix login redirect** moved to done'],
          open: ['Release notes draft'],
          due: [],
          scheduled: [],
        )),
        LaneNotice(title: _running.title, live: () => _running, onOpen: () {}),
        LaneNotice(title: _done.title, live: () => _done, onOpen: () {}),
      ],
    );

void main() {
  for (final (name, platform, width) in [
    ('mobile', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.macOS, 640.0),
  ]) {
    testWidgets('compact cards $name', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: RepaintBoundary(child: _cards())),
            ),
          ),
        ));
        await expectGolden(tester, find.byType(RepaintBoundary).first,
            'goldens/compact_cards_$name.png');
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
