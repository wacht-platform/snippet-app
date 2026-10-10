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
    // The mapping is the contract the whole shell relies on. `isNot` alone is
    // NOT enough: two colours can differ while being indistinguishable. State is
    // carried by colour alone, so each pair must also SEPARATE in luminance.
    double ratio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    final idle = sessionStateColor('idle');
    final busy = sessionStateColor('running');
    final wants = sessionStateColor('waiting_for_input');

    expect(wants, isNot(idle));
    expect(wants, isNot(busy));
    expect(ratio(wants, idle), greaterThanOrEqualTo(2.0),
        reason: 'the accent is neutral, so "needs you" must out-brighten idle '
            'rather than differ by hue');
    expect(ratio(wants, busy), greaterThanOrEqualTo(2.0),
        reason: '"needs you" must not read as "busy"');

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
