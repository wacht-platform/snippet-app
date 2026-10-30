import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/voice_screen.dart';
import 'package:snippet/theme.dart';

class _Fake extends DaemonClient {
  _Fake(this.ambient) : super('http://x', 't');
  final Map<String, dynamic> ambient;
  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'voice': {'enabled': true, 'max_seconds': 180}
      });
  @override
  Future<AmbientSettings> getAmbientSettings() async =>
      AmbientSettings.fromJson(ambient);
}

const _voices = [
  {'model': 'flux-priya-en', 'accent': 'American', 'gender': 'Female'},
  {'model': 'flux-orion-en', 'accent': 'American', 'gender': 'Male'},
];

Map<String, dynamic> _scn(String name) => switch (name) {
      'both_deepgram' => {
          'stt': 'flux',
          'tts_provider': 'deepgram',
          'deepgram_key_set': true,
          'deepgram_host': 'api.deepgram.com',
          'deepgram_hosts': [
            {'host': 'api.deepgram.com', 'label': 'Global'},
            {'host': 'api.eu.deepgram.com', 'label': 'EU'}
          ],
          'tts_voice': 'flux-priya-en',
          'tts_voices': _voices,
          'wake_phrases': ['snippet'],
        },
      _ => {
          'stt': 'assemblyai',
          'tts_provider': 'rime',
          'assemblyai_key_set': true,
          'rime_key_set': false,
          'rime_voice': 'cove',
          'wake_phrases': ['snippet', 'hey snippet'],
        },
    };

void main() {
  Future<void> pump(WidgetTester t, String scn, bool mobile) async {
    debugDefaultTargetPlatformOverride =
        mobile ? TargetPlatform.android : TargetPlatform.macOS;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(mobile ? 390 : 760, 2000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: mobile
            ? VoiceScreen(client: _Fake(_scn(scn)))
            : SingleChildScrollView(
                child: VoiceScreen(client: _Fake(_scn(scn)), embedded: true)),
      ),
    ));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
  }

  for (final mobile in [true, false]) {
    final label = mobile ? 'phone' : 'desktop';
    testWidgets('Deepgram key and region appear once, together ($label)',
        (t) async {
      await pump(t, 'both_deepgram', mobile);
      expect(find.text('DEEPGRAM'), findsOneWidget);
      expect(find.text('API key'), findsOneWidget);
      expect(find.text('Region'), findsOneWidget);
      expect(find.text('ASSEMBLYAI'), findsNothing);
      expect(find.text('RIME'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('only the selected providers ask for keys ($label)',
        (t) async {
      await pump(t, 'mixed', mobile);
      expect(find.text('DEEPGRAM'), findsNothing);
      expect(find.text('ASSEMBLYAI'), findsOneWidget);
      expect(find.text('RIME'), findsOneWidget);
      expect(find.text('API key'), findsNWidgets(2));
      for (final h in ['VOICE NOTES', 'LISTENING', 'REPLIES', 'CONVERSATION']) {
        expect(find.text(h), findsOneWidget);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
