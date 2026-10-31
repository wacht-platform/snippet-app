import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/turn_changes_card.dart';

void main() {
  testWidgets('summarises a turn and expands the file list', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    addTearDown(tester.view.reset);
    final opened = <String>[];
    var all = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: TurnChangesCard(
            onOpenFile: opened.add,
            onOpenAll: () => all++,
            event: {
          'kind': 'turn_changes',
          'total_files': 6,
          'add': 140,
          'del': 22,
          'files': [
            for (var i = 0; i < 6; i++)
              {'path': 'lib/screens/file$i.dart', 'add': 30 - i, 'del': i},
          ],
        }),
      ),
    ));
    expect(find.text('6 files changed'), findsOneWidget);
    expect(find.text('+140'), findsOneWidget);
    expect(find.textContaining('file0.dart'), findsNothing);
    await tester.tap(find.text('6 files changed'));
    await tester.pump();
    expect(find.textContaining('file0.dart'), findsOneWidget);
    expect(find.textContaining('file5.dart'), findsOneWidget);
    await tester.tap(find.textContaining('file2.dart'));
    expect(opened, ['lib/screens/file2.dart']);
    await tester.tap(find.text('View all changes'));
    expect(all, 1);
    await tester.pump();
    await expectLater(find.byType(TurnChangesCard),
        matchesGoldenFile('visual/goldens/turn_changes_card.png'));
  });

  testWidgets('renders nothing for an empty turn', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TurnChangesCard(event: const {'kind': 'turn_changes'})));
    expect(find.textContaining('changed'), findsNothing);
  });
}
