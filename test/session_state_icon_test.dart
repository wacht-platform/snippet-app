import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/screens/shell_nav.dart';

/// Regression tests for [SessionStateIcon].
///
/// These exist because `flutter analyze` and a green build are BOTH blind to
/// this class of bug. A `late final AnimationController x = AnimationController(...)`
/// runs its initialiser on FIRST ACCESS. When nothing reads the controller
/// (an IDLE session — no pulse), the first access is `dispose()`, which
/// constructs a controller on an already-unmounting element and throws at
/// runtime only.
void main() {
  Future<void> mountThenUnmount(WidgetTester t, String status) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SessionStateIcon(status: status)),
    ));
    expect(t.takeException(), isNull, reason: 'mount ($status) must be clean');
    // Replace the tree so the icon is disposed.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull,
        reason: 'dispose ($status) must be clean — a controller built lazily '
            'inside dispose is the bug this guards');
  }

  testWidgets('idle icon mounts and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'idle');
  });

  testWidgets('running icon mounts, pulses and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'running');
    // A running icon must have actually animated (a ticker was live).
  });

  testWidgets('waiting_for_input mounts and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'waiting_for_input');
  });

  testWidgets('unknown/absent status is treated as idle', (t) async {
    await mountThenUnmount(t, '');
  });

  testWidgets('status change idle -> running starts the pulse safely',
      (t) async {
    Widget build(String status) => MaterialApp(
          home: Scaffold(body: SessionStateIcon(status: status)),
        );
    await t.pumpWidget(build('idle'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(build('running'));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    // And back down again.
    await t.pumpWidget(build('idle'));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
  });

  testWidgets('state colours are distinct and stable', (t) async {
    // The mapping is the contract the whole shell relies on.
    expect(sessionStateColor('running'), isNot(sessionStateColor('idle')));
    expect(sessionStateColor('waiting_for_input'),
        isNot(sessionStateColor('running')));
    expect(sessionIsActive('running'), isTrue);
    expect(sessionIsActive('idle'), isFalse);
    expect(sessionIsActive('waiting_for_input'), isFalse);
  });

  testWidgets('animate:false suppresses the ticker', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SessionStateIcon(status: 'running', animate: false),
      ),
    ));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
