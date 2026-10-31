import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/presented_file_card.dart';
import 'package:snippet/theme.dart';

void main() {
  testWidgets('single and grouped shared files render as cards',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 520);
    addTearDown(tester.view.reset);
    final client = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            PresentedFiles(client: client, files: const [
              (path: '/tmp/report.pdf', caption: 'Quarterly numbers'),
            ]),
            const SizedBox(height: 16),
            PresentedFiles(client: client, files: const [
              (path: '/tmp/a/notes.md', caption: ''),
              (path: '/tmp/a/data.csv', caption: 'Raw export'),
              (path: '/tmp/a/app.apk', caption: ''),
            ]),
          ]),
        ),
      ),
    ));
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('Shared 3 files'), findsOneWidget);
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('visual/goldens/presented_files_card.png'));
  });
}
