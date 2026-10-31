import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/notification_stack.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

const _items = <Map<String, dynamic>>[
  {
    'title': 'Fix login redirect',
    'kind': 'waiting',
    'session': 's-1',
    'body': 'Run `pnpm test:auth`? It hits the **staging** database.',
    'attention': {'type': 'approval', 'id': '4:x'},
  },
  {
    'title': 'Release notes draft',
    'kind': 'waiting',
    'session': 's-2',
    'body': 'Which version should the notes cover?',
    'attention': {'type': 'question', 'id': '9:y'},
  },
  {
    'title': 'Coordination review',
    'kind': 'done',
    'session': 's-3',
    'body': '## Summary\n- Merged the **review** queue fix',
  },
  {
    'title': 'Technoxi LinkedIn',
    'kind': 'idle',
    'session': 's-5',
    'body': 'Finished the engagement pass',
  },
  {
    'title': 'Deploy preview',
    'kind': 'failed',
    'session': 's-6',
    'body': 'Build step exited with code 1',
  },
];

void main() {
  setUpAll(() async {
    final packages =
        (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map)['packages'] as List;
    final root = packages.firstWhere(
        (p) => p['name'] == 'lucide_icons_flutter')['rootUri'] as String;
    final pkg = Uri.parse(root).toFilePath();
    final font = File('$pkg/assets/lucide.ttf');
    if (!font.existsSync()) return;
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
  });

  for (final (name, platform, width) in [
    ('mobile', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.macOS, 444.0),
  ]) {
    for (final (expanded, open) in [
      (false, false),
      (false, true),
      (true, false)
    ]) {
      testWidgets(
          'stack ${expanded ? 'expanded' : open ? 'open' : 'collapsed'} ($name)',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.binding.setSurfaceSize(Size(
              width,
              expanded
                  ? 640
                  : open
                      ? 320
                      : 220));
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              backgroundColor: AppColors.bg,
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: NotificationStack(
                      items: _items,
                      expanded: expanded,
                      onToggle: () {},
                      onClearAll: () {},
                      cardBuilder: (p, embedded, lifted) =>
                          NotificationMessageCard(
                        payload: p,
                        embedded: embedded,
                        lifted: lifted,
                        initiallyExpanded: open && identical(p, _items.first),
                        onOpen: () {},
                        onDismiss: () {},
                        onHold: (_) {},
                        onSent: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectGolden(
              tester,
              find.byType(Scaffold),
              'goldens/notification_stack_${expanded ? 'expanded' : open ? 'open' : 'collapsed'}_$name.png');
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
}
