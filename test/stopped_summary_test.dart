import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notifications.dart';

void main() {
  test('stopped summary names running lanes', () {
    expect(stoppedSummary(null), 'Finished · standing by');
    expect(stoppedSummary(['Call tracking daemon']),
        'Paused while a lane works: Call tracking daemon');
    expect(
        stoppedSummary(['A', 'B', 'C']), 'Paused while 3 lanes work: A, B +1');
  });
}
