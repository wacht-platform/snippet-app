import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/files.dart';
import 'package:snippet/widgets.dart';

/// The session's file browser is opened from `session.dart` with an
/// `onOpenFile` callback that creates a shell TAB. That is a desktop concept:
/// the phone shell renders `_activeTab`, and a file tab is auxiliary, so
/// `_activeTab` skips it and the mobile shell never draws it.
///
/// Honouring that callback on a phone therefore closed the explorer and pushed a
/// surface the phone does not render — tapping a file appeared to do nothing.
/// These tests pin the split: phones get the viewer route, desktop keeps tabs.
class _FakeFilesClient extends DaemonClient {
  _FakeFilesClient() : super('https://daemon.invalid', 'test-token');

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': path ?? '/root',
        'parent': null,
        'entries': [
          {'name': 'clip.mp4', 'path': '/root/clip.mp4', 'is_dir': false},
          {'name': 'song.mp3', 'path': '/root/song.mp3', 'is_dir': false},
          {'name': 'notes.pdf', 'path': '/root/notes.pdf', 'is_dir': false},
          {'name': 'notes.txt', 'path': '/root/notes.txt', 'is_dir': false},
          {'name': 'lib', 'path': '/root/lib', 'is_dir': true},
        ],
      });

  @override
  Future<FileContent> readFile(String path) async => FileContent.fromJson({
        'path': path,
        'content': 'hello\n',
        'size': 6,
        'binary': false,
        'hash': 'x',
      });
}

void main() {
  /// Run [body] as a PHONE or as desktop. Cleared in a `finally` inside the
  /// body: the framework asserts no foundation debug variable survives the body,
  /// which runs before any tearDown.
  Future<void> asPlatform(TargetPlatform platform,
      Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Pump the explorer and return a sink for the `onOpenFile` callback, so a
  /// test can assert whether the desktop tab path was taken.
  Future<List<String>> pumpExplorer(WidgetTester tester, {double width = 420}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: FileExplorer(
        client: _FakeFilesClient(),
        title: 'Files',
        start: '/root',
        onOpenFile: (path, name) => opened.add(path),
      ),
    ));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('on a phone, tapping a file opens the viewer, not a shell tab',
      (tester) async {
    await asPlatform(TargetPlatform.android, () async {
      final opened = await pumpExplorer(tester);

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      // The regression: the tab callback fired and the viewer never opened.
      expect(opened, isEmpty,
          reason: 'a phone must not route a file into a desktop shell tab');
      expect(find.byType(FileViewer), findsOneWidget,
          reason: 'the file should open in a viewer route');
    });
  });

  testWidgets('on desktop, tapping a file still opens a shell tab',
      (tester) async {
    await asPlatform(TargetPlatform.macOS, () async {
      final opened = await pumpExplorer(tester, width: 1400);

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      expect(opened, ['/root/notes.txt'],
          reason: 'desktop keeps the tab behaviour the mobile fix must not break');
    });
  });

  testWidgets('media and documents get their own row glyphs', (tester) async {
    await asPlatform(TargetPlatform.android, () async {
      await pumpExplorer(tester);

      Iterable<String> iconNamesFor(String fileName) {
        final row = find.ancestor(
          of: find.text(fileName),
          matching: find.byType(Row),
        );
        final icons = find.descendant(of: row, matching: find.byType(AppIcon));
        return tester.widgetList<AppIcon>(icons).map((i) => i.name);
      }

      // Media must not render as the generic fallback. `file-text` used to be
      // returned for unrecognised names and has no case in the icon map, so
      // every such file silently drew the map's fallback circle.
      expect(iconNamesFor('clip.mp4'), contains('film'));
      expect(iconNamesFor('song.mp3'), contains('music'));
      expect(iconNamesFor('notes.pdf'), contains('pdf'));
      expect(iconNamesFor('notes.txt'), contains('file'));
      expect(iconNamesFor('notes.txt'), isNot(contains('file-text')));
      expect(iconNamesFor('lib'), contains('folder'));
    });
  });
}
