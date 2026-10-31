import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/file_icons.dart';
import 'package:snippet/theme.dart';

void main() {
  test('source files get a language badge, others keep an icon', () {
    expect(fileBadgeFor('main.rs')?.$1, 'RS');
    expect(fileBadgeFor('lib/app.tsx')?.$1, 'TSX');
    expect(fileBadgeFor('Cargo.toml'), isNull);
    expect(fileBadgeFor('photo.png'), isNull);
    expect(fileBadgeFor('README.md'), isNull);
  });

  testWidgets('glyph sheet', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(900, 360);
    addTearDown(tester.view.reset);
    const names = [
      'a.rs', 'a.go', 'a.py', 'a.js', 'a.ts', 'a.tsx', 'a.dart', 'a.kt',
      'a.swift', 'a.java', 'a.c', 'a.cpp', 'a.cs', 'a.rb', 'a.php', 'a.sh',
      'a.sql', 'a.html', 'a.css', 'a.vue', 'a.json', 'a.yaml', 'a.toml',
      'a.md', 'a.png', 'a.mp4', 'a.zip', 'a.pdf', 'Dockerfile', 'a.lock',
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 22, runSpacing: 18, children: [
            for (final n in names)
              Column(mainAxisSize: MainAxisSize.min, children: [
                FileGlyph(n, size: 22),
                const SizedBox(height: 4),
                Text(n, style: const TextStyle(fontSize: 9)),
              ]),
          ]),
        ),
      ),
    ));
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('visual/goldens/file_glyphs.png'));
  });
}
