import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:snippet/ambient/hold.dart';
import 'package:snippet/ambient/macos_mic.dart';

const _config = RecordConfig();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var listens = 0;
  var cancels = 0;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    dir = Directory.systemTemp.createTempSync('voice-note');
    listens = 0;
    cancels = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('snippet/macos_aec_mic'),
      MockStreamHandler.inline(onListen: (_, events) {
        listens++;
        sink = events;
      }, onCancel: (_) {
        cancels++;
      }),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a note becomes a playable WAV and holds ambient while recording',
      () async {
    final r = HeldRecorder();
    final path = '${dir.path}/note.wav';
    await r.start(_config, path: path);
    await settle();
    expect(await r.isRecording(), isTrue);
    expect(AmbientHold.local, isTrue);
    final pcm = Uint8List.fromList([0x00, 0x10, 0x00, 0xF0]);
    sink!.success(pcm);
    await settle();
    expect(await r.stop(), path);
    expect(AmbientHold.local, isFalse);
    expect(await r.isRecording(), isFalse);
    final wav = File(path).readAsBytesSync();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.sublist(44), pcm);
    expect(voiceNoteExtension, 'wav');
  });

  test('a note saves even when the temp folder does not exist yet', () async {
    final r = HeldRecorder();
    final path = '${dir.path}/Caches/com.snippet/note.wav';
    await r.start(_config, path: path);
    await settle();
    sink!.success(Uint8List.fromList([0x00, 0x10]));
    await settle();
    expect(await r.stop(), path);
    expect(File(path).existsSync(), isTrue);
  });

  test('silence fails with a reason and writes no file', () async {
    final r = HeldRecorder();
    final path = '${dir.path}/silent.wav';
    await r.start(_config, path: path);
    await settle();
    sink!.success(Uint8List(64));
    await settle();
    await expectLater(r.stop(), throwsA(contains('no audio')));
    expect(File(path).existsSync(), isFalse);
    expect(AmbientHold.local, isFalse);
  });

  test('no audio at all fails instead of reporting an empty file', () async {
    final r = HeldRecorder();
    await r.start(_config, path: '${dir.path}/none.wav');
    await expectLater(r.stop(), throwsA(contains('no audio')));
  });

  test('ending a note leaves ambient listening on the same native stream',
      () async {
    final ambient = <Uint8List>[];
    final sub = MacosMic.stream.listen(ambient.add);
    await settle();
    final r = HeldRecorder();
    await r.start(_config, path: '${dir.path}/note.wav');
    await settle();
    expect(listens, 1);
    final pcm = Uint8List.fromList([0x00, 0x10]);
    sink!.success(pcm);
    await settle();
    await r.stop();
    await settle();
    expect(cancels, 0);
    sink!.success(pcm);
    await settle();
    expect(ambient, hasLength(2));
    await sub.cancel();
    await settle();
    expect(cancels, 1);
  });
}
