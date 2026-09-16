import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';
import 'package:snippet/screens/processes.dart';
import 'package:snippet/screens/recurring.dart';
import 'package:snippet/screens/usage.dart';
import 'package:snippet/screens/vault.dart';
import 'package:snippet/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The secondary screens as they actually render, with real content.
///
/// These are review surfaces. They drive the REAL screen widgets against a fake
/// client, so hierarchy and density problems show up the way a person would hit
/// them — several rows stacked, real strings, both densities. A widget shown in
/// isolation hides the bugs that only appear when rows sit together.
///
/// Each screen's data comes from the same JSON shape the daemon returns, so the
/// golden cannot drift into a hand-built approximation of the real thing.
class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  List<String> vault = [];
  List<Map<String, dynamic>> procs = [];
  Map<String, dynamic> usage = {};
  List<Map<String, dynamic>> jobs = [];

  @override
  Future<List<String>> vaultList() async => vault;

  @override
  Future<List<Map<String, dynamic>>> bgList(String session) async => procs;

  @override
  Future<String> bgLog(String session, String id, {int tail = 300}) async =>
      'listening on :8080\nready';

  @override
  Future<UsageSummary> getUsage() async => UsageSummary.fromJson(usage);

  @override
  Future<List<RecurringJob>> recurringJobs() async =>
      jobs.map(RecurringJob.fromJson).toList();

  /// `RecurringScreen` watches a live event stream. A fake has no server, and
  /// the real `events()` would open a socket to an unresolvable host and raise
  /// an unhandled async error. Throwing here is the honest stand-in: the
  /// screen's own `try`/`catch` handles exactly this path by scheduling a
  /// reconnect, which is what a device with a dead daemon does too.
  @override
  WebSocketChannel events() => throw UnimplementedError('no live events');

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      const [];
}

Map<String, dynamic> _job(String id, String title, String schedule,
        {bool enabled = true, String? error, int nextRun = 0}) =>
    {
      'id': id,
      'title': title,
      'session_id': 'mission-control',
      'prompt': 'Sweep the board for tasks nobody has picked up.',
      // The shape the daemon sends: `kind` plus the fields that kind uses.
      // An interval without `every_secs` renders "every 0s".
      'schedule': schedule == 'daily'
          ? {'kind': 'daily', 'hour': 9, 'minute': 0}
          : {'kind': 'interval', 'every_secs': 1800},
      'enabled': enabled,
      'queued': false,
      'next_run_at': nextRun,
      'created_at': 1757000000,
      'updated_at': 1757000000,
      if (error != null) 'last_error': error,
    };

/// An epoch `minutes` from now, for fixtures that render a countdown.
int _inMinutes(int minutes) =>
    DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch ~/
    1000;

LaneInfo _lane(String id, String title, String status,
        {String? summary, String? error, String? activity}) =>
    LaneInfo(
      id: id,
      title: title,
      status: status,
      startedAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 7))
          .toIso8601String(),
      summary: summary,
      error: error,
      activity: activity,
    );

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
    );

