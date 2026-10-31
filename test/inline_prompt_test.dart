import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/dialog_widgets.dart';

void main() {
  testWidgets('anchored prompt is a popover, returns the typed value',
      (t) async {
    String? out;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => out = await promptText(c,
              title: 'Nickname', initial: 'a', anchored: true),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await t.enterText(find.byType(TextField), 'Zed');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(out, 'Zed');
  });
}
