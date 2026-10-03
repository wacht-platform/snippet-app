import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'three stacked notifications clear on hold with haptic, then fresh expiry',
      (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var navigations = 0;
    onNotifTap = (_) => navigations++;
    await mount(tester);
    for (final title in ['First', 'Second', 'Third']) {
      enqueue(title);
    }
    await tester.pump();
    expect(find.textContaining('Hold to clear all'), findsNothing);
    expect(
        find.byKey(const ValueKey('notification-backing-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('notification-backing-2')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp(r'^3 notifications\. Long press to clear all')),
        findsOneWidget);
    semantics.dispose();
    await tester.pump(const Duration(milliseconds: 4800));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('First')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('First'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(find.byType(Dismissible), findsNothing);
    expect(navigations, 0);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
    enqueue('Fresh');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(find.text('Fresh'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Fresh'), findsNothing);
  });

  testWidgets('swipe removes only front and next receives five seconds',
      (tester) async {
    await mount(tester);
    for (final title in ['First', 'Second', 'Third']) {
      enqueue(title);
    }
    await tester.pump();
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.textContaining('Hold to clear all'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Third'), findsOneWidget);
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
