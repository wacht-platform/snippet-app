import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/notifications.dart';

void main() {
  setUp(() {
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    notificationAppForeground = true;
  });
  tearDown(() {
    onNotifTap = null;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: const NotificationPopovers(child: Scaffold()),
    ));
  }

  void enqueue(String title) => foregroundNotifications.add({'title': title});

  testWidgets('stack shows newest on top with a count; Clear all empties it',
      (tester) async {
    await mount(tester);
    for (final title in ['First', 'Second', 'Third']) {
      enqueue(title);
    }
    await tester.pump();
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
    expect(find.text('2 more'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('Third'), findsNothing);
    expect(find.text('2 more'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'expanding lists every row, groups needs-you first, and holds expiry',
      (tester) async {
    await mount(tester);
    enqueue('Quiet');
    foregroundNotifications.add({'title': 'Blocked', 'kind': 'waiting'});
    enqueue('Newest');
    await tester.pump();
    expect(find.text('Blocked'), findsOneWidget);
    await tester.tap(find.text('2 more'));
    await tester.pump();
    for (final t in ['Blocked', 'Quiet', 'Newest']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('NEEDS YOU'), findsOneWidget);
    expect(find.text('UPDATES'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Blocked')).dy,
        lessThan(tester.getTopLeft(find.text('Newest')).dy));
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Quiet'), findsOneWidget);
    await tester.tap(find.text('Collapse'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Newest'), findsNothing);
    expect(find.text('Quiet'), findsNothing);
    expect(find.text('Blocked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-press on the front or ghost card expands the stack',
      (tester) async {
    Map<String, dynamic>? opened;
    onNotifTap = (p) => opened = p;
    await mount(tester);
    for (final title in ['First', 'Second', 'Third']) {
      enqueue(title);
    }
    await tester.pump();
    await tester.longPress(find.text('Third'));
    await tester.pump();
    expect(find.text('Collapse'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(opened, isNull);
    await tester.tap(find.text('Collapse'));
    await tester.pump();
    final front = tester.getRect(find.byType(Dismissible));
    await tester.longPressAt(Offset(front.center.dx, front.bottom + 4));
    await tester.pump();
    expect(find.text('Collapse'), findsOneWidget);
    await tester.tap(find.text('Collapse'));
    await tester.pump();
    await tester.tap(find.text('Third'));
    await tester.pump();
    expect(opened?['title'], 'Third');
    expect(find.text('Collapse'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swipe removes only the top card', (tester) async {
    await mount(tester);
    for (final title in ['First', 'Second', 'Third']) {
      enqueue(title);
    }
    await tester.pump();
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('1 more'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('narrow scaled stack fits on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(240, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, scale: 2.5);
      for (var i = 0; i < 3; i++) {
        enqueue('A very long notification title $i');
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(Dismissible));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(240));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
