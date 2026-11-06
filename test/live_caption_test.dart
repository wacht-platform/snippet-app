import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient/live_caption.dart';

void main() {
  testWidgets('a caption clears soon after the last words', (tester) async {
    final feed = LiveCaptionFeed();
    feed.apply({'text': 'hello', 'final': false});
    await tester.pump(const Duration(seconds: 3));
    feed.apply({'text': 'hello there', 'final': false});
    await tester.pump(const Duration(seconds: 3));
    expect(feed.text.value, 'hello there');
    feed.apply({'text': 'hello there boss', 'final': true});
    await tester.pump(const Duration(milliseconds: 2400));
    expect(feed.text.value, 'hello there boss');
    await tester.pump(const Duration(milliseconds: 200));
    expect(feed.text.value, isNull);
  });

  testWidgets('the caption floats above the composer without moving it or taking taps', (tester) async {
    final feed = LiveCaptionFeed();
    final composer = GlobalKey();
    final behind = GlobalKey();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Expanded(
          child: GestureDetector(key: behind, behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const SizedBox.expand()),
        ),
        LiveCaptionAnchor(
          feed: feed,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: SizedBox(key: composer, height: 60),
        ),
      ]),
    ));
    final before = tester.getRect(find.byKey(composer));
    const words = 'what is the status of the build';
    feed.apply({'text': words, 'final': true});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(find.byKey(composer)), before);
    expect(tester.getBottomLeft(find.text(words)).dy, lessThan(before.top));
    await tester.tapAt(tester.getCenter(find.text(words)));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(words), findsNothing);
  });
}
