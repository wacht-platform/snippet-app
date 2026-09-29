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
    d.save(a, const Draft(text: 'half a thought'), now: true);
    expect(d.of(a)?.text, 'half a thought');
    expect(d.has(b), isFalse);
    d.save(a, const Draft(text: '   '), now: true);
    expect(d.has(a), isFalse);
  });

  test('attachments alone keep a draft, and late uploads join it', () async {
    SharedPreferences.setMockInitialValues({});
    final d = Drafts.instance;
    final k = Drafts.keyFor('https://m1', 's3');
    d.addAttachment(k,
        const DraftAttachment(name: 'shot.png', isImage: true, remotePath: '/u/1'));
    expect(d.has(k), isTrue);
    d.addAttachment(k, const DraftAttachment(name: 'Pasted text', pastedText: 'x'));
    expect(d.of(k)?.attachments.map((a) => a.name), ['shot.png', 'Pasted text']);
  });

  test('drafts survive a restart, including older text-only ones', () async {
    SharedPreferences.setMockInitialValues({
      'draft:https://m1|s9': 'unsent',
      'draft:https://m1|s10':
          '{"text":"see this","attachments":[{"name":"a.pdf","remote":"/u/2"}]}',
      'other': 'x',
    });
    await Drafts.instance.init();
    expect(Drafts.instance.of(Drafts.keyFor('https://m1', 's9'))?.text, 'unsent');
    final d = Drafts.instance.of(Drafts.keyFor('https://m1', 's10'))!;
    expect(d.text, 'see this');
    expect(d.attachments.single.remotePath, '/u/2');
  });
}
