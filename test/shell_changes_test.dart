import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/file_changes.dart';
import 'package:snippet/tool_activity.dart';

Map<String, dynamic> _turn(List<List<Object>> files) => {
      'kind': 'turn_changes',
      'files': [
        for (final f in files) {'path': f[0], 'add': f[1], 'del': f[2]}
      ],
    };

void main() {
  test('shell edits are listed, summed across turns, and not double counted', () {
    final covered = [
      FileChange('/w/lib/local_service.dart', FileChangeKind.created)
    ];
    final r = shellChanges([
      _turn([
        ['lib/local_service.dart', 101, 0],
        ['lib/screens/shell_welcome.dart', 10, 2]
      ]),
      _turn([
        ['lib/screens/shell_welcome.dart', 5, 1]
      ]),
      {'kind': 'tool_call'},
    ], covered);
    expect(r.map((c) => c.path), ['lib/screens/shell_welcome.dart']);
    expect((r.single.add, r.single.del), (15, 3));
  });

  test('no turn_changes means no shell rows', () {
    expect(shellChanges([{'kind': 'x'}], const []), isEmpty);
  });
}
