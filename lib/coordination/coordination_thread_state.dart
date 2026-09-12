import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../models.dart';

/// Cursor-backed state for one coordination thread. The daemon remains the
/// source of truth; this class only owns paging, deduplication, and send state.
class CoordinationThreadState extends ChangeNotifier {
  CoordinationThreadState({required this.client, required this.threadId});

  final DaemonClient client;
  final String threadId;
  final List<CoordinationEvent> events = [];
  StreamSubscription<dynamic>? _coordinationSubscription;
  WebSocketChannel? _coordinationSocket;

  /// Attach to persisted coordination events. Reconnect callers should invoke
  /// [refresh] first, then call this method so replay closes any missed range.
  void attachLive() {
    _coordinationSubscription?.cancel();
    _coordinationSocket?.sink.close();
    try {
      final socket = client.attachCoordinationEvents();
      _coordinationSocket = socket;
      _coordinationSubscription = socket.stream.listen((raw) {
        try {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          final event = CoordinationEvent.fromJson(
              frame['event'] as Map<String, dynamic>);
          if (event.threadId != threadId) return;
          _merge([event], advanceReplayCursor: false);
          notifyListeners();
        } catch (_) {
          // Persisted replay remains authoritative when a malformed frame arrives.
        }
      }, onDone: () {}, onError: (_) {});
    } catch (_) {
      // The next refresh/reconnect may attach again.
    }
  }

  @override
  void dispose() {
    _coordinationSubscription?.cancel();
    _coordinationSocket?.sink.close();
    super.dispose();
  }

  bool loading = false;
  bool sending = false;
  String? error;

  int _replayCursor = 0;
  int get cursor => _replayCursor;
  List<CoordinationEvent> get visibleEvents => List.unmodifiable(events);

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    try {
      const pageSize = 100;
      while (true) {
        final incoming = await client.coordinationEvents(threadId,
            afterSequence: _replayCursor, limit: pageSize);
        if (incoming.isEmpty) break;
        _merge(incoming, advanceReplayCursor: true);
        if (incoming.length < pageSize) break;
      }
      notifyListeners();
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
    }
  }

  Future<CoordinationEvent?> send({
    required String actorKind,
    required String actorId,
    required String body,
    String? idempotencyKey,
  }) async {
    if (sending || body.trim().isEmpty) return null;
    sending = true;
    error = null;
    try {
      final event = await client.postCoordinationMessage(threadId,
          actorKind: actorKind,
          actorId: actorId,
          body: body,
          idempotencyKey: idempotencyKey);
      _merge([event], advanceReplayCursor: false);
      notifyListeners();
      return event;
    } catch (e) {
      error = '$e';
      return null;
    } finally {
      sending = false;
    }
  }

  void _merge(Iterable<CoordinationEvent> incoming,
      {required bool advanceReplayCursor}) {
    final byId = <String, CoordinationEvent>{
      for (final event in events) event.eventId: event,
    };
    for (final event in incoming) {
      byId[event.eventId] = event;
      if (advanceReplayCursor && event.sequence > _replayCursor) {
        _replayCursor = event.sequence;
      }
    }
    events
      ..clear()
      ..addAll(byId.values.toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence)));
  }
}
