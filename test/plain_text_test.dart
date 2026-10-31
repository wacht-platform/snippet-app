import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/plain_text.dart';

void main() {
  test('strips inline markdown for plain surfaces', () {
    expect(plainInline('**Scheduled run — Fresh X (<60m)**'),
        'Scheduled run — Fresh X (<60m)');
    expect(plainInline('Use `cargo test` and [docs](http://x.y)'),
        'Use cargo test and docs');
    expect(plainInline('**Composer:** the label *now* collapses'),
        'Composer: the label now collapses');
    expect(plainInline('snake_case_name stays'), 'snake_case_name stays');
    expect(plainInline('## Heading'), 'Heading');
  });
}
