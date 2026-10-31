import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/crew_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/theme.dart';

CoordinationAgent _a(String id, String name) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': name});

void main() {
  testWidgets('crew popover is a 2x2 grid and survives a right-click menu',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 400);
    addTearDown(tester.view.reset);
    final menu = Completer<void>();
    var menus = 0;
    final entries = deriveCrew(
        [_a('a', 'Scout'), _a('b', 'Reviewer'), _a('c', 'Snippet')], const []);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: CrewStack(
              entries: entries,
              onOpen: (_) {},
              onNew: () {},
              onMenu: (ctx, agent, point) {
                menus++;
                return menu.future;
              },
            ),
          ),
        ),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(CrewStack)));
    await tester.pump(const Duration(milliseconds: 50));
    final scout = tester.getTopLeft(find.text('Scout'));
    final reviewer = tester.getTopLeft(find.text('Reviewer'));
    final snippet = tester.getTopLeft(find.text('Snippet'));
    final add = tester.getTopLeft(find.text('New agent'));
    expect(reviewer.dx, greaterThan(scout.dx));
    expect((reviewer.dy - scout.dy).abs(), lessThan(40));
    expect(snippet.dx, scout.dx);
    expect(snippet.dy, greaterThan(scout.dy + 60));
    expect(add.dy, greaterThan(scout.dy + 60));
    expect(add.dx, greaterThan(snippet.dx));

    await mouse.moveTo(tester.getCenter(find.text('Scout')));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('Scout')),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await tester.pump();
    expect(menus, 1);
    await mouse.moveTo(const Offset(600, 380));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Scout'), findsOneWidget);
    menu.complete();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Scout'), findsNothing);
  });
}
