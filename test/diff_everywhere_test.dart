import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_welcome.dart';
import 'package:snippet/theme.dart';

SessionInfo _s(String id, String title, Map<String, dynamic> changes) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': 'idle',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 600,
      'folder': '/home/dev/code/app',
      'changes': changes,
    });

void main() {
  testWidgets('recent sessions show line diff, none when unchanged',
      (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(600, 400);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ShellRecentPlaceholder(
          sessions: [
            _s('a', 'Fix login', {'files': 3, 'added': 42, 'removed': 7}),
            _s('b', 'Notes', {'files': 0, 'added': 0, 'removed': 0}),
          ],
          sessionsLoading: false,
          onOpenSession: (_, __, ___) {},
        ),
      ),
    ));
    expect(find.text('+42'), findsOneWidget);
    expect(find.text('-7'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('visual/goldens/diff_recent.png'));
  });
}
