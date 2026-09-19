import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';

/// File search used to await ONE directory at a time, so a 200-directory
/// workspace cost 200 sequential round trips. That is latency-bound, not
/// CPU-bound, so the fix is to overlap the requests.
///
/// It also restarted the whole crawl on every debounced keystroke (the run id
/// was bumped per query), so a crawl could never finish while the user was
/// still typing. The crawl now runs ONCE to completion and typing filters what
/// has already arrived.
///
/// Both properties are invisible to `flutter analyze` and to a green build, so
/// they are pinned here.
class _CountingFsClient extends DaemonClient {
  _CountingFsClient(this.tree) : super('https://daemon.invalid', 'test-token');

  /// path → entry maps, exactly as the daemon's `/fs` would return them.
  final Map<String, List<Map<String, dynamic>>> tree;

  int calls = 0;
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<FsListing> fs(String? path) async {
    calls++;
    // Counted around the yield, so overlapping callers are visible: the body
    // runs synchronously up to the first await, so `Future.wait` has already
    // entered every task in the batch by the time any of them resumes.
    _inFlight++;
    maxInFlight = math.max(maxInFlight, _inFlight);
    await Future<void>.value();
    _inFlight--;
    final key = (path == null || path.isEmpty) ? '/root' : path;
    return FsListing.fromJson({
      'path': key,
      'parent': null,
      'entries': tree[key] ?? const [],
    });
  }
}

void main() {
  /// Desktop, because the search popover's anchored branch is desktop-only and
  /// `kMobile` derives from the target platform (a mobile one in flutter_test).
  /// Cleared in a `finally` INSIDE the body: the framework asserts no foundation
  /// debug variable survives the body, which runs before any tearDown.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// A root holding [dirs] folders, each holding one `fileN.txt`.
  _CountingFsClient wideTree(int dirs) {
    final entries = <Map<String, dynamic>>[
      {'name': 'root.txt', 'path': '/root/root.txt', 'is_dir': false},
      for (var i = 0; i < dirs; i++)
        {'name': 'd$i', 'path': '/root/d$i', 'is_dir': true},
    ];
    return _CountingFsClient({
      '/root': entries,
      for (var i = 0; i < dirs; i++)
        '/root/d$i': [
          {'name': 'file$i.txt', 'path': '/root/d$i/file$i.txt', 'is_dir': false},
        ],
    });
  }

  Future<void> openSearch(WidgetTester tester, DaemonClient client) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FileTreeSidebarPanel(
            client: client,
            workspacePath: '/root',
            onOpenFile: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the crawl overlaps its directory fetches', (tester) async {
    await onDesktop(() async {
      final client = wideTree(12);
      await openSearch(tester, client);

      await tester.enterText(find.byType(TextField), 'file');
      // Fire the debounce, then let the crawl run out.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // A sequential walk could never exceed 1 here. The root is fetched alone,
      // then its 12 children go out together.
      expect(client.maxInFlight, greaterThan(1),
          reason: 'directory fetches should overlap, not run one at a time');
      expect(find.text('file3.txt'), findsOneWidget);
    });
  });

  testWidgets('the crawl runs once, however much you keep typing',
      (tester) async {
    await onDesktop(() async {
      final client = wideTree(12);
      await openSearch(tester, client);

      await tester.enterText(find.byType(TextField), 'file');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final afterFirst = client.calls;

      // The regression: a per-query run id meant each keystroke restarted the
      // crawl, so results could never arrive while typing continued.
      for (final q in ['file1', 'file12', 'file']) {
        await tester.enterText(find.byType(TextField), q);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
      }

      expect(client.calls, afterFirst,
          reason: 'the workspace is crawled once, then filtered locally');
      expect(find.text('file3.txt'), findsOneWidget);
    });
  });
}
