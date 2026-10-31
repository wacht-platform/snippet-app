import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/theme.dart';

import 'golden.dart';

const _transcript = [
  'Understood. I will stay quiet during your meeting and will not speak in between. Reach me when you are out.',
  'Okay, acknowledged. I will stay quiet through your meeting.',
  'Let me check the recurring jobs to find the X-related one.',
  'Found it: the "Fresh X Reply Surfacing" job. Cancelling it now.',
  'Cancelled. The recurring job is stopped, so there are no more hourly reply runs. The other recurring job is untouched; let me know if you want that one changed too.',
];

Widget _circle(IconData icon) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: AppColors.surface1,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line)),
      child: Icon(icon, size: 18, color: AppColors.fg2),
    );

class _FakeScreen extends StatelessWidget {
  const _FakeScreen({required this.mobile});
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: mobile ? 56 : 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(children: [
              if (mobile) _circle(Icons.menu),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Mission Control',
                      style: sans(mobile ? 17 : 14,
                          weight: W.label, color: AppColors.fg1))),
              mobile
                  ? _circle(Icons.settings_outlined)
                  : Text('Share  Settings',
                      style: sans(12.5, color: AppColors.fg3)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                for (final t in _transcript)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(t,
                        style: sans(mobile ? 17 : 14,
                            height: 1.5, color: AppColors.fg1)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

const _items = <Map<String, dynamic>>[
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
  {
    'title': 'Add Mission Control wakes setting',
    'kind': 'waiting',
    'session': 's-1',
    'body': 'Should the wake word be on by default?',
    'attention': {'type': 'question', 'id': '9:y'},
  },
];

void main() {
  setUpAll(() async {
    final packages =
        (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map)['packages'] as List;
    final root = packages.firstWhere(
        (p) => p['name'] == 'lucide_icons_flutter')['rootUri'] as String;
    final font = File('${Uri.parse(root).toFilePath()}/assets/lucide.ttf');
    if (!font.existsSync()) return;
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
  });
  setUp(() {
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    notificationAppForeground = true;
  });

  for (final (name, platform, size, top) in [
    ('mobile', TargetPlatform.android, const Size(390, 844), 47.0),
    ('desktop', TargetPlatform.linux, const Size(900, 560), 0.0),
  ]) {
    for (final state in ['single', 'collapsed', 'expanded']) {
      testWidgets('placement $state ($name)', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.only(top: top),
                viewPadding: EdgeInsets.only(top: top),
              ),
              child: NotificationPopovers(child: child!),
            ),
            home: _FakeScreen(mobile: name == 'mobile'),
          ));
          for (final p in state == 'single' ? _items.take(1) : _items) {
            foregroundNotifications.add({...p});
          }
          await tester.pumpAndSettle();
          if (state == 'expanded') {
            await tester.tap(find.text('2 more'));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await expectGolden(tester, find.byType(MaterialApp),
              'goldens/notification_placement_${state}_$name.png');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(minutes: 1));
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
}
