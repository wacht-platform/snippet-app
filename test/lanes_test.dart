import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';
import 'package:snippet/shell_panel.dart';

LaneInfo lane({String id = 'one', String title = 'Worker',
    String status = 'running', String report = 'Full report'}) => LaneInfo(
  id: id, title: title, status: status,
  startedAt: DateTime.now().toUtc().toIso8601String(),
  handoff: 'Full handoff', report: report, error: 'Full error',
  activity: 'Current activity', summary: 'Full summary',
  activityLog: [LaneActivity.fromJson({
    'text': 'Historical activity', 'kind': 'tool', 'at': '2026-01-01T00:00:00Z',
  })],
);

void main() {
  for (final mode in ['mobile', 'hosted desktop', 'nested fallback']) {
    testWidgets('$mode detail navigation, live identity and back', (tester) async {
      debugDefaultTargetPlatformOverride = mode == 'mobile'
          ? TargetPlatform.android : TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var lanes = [lane()];
      var closed = false;
      final rootKey = GlobalKey<NavigatorState>();
      final localKey = GlobalKey<NavigatorState>();
      final request = ShellPanelRequest(
        purpose: ShellPanelPurpose.lanes, id: 'lanes', client: null,
        builder: (_, close) => LanesScreen(liveLanes: () => lanes, onClose: close),
      );
      late BuildContext entry;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: rootKey,
        home: Builder(builder: (context) {
          entry = context;
          return const Scaffold(body: Text('Outer home'));
        }),
      ));
      Navigator.of(entry).push(MaterialPageRoute<void>(builder: (_) {
        if (mode == 'hosted desktop') {
          return ShellPanelScope(
            open: (_) async => null,
            child: ShellPanelBody(request: request, onClose: () => closed = true),
          );
        }
        if (mode == 'nested fallback') {
          return Navigator(
            key: localKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) =>
                LanesScreen(liveLanes: () => lanes, onClose: () => closed = true)),
          );
        }
        return LanesScreen(liveLanes: () => lanes);
      }));
      await tester.pumpAndSettle();
      expect(find.text('Delegated lanes'), findsOneWidget);
      expect(find.textContaining(RegExp('^in progress\$', caseSensitive: false)), findsOneWidget);
      expect(find.text('In progress · 1'), findsNothing);
      expect(find.text('Handoff'), findsNothing);
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.byType(LaneDetailScreen), findsOneWidget);
      expect(find.text('Delegated lanes'), findsNothing);
      for (final text in ['Full handoff', 'Full report', 'Full error',
        'Current activity', 'Historical activity']) {
        expect(find.text(text), findsWidgets);
      }
      final nested = mode == 'hosted desktop' ? request.navigatorKey : localKey;
      if (mode != 'mobile') {
        expect(nested.currentState!.canPop(), isTrue);
        expect(closed, isFalse);
      }
      lanes = [lane(id: 'other', title: 'Wrong lane'),
        lane(title: 'Updated worker', status: 'failed', report: 'Updated report')];
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Updated worker'), findsWidgets);
      expect(find.text('Updated report'), findsOneWidget);
      expect(find.text('Wrong lane'), findsNothing);
      expect(find.text('failed'), findsOneWidget);
      lanes = [];
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Lane unavailable'), findsOneWidget);
      lanes = [lane(title: 'Restored worker', status: 'completed')];
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Restored worker'), findsWidgets);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Delegated lanes'), findsOneWidget);
      expect(find.byType(LaneDetailScreen), findsNothing);
      expect(find.textContaining(RegExp('^completed\$', caseSensitive: false)), findsOneWidget);
      expect(find.text('done'), findsOneWidget);
      expect(closed, isFalse);
      if (mode != 'mobile') expect(nested.currentState!.canPop(), isFalse);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      if (mode == 'mobile') {
        expect(find.text('Outer home'), findsOneWidget);
      } else {
        expect(closed, isTrue);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
