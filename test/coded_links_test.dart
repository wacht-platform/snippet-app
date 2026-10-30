import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/widgets.dart';

void main() {
  test('backticked session and artifact links become links', () {
    expect(unwrapCodedLinks('in `[Demo — x](session:abc-1)` ok'),
        'in [Demo — x](session:abc-1) ok');
    expect(unwrapCodedLinks('`[A](artifact:z)`'), '[A](artifact:z)');
    expect(unwrapCodedLinks('`code` and `[a](https://x.y)`'),
        '`code` and `[a](https://x.y)`');
  });
}
