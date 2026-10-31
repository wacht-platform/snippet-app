import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets('Reveal animates height', (t) async {
    final show = ValueNotifier(false);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, v, __) => ListView(children: [const SizedBox(height: 50, child: Text("a")),
            Reveal(show: v, child: const SizedBox(height: 200, child: Text('x'))),
          ]),
        ),
      ),
    ));
    expect(t.getSize(find.byType(Reveal)).height, 0);
    show.value = true;
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final mid = t.getSize(find.byType(Reveal)).height;
    expect(mid, inInclusiveRange(1, 199));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(Reveal)).height, 200);
    show.value = false;
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final m2 = t.getSize(find.byType(Reveal)).height;
    expect(m2, inInclusiveRange(1, 199));
  });
}
