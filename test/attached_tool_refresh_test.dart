import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';

class LocalClient extends DaemonClient {
  LocalClient() : super('https://daemon.invalid', 'test');
  final _events = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _events;
}

void main() {
  testWidgets('attached tool results debounce repo refresh without activity',
      (tester) async {
    final client = LocalClient();
    var refreshes = 0;
    bool? forced;
    final watcher = Revalidator(
      client: client,
      on: (e) =>
          e['kind'] == DeviceEventHub.attachedToolResult &&
          e['session'] == 's' &&
          e['workspace'] == '/repo',
      onRevalidate: ({required bool force}) {
        forced = force;
        refreshes++;
      },
    );
    void publish(String wire, List<dynamic> events) =>
        client.deviceEvents.addAttachedToolResults(
          {'wire': wire, 'new_events': events},
          session: 's',
          workspace: '/repo',
        );
    publish('snapshot', [
      {'kind': 'tool_result'}
    ]);
    publish('delta', [
      {'kind': 'tool_call'}
    ]);
    publish('delta', [null, 'bad']);
    await tester.pump(const Duration(seconds: 1));
    expect(refreshes, 0);
    publish('delta', [
      {'kind': 'tool_result'},
      {'kind': 'tool_result'}
    ]);
    publish('delta', [
      {'kind': 'tool_result'}
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    expect(refreshes, 1);
    expect(forced, isTrue);
    watcher.dispose();
  });
}
