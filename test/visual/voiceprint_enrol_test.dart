import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/voiceprint_enrol.dart';
import 'golden.dart';

AmbientSettings _ambient(List<bool> current,
    {bool reenrol = false, int adaptive = 0}) {
  final j = <String, dynamic>{
    'voiceprint_reenrol': reenrol,
    'voiceprint_adaptive': adaptive,
    'voiceprints': [
      for (var i = 0; i < current.length; i++)
        {
          'id': 'v$i',
          'label': 'Sample ${i + 1}',
          'current': current[i],
          'created_at': 1757000000,
        },
    ],
  };
  return AmbientSettings.fromJson(j);
}

Widget _view(
  AmbientSettings a, {
  EnrolPhase phase = EnrolPhase.idle,
  String? error,
  bool manage = false,
  EnrolLive? live,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RepaintBoundary(
            child: Container(
              color: AppColors.bg,
              child: VoiceprintGroup(
                ambient: a,
                phase: phase,
                live: ValueNotifier(live ??
                    const EnrolLive(
                        Duration.zero, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
                manageOpen: manage,
                busy: false,
                error: error,
                onRecord: () {},
                onStop: () {},
                onCancel: () {},
                onRecent: () {},
                onToggleManage: () {},
                onRemove: (_) {},
                onClear: () {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final (density, platform, width) in [
    ('mobile', TargetPlatform.android, 390.0),
    ('desktop', TargetPlatform.macOS, 640.0),
  ]) {
    final cases = <String, Widget>{
      'not_set_up': _view(_ambient([])),
      'recording': _view(_ambient([true]),
          phase: EnrolPhase.recording,
          live: const EnrolLive(Duration(milliseconds: 3200),
              [0.1, 0.3, 0.6, 0.8, 0.5, 0.7, 0.9, 0.4, 0.6, 0.3, 0.5, 0.2])),
      'too_quiet': _view(_ambient([true]), error: kEnrolTooQuiet),
      'two_of_three': _view(_ambient([true, true], adaptive: 4)),
      'done': _view(_ambient([true, true, true], adaptive: 12), manage: true),
      'reenrol': _view(_ambient([false, false], reenrol: true), manage: true),
    };
    for (final e in cases.entries) {
      testWidgets('voiceprint ${e.key} ($density)', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          tester.view.devicePixelRatio = 2.0;
          tester.view.physicalSize = Size(width, 620) * 2.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(e.value);
          await tester.pump(const Duration(milliseconds: 100));
          await expectGolden(tester, find.byType(RepaintBoundary).first,
              'goldens/voiceprint_${e.key}_$density.png');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
