import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/call_tracking.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/voice_screen.dart';
import 'package:snippet/theme.dart';

class _Fake extends DaemonClient {
  _Fake(this.policy) : super('http://x', 't');
  final RecordingPolicy? policy;
  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'voice': {'enabled': true, 'max_seconds': 180}
      });
  @override
  Future<AmbientSettings> getAmbientSettings() async =>
      AmbientSettings.fromJson({'stt': 'flux', 'tts_provider': 'deepgram'});
  @override
  Future<RecordingPolicy?> getRecording() async => policy;
}

final _json = {
  'retention_days': 30,
  'snooze_until': null,
  'rules': [
    {
      'id': 'r1',
      'label': 'Monday standup',
      'mode': 'auto',
      'basis': 'always record my Monday standup',
      'when': {
        'keywords': ['standup'],
        'weekdays': [1],
        'from_hhmm': '09:00',
        'to_hhmm': null
      },
      'created_at': 1
    },
    {
      'id': 'r2',
      'label': 'Family calls',
      'mode': 'never',
      'basis': '',
      'when': {'keywords': [], 'weekdays': null},
      'created_at': 2
    }
  ],
  'windows': [
    {
      'id': 'w1',
      'label': 'Lunch off',
      'mode': 'never',
      'basis': '',
      'from_ms': 1000,
      'to_ms': 2000,
      'created_at': 3
    }
  ],
  'recordings': [
    {'id': 'a', 'started': 1700000000000, 'ended': 1700000600000, 'lines': 12, 'path': '/x'}
  ],
};

void main() {
  test('policy parsing', () {
    final p = RecordingPolicy.fromJson(_json);
    expect(p.retentionDays, 30);
    expect(p.snoozeUntil, isNull);
    expect(p.rules[0].weekdays, [1]);
    expect(p.rules[0].keywords, ['standup']);
    expect(p.rules[0].fromHhmm, '09:00');
    expect(p.rules[1].weekdays, isNull);
    expect(p.windows.single.toMs, 2000);
    expect(p.recordings.single.lines, 12);
  });

  test('auto call_state carries the label', () {
    final e = parseCallEvent({
      'type': 'call_state',
      'call_id': 'c1',
      'state': 'tracking',
      'auto': true,
      'label': 'Monday standup'
    })!;
    expect(e.auto, isTrue);
    final t = CallTracker();
    t.apply('u', e);
    expect(t.state.value!.auto, isTrue);
    expect(t.state.value!.label, 'Monday standup');
  });

  Future<void> pump(WidgetTester t, RecordingPolicy? p) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 3000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: VoiceScreen(client: _Fake(p))),
    ));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('Recording section lists rules, windows and recordings',
      (t) async {
    await pump(t, RecordingPolicy.fromJson(_json));
    expect(find.text('RECORDING'), findsOneWidget);
    expect(find.text('Snooze'), findsOneWidget);
    expect(find.text('Keep recordings'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('Monday standup'), findsOneWidget);
    expect(find.textContaining('always record my Monday standup'),
        findsOneWidget);
    expect(find.text('Family calls'), findsOneWidget);
    expect(find.text('Lunch off'), findsOneWidget);
    expect(find.text('12 lines'), findsOneWidget);
    expect(find.text('Remove'), findsNWidgets(3));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('empty rules show the hint', (t) async {
    await pump(
        t,
        RecordingPolicy.fromJson(
            {'retention_days': 0, 'rules': [], 'windows': [], 'recordings': []}));
    expect(find.textContaining('Ask Mission Control, for example'),
        findsOneWidget);
    expect(find.text('Forever'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a 404 hides the section', (t) async {
    await pump(t, null);
    expect(find.text('RECORDING'), findsNothing);
    expect(find.text('RULES'), findsNothing);
    expect(find.text('CONVERSATION'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
