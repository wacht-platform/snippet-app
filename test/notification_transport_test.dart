import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/device_events.dart';
import 'package:snippet/notification_inbox.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('saved desktop shell delivers real WS and reconnect HTTP alerts',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = ['xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events', 'xyz.luan/audioplayers',
      'com.llfbandit.record/messages'];
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if (call.method == 'create') {
        final name = 'xyz.luan/audioplayers/events/${(call.arguments as Map)['playerId']}';
        channels.add(name);
        messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      }
      return null;
    });
    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    late String oldPath;
    late Directory directory;
    late HttpServer server;
    await tester.runAsync(() async {
      oldPath = await factory.getDatabasesPath();
      directory = await Directory.systemTemp.createTemp('notification-transport-');
      await factory.setDatabasesPath(directory.path);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
    final url = 'http://127.0.0.1:${server.port}';
    final sockets = <WebSocket>[];
    final eventSockets = <WebSocket>[];
    final requests = <String>[];
    final errors = <Object>[];
    final recovered = <Map<String, dynamic>>[];
    var pages = 0;
    final subscription = server.listen((request) async {
      try {
        final path = request.uri.path;
        requests.add(request.uri.toString());
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          if (path == '/events') eventSockets.add(socket);
          socket.listen((_) {}, onError: errors.add);
          return;
        }
        Object body;
        switch (path) {
          case '/mission-control/open': body = {'id': 'mission-control'};
          case '/health': body = {'ok': true};
          case '/sessions': body = <Object>[];
          case '/sessions/counts': body = <String, int>{};
          case '/config': body = {'profiles': [], 'active_profile': ''};
          case '/notifications':
            pages++;
            body = {'events': recovered, 'has_more': false,
              'next_cursor': recovered.isEmpty
                  ? {'created_at': 0, 'event_id': 0}
                  : {'created_at': recovered.last['created_at'], 'event_id': recovered.last['event_id']}};
          default: body = <String, dynamic>{};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
      } catch (error) { errors.add(error); }
    });
    SharedPreferences.setMockInitialValues({
      'instances': jsonEncode([{'name': 'Loopback machine', 'url': url, 'token': 'fixture'}]),
      'notif_enabled': false,
    });
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    notificationAppForeground = true;
    final delivered = <Map<String, dynamic>>[];
    final queueSubscription = foregroundNotifications.stream.listen(delivered.add);
    NotificationInbox? inbox;
    addTearDown(() => tester.runAsync(() async {
      await queueSubscription.cancel();
      for (final socket in sockets) { unawaited(socket.close()); }
      unawaited(subscription.cancel());
      unawaited(server.close(force: true));
      await inbox?.db.close();
      await factory.setDatabasesPath(oldPath);
      await directory.delete(recursive: true);
      HttpOverrides.global = oldOverrides;
      debugDefaultTargetPlatformOverride = null;
      for (final name in channels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
      visibleNotificationSession.value = null;
      foregroundNotifications.drain();
    }));
    Future<void> until(bool Function() ready, String stage) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull, reason: stage);
        expect(errors, isEmpty, reason: stage);
      }
      expect(ready(), isTrue, reason: '$stage; requests=$requests; delivered=$delivered');
    }
    await tester.pumpWidget(const MaterialApp(
      home: NotificationPopovers(child: DesktopShell()),
    ));
    await until(() => eventSockets.isNotEmpty && pages > 0, 'saved shell selected and connected');
    await tester.runAsync(() async { inbox = await NotificationInbox.open(); });
    expect(inbox!.db.path, startsWith(directory.path));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Map<String, dynamic> event(int id, String title) => {
      'notification_id': '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
      'event_id': id, 'created_at': now, 'expires_at': now + 3600,
      'kind': 'waiting', 'title': title, 'message': 'Approve fixture',
      'destination': {'type': 'session', 'id': 'transport-chat'},
    };
    final live = event(1, 'Observed socket alert');
    final wire = jsonEncode({'kind': 'notification', 'notification': live});
    expect(DeviceEvent.decode(wire)!.notification, live);
    for (final socket in eventSockets) { socket.add(wire); }
    await until(() => delivered.length == 1, 'WS decoded, ingested and queued');
    expect(find.text('Observed socket alert'), findsOneWidget);
    expect(delivered.single['notification_id'], live['notification_id']);
    await tester.runAsync(() async {
      expect(await inbox!.db.query('inbox'), hasLength(1));
    });
    for (final socket in eventSockets) { socket.add(wire); }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(delivered, hasLength(1));
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump(const Duration(milliseconds: 400));
    visibleNotificationSession.value = notificationSessionKey(url, 'transport-chat');
    for (final socket in eventSockets) {
      socket.add(jsonEncode({'kind': 'notification', 'notification': event(2, 'Same chat hidden')}));
    }
    var rows = 0;
    for (var i = 0; i < 100 && rows < 2; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        rows = (await inbox!.db.query('inbox')).length;
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(rows, 2, reason: 'same-chat delivery must persist before suppression');
    expect(delivered, hasLength(1));
    expect(find.text('Same chat hidden'), findsNothing);
    visibleNotificationSession.value = null;
    recovered.add(event(3, 'Observed reconnect alert'));
    final previousPages = pages;
    final previousConnections = eventSockets.length;
    await tester.runAsync(() async {
      for (final socket in eventSockets.toList()) { unawaited(socket.close()); }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 3));
    await until(() => pages > previousPages && delivered.length == 2,
        'reconnect HTTP recovery ingested and queued');
    expect(find.text('Observed reconnect alert'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await inbox!.db.query('inbox'), hasLength(3));
    });
    expect(eventSockets.length, greaterThan(previousConnections));
    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (final socket in sockets) { unawaited(socket.close()); }
      unawaited(server.close(force: true));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(seconds: 60));
    debugDefaultTargetPlatformOverride = null;
  });
}
