import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Test bootstrap for the whole suite.
///
/// 1. Never fetch fonts over the network — the default tries, fails, and prints
///    a wall of noise on every test.
/// 2. Load a REAL font for each UI family when the files exist on this machine,
///    so `flutter test` renders readable text instead of the Ahem blocks. The
///    suites pass locally either way; this only improves what you can SEE.
///
/// The family names matter. `google_fonts` registers each weight as its own
/// family with a variant suffix — `Geist_regular`, `Geist_500` — NOT the bare
/// `Geist`. Registering the bare name loads a font that nothing ever asks for,
/// and the text still renders as blocks.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await _loadRealFonts();
  _primeGoldenMode();
  await testMain();
}

/// Goldens are LOCAL review artifacts, not repo content, so a fresh clone has
/// none. Without this every comparison would fail on a checkout that simply has
/// not rendered yet. When the directory holds no PNGs, write them instead of
/// comparing; once they exist, the normal comparison runs and a real visual
/// change still fails loudly.
void _primeGoldenMode() {
  final dir = Directory('test/visual/goldens');
  final hasGoldens = dir.existsSync() &&
      dir.listSync().any((e) => e.path.endsWith('.png'));
  if (!hasGoldens) autoUpdateGoldenFiles = true;
}

/// One real source file per family. A missing file makes that family a no-op,
/// so this stays safe on a machine without them.
const String _geist =
    '/home/snippet/.bun/install/cache/next@16.2.6@@@1/dist/compiled/@vercel/og/Geist-Regular.ttf';
const String _sansFallback =
    '/home/snippet/.pub-cache/hosted/pub.dev/google_fonts-8.2.1/example/google_fonts/Lato-Regular.ttf';
const String _mono =
    '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf';

/// The weights the app actually asks for: body 400, label/title 500, strong 600.
const List<int> _weights = [400, 500, 600];

/// google_fonts names weight 400 `_regular` and every other weight `_<number>`.
String _variantName(String family, int weight) =>
    weight == 400 ? '${family}_regular' : '${family}_$weight';

Future<void> _loadRealFonts() async {
  final sources = <String, String>{
    'Geist': _geist,
    'Inter': _sansFallback,
    'JetBrainsMono': _mono,
  };
  for (final entry in sources.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    for (final weight in _weights) {
      final loader = FontLoader(_variantName(entry.key, weight))
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  }
  // `monoFamily` degrades to the generic name when nothing is registered.
  final monoFile = File(_mono);
  if (monoFile.existsSync()) {
    final bytes = await monoFile.readAsBytes();
    final loader = FontLoader('monospace')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
