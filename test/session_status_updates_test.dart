import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/session_status_updates.dart';

SessionInfo row(String status) =>
    SessionInfo.fromJson({'id': 's', 'status': status});

void main() {
  test('fresh list retires pre-fetch idle and running statuses', () {
    final updates = SessionStatusUpdates();
    for (final old in ['idle', 'running']) {
      updates.record('s', old);
      final revision = updates.revision;
      final rows = [row(old == 'idle' ? 'running' : 'idle')];
      updates.merge(rows, since: revision);
      expect(rows.single.status, old == 'idle' ? 'running' : 'idle');
    }
  });

  test('slow list preserves only concurrent updates, then reconciles', () {
    final updates = SessionStatusUpdates();
    final revision = updates.revision;
    updates.record('s', 'running');
    updates.record('s', 'waiting_for_input');
    final rows = [row('idle')];
    updates.merge(rows, since: revision);
    expect(rows.single.status, 'waiting_for_input');
    final fresh = [row('idle')];
    updates.merge(fresh, since: updates.revision);
    expect(fresh.single.status, 'idle');
  });

  test('instance clear discards concurrent updates', () {
    final updates = SessionStatusUpdates();
    final revision = updates.revision;
    updates.record('s', 'running');
    updates.clear();
    final rows = [row('idle')];
    updates.merge(rows, since: revision);
    expect(rows.single.status, 'idle');
  });

  test('optimistic running wins over old state until attach acknowledges', () {
    final idle = HarnessState.fromJson({'status': 'idle'});
    expect(sessionDisplayStatus(idle, true), 'running');
    expect(sessionDisplayStatus(idle, false), 'idle');
    final waiting = HarnessState.fromJson({'status': 'waiting_for_input'});
    expect(sessionDisplayStatus(waiting, false), 'waiting_for_input');
  });
}