void main() {
  for (final (density, platform) in [
    ('mobile', TargetPlatform.android),
    ('desktop', TargetPlatform.macOS),
  ]) {
    // --- Lanes: the clearest hierarchy test, since every row carries a state
    // colour and two of them share a surface.
    testWidgets('lanes ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final lanes = [
          _lane('1', 'Audit the service store', 'running',
              summary: 'Reading every call site.', activity: 'rg fg4 lib/'),
          _lane('2', 'Refactor the task board', 'completed',
              summary: 'Header treatment unified.'),
          _lane('3', 'Migrate legacy sidecars', 'failed',
              error: 'Permission denied writing the sidecar directory.'),
          _lane('4', 'Old duplicate-send report', 'cancelled'),
          _lane('5', 'Normalise the type scale', 'completed',
              summary: '255 literals across 34 files.'),
        ];

        await tester.pumpWidget(_app(LanesScreen(liveLanes: () => lanes)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/lanes_$density.png'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Vault: a list of secrets plus the add affordance.
    testWidgets('vault ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..vault = [
            'GEMINI_API_KEY',
            'HF_TOKEN',
            'VMOS_ACCESS_KEY_ID',
            'XDR_CLIENT_PASSWORD',
          ];

        await tester.pumpWidget(_app(VaultScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/vault_$density.png'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Processes: rows with a live status, a pid, and two action targets.
    testWidgets('processes ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..procs = [
            {
              'id': 'p1',
              'command': 'cargo watch -x "test --lib"',
              'pid': 48120,
              'running': true,
              // The daemon sends `status: null` while running; the bare exit
              // code (or "signal") once it has exited.
            },
            {
              'id': 'p2',
              'command': 'python3 -m http.server 8899 --directory apk-serve',
              'pid': 1319751,
              'running': true,
            },
            {
              'id': 'p3',
              'command': 'flutter build apk --release --split-per-abi',
              'pid': 0,
              'running': false,
              'status': '0',
            },
            {
              'id': 'p4',
              'command': 'cargo test --lib --offline',
              'pid': 0,
              'running': false,
              'status': '101',
            },
            {
              'id': 'p5',
              'command': 'rg --files-with-matches fg4 lib/',
              'pid': 0,
              'running': false,
              'status': 'signal',
            },
          ];

        await tester.pumpWidget(
            _app(ProcessesScreen(client: client, sessionId: 's1')));
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/processes_$density.png'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Recurring: chips (selection), job rows, and a failure state.
    testWidgets('recurring ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..jobs = [
            // Relative, so "next in" stays meaningful as the clock moves; a
            // fixed epoch drifts into the past and renders "due now".
            _job('j1', 'Board sweep', 'interval',
                nextRun: _inMinutes(6)),
            _job('j2', 'Morning brief', 'daily', nextRun: _inMinutes(940)),
            _job('j3', 'Stale report', 'interval',
                enabled: false,
                nextRun: _inMinutes(30),
                error: 'The session it targets no longer exists.'),
          ];

        await tester.pumpWidget(_app(RecurringScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/recurring_$density.png'));
        // `RecurringScreen` watches `client.events()`. The fake throws, which the
        // screen catches and answers by scheduling a 3s reconnect timer. That
        // timer must not outlive the test, so unmount the tree — `dispose`
        // cancels it, which is the same path a device takes when you close the
        // screen.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // --- Usage: the provider cards with their rate windows.
    testWidgets('usage ($density)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(430, 860) * 2.0;
        addTearDown(tester.view.reset);

        final client = _FakeDaemon()
          ..usage = {
            'providers': [
              {
                'provider': 'anthropic',
                'model': 'claude-sonnet-4',
                'sessions': 12,
                'total_tokens': 1842300,
                'prompt_tokens': 1420000,
                'completion_tokens': 422300,
                'cache_read_tokens': 910000,
                'rate_limits_supported': true,
                'rate_limits': [
                  {
                    'used_percent': 38.5,
                    'window_minutes': 300,
                    // `resets_at: 0` means "no reset to name": the bar and the
                    // percentage still render, but the countdown line does not.
                    // A real epoch cannot be used here — `rateResetLabel`
                    // appends the reset's ABSOLUTE local time ("resets in 2h ·
                    // 08:40"), which changes as wall-clock time advances, so the
                    // committed golden could never match on a later run.
                    'resets_at': 0,
                  },
                  {
                    'used_percent': 71.2,
                    'window_minutes': 10080,
                    'resets_at': 0,
                  },
                ],
              },
              {
                'provider': 'openai',
                'model': 'gpt-5',
                'sessions': 4,
                'total_tokens': 210400,
                'prompt_tokens': 180000,
                'completion_tokens': 30400,
                'rate_limits_supported': false,
                'rate_limits': [],
              },
            ],
          };

        await tester.pumpWidget(_app(UsageScreen(client: client)));
        await tester.pump(const Duration(milliseconds: 120));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/usage_$density.png'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
