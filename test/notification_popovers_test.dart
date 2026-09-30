import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:flutter/services.dart';
import 'package:snippet/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/notifications.dart';

void main() {
  testWidgets('desktop popover tap reaches the shell route', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => NotificationPopovers(child: child!),
      home: const DesktopShell(),
    ));
    await tester.pumpAndSettle();
    expect(onNotifTap, isNotNull);
    foregroundNotifications.add({
      'title': 'Desktop alert', 'url': 'missing-machine', 'session': 'chat',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop alert'));
    await tester.pumpAndSettle();
    expect(find.text('That machine is no longer saved.'), findsOneWidget);
    expect(find.text('Desktop alert'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(onNotifTap, isNull);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  test('desktop foreground state controls visible-chat suppression', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    reportForeground(true);
    reportVisibleNotificationSession('u', 's');
    expect(notificationAppForeground, isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 'other'}), isFalse);
    reportForeground(false);
    expect(notificationAppForeground, isFalse);
    expect(visibleNotificationSession.value, isNull);
    reportVisibleNotificationSession('u', 's');
    expect(visibleNotificationSession.value, isNull);
    reportForeground(true);
    expect(notificationAppForeground, isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isFalse);
  });

  final haptics = <String>[];
  setUp(() {
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    notificationAppForeground = true;
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
  });
  tearDown(() {
    onNotifTap = null;
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('builder overlay supports tooltip, updates, and routing',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    onNotifTap = (payload) => navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text(payload['title'] as String)),
          ),
        );
    await tester.pumpWidget(ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (_, value, __) => MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => NotificationPopovers(child: child!),
        home: Scaffold(body: Text('Home $value')),
      ),
    ));
    foregroundNotifications.add({'title': 'Dismiss me'});
    await tester.pumpAndSettle();
    expect(find.text('Dismiss me'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Dismiss')));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Dismiss'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.moveTo(Offset.zero);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss me'), findsNothing);
    await mouse.removePointer();
    revision.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Home 1'), findsOneWidget);
    foregroundNotifications.add({'title': 'Destination'});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  test('destination preserves brief context', () {
    final payload = notificationDestination('url', {
      'kind': 'waiting',
      'message': 'Approve command',
      'destination': {'type': 'session', 'id': 's'},
    });
    expect(payload['kind'], 'waiting');
    expect(payload['body'], 'Approve command');
    expect(payload['session'], 's');
  });

  testWidgets('expiry gives each FIFO item five seconds without haptics',
      (tester) async {
    foregroundNotifications.add({'title': 'First'});
    foregroundNotifications.add({'title': 'Second'});
    await tester.pumpWidget(
        const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    await tester.pump(const Duration(seconds: 4));
    foregroundNotifications.add({'title': 'Third'});
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
    expect(haptics, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('only physical left dismisses in $direction', (tester) async {
      final opened = <Map<String, dynamic>>[];
      onNotifTap = opened.add;
      foregroundNotifications.add({'title': 'Swipe'});
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
        textDirection: direction,
        child: const NotificationPopovers(child: Scaffold()),
      )));
      expect(haptics, isEmpty);
      await tester.drag(find.byType(Dismissible), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Swipe'), findsOneWidget);
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Swipe'), findsNothing);
      expect(opened, isEmpty);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });
  }

  testWidgets('gesture pauses expiry; reduced motion and suppression clean up',
      (tester) async {
    foregroundNotifications.add({'title': 'Held', 'url': 'u', 'session': 's'});
    foregroundNotifications.add({'title': 'Next', 'kind': 'waiting'});
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: NotificationPopovers(child: Scaffold()),
    )));
    expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Held')));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Held'), findsOneWidget);
    await gesture.cancel();
    visibleNotificationSession.value = notificationSessionKey('u', 's');
    await tester.pump();
    await tester.pump();
    expect(find.text('Held'), findsNothing);
    expect(find.text('Needs your input'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Next'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    foregroundNotifications.add({'title': 'After dispose'});
    expect(foregroundNotifications.drain().single['title'], 'After dispose');
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow card handles long title and enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    foregroundNotifications.add({
      'title': List.filled(30, 'Long title').join(' '),
      'kind': 'error',
      'body': List.filled(30, 'Brief context').join(' '),
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const NotificationPopovers(child: Scaffold()),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Failed · Brief context'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to open'), findsNothing);
  });

  testWidgets('whole card tap and dismiss advance the FIFO queue',
      (tester) async {
    final opened = <Map<String, dynamic>>[];
    onNotifTap = opened.add;
    final first = <String, dynamic>{'title': 'First', 'notification_id': 'one'};
    foregroundNotifications.add(first);
    foregroundNotifications.add({'title': 'Second'});
    await tester.pumpWidget(
        const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    foregroundNotifications.add({'title': 'Third'});
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    final card = find.byType(InkWell).first;
    await tester.tapAt(tester.getTopLeft(card) + const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(opened, [same(first)]);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(find.text('Third'), findsOneWidget);
    await tester.tap(find.text('Tap to open'));
    await tester.pumpAndSettle();
    expect(opened.last['title'], 'Third');
    expect(find.byTooltip('Dismiss'), findsNothing);
  });
}
