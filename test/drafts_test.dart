import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/drafts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drafts are kept per session and cleared when emptied', () async {
    SharedPreferences.setMockInitialValues({});
    final d = Drafts.instance;
    final a = Drafts.keyFor('https://m1', 's1');
    final b = Drafts.keyFor('https://m1', 's2');
    d.save(a, 'half a thought', now: true);
    expect(d.of(a), 'half a thought');
    expect(d.has(b), isFalse);
    d.save(a, '   ', now: true);
    expect(d.has(a), isFalse);
  });

  test('drafts survive a restart', () async {
    SharedPreferences.setMockInitialValues(
        {'draft:https://m1|s9': 'unsent', 'other': 'x'});
    await Drafts.instance.init();
    expect(Drafts.instance.of(Drafts.keyFor('https://m1', 's9')), 'unsent');
  });
}
