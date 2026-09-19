import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Compare against a golden, writing it on a checkout that has never rendered
/// one.
///
/// Goldens are LOCAL review artifacts and are not committed, so a fresh clone
/// starts with none. The check has to be per CALL, not per directory:
/// `flutter test` runs each test file in its own isolate, so a directory-level
/// check races — the first file writes its few goldens, and every later file
/// then sees PNGs present and switches to comparing against files that were
/// never generated.
///
/// Once a file exists it is compared normally, so a real visual change still
/// fails loudly.
Future<void> expectGolden(
  WidgetTester tester,
  Finder finder,
  String name,
) async {
  // `matchesGoldenFile` resolves a relative path against the test file's own
  // directory; every call site here passes `goldens/<name>`.
  final exists = File('test/visual/$name').existsSync();
  final previous = autoUpdateGoldenFiles;
  if (!exists) autoUpdateGoldenFiles = true;
  try {
    await expectLater(finder, matchesGoldenFile(name));
  } finally {
    autoUpdateGoldenFiles = previous;
  }
}
