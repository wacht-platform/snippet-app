import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/mission_control/widgets/mission_control_header.dart';
import 'package:snippet/widgets.dart';

void main() {
  for (final compact in [true, false]) {
    testWidgets('${compact ? 'Compact' : 'Full'} header has no Tasks shortcut',
        (tester) async {
      final state = MissionControlState(
        client: DaemonClient('https://daemon.invalid', 'test-token'),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: compact
              ? MissionControlHeader.compact(state: state)
              : MissionControlHeader.full(state: state),
        ),
      ));

      expect(find.text('Mission Control'), findsOneWidget);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byTooltip('Tasks'), findsNothing);
      expect(find.text('Tasks'), findsNothing);
      expect(find.byTooltip('Agents'), findsOneWidget);
      expect(find.byTooltip('Inbox'), findsOneWidget);
      expect(find.byType(IconBtn), findsNWidgets(2));
    });
  }
}
