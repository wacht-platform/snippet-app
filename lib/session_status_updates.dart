import 'models.dart';

class SessionStatusUpdates {
  int _revision = 0;
  final Map<String, ({int revision, String status})> _updates = {};

  int get revision => _revision;

  void record(String id, String status) {
    _updates[id] = (revision: ++_revision, status: status);
  }

  void clear() => _updates.clear();

  void merge(List<SessionInfo> sessions, {required int since}) {
    for (var i = 0; i < sessions.length; i++) {
      final update = _updates[sessions[i].id];
      if (update != null && update.revision > since) {
        sessions[i] = sessions[i].withStatus(update.status);
      }
    }
  }
}

String sessionDisplayStatus(HarnessState? state, bool running) =>
    running ? 'running' : (state?.status ?? 'idle');
