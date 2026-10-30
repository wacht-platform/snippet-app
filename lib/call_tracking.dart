import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'session_quick_send.dart' show resolveInstanceForPayload;

const callPromptType = 'call_prompt';
const callStateType = 'call_state';
const callActionTrack = 'track';
const callActionIgnore = 'ignore';
const callActionStop = 'stop';
const callPromptTitle = 'Take notes on this conversation?';
const callPromptBody =
    "Sounds like you're talking with someone. Snippet can keep notes.";

class CallEvent {
  const CallEvent({
    required this.type,
    required this.callId,
    this.expiresAtMs = 0,
    this.state = '',
    this.title = callPromptTitle,
    this.body = callPromptBody,
    this.auto = false,
    this.label = '',
  });
  final bool auto;
  final String label;
  final String type;
  final String callId;
  final int expiresAtMs;
  final String state;
  final String title;
  final String body;

  bool get isPrompt => type == callPromptType;
}

int _ms(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  return n > 0 && n < 100000000000 ? n * 1000 : n;
}

/// The only place that knows where the daemon puts the call payload inside a
/// notification event: top level, or nested under `call`/`payload`/`data`/`attention`.
CallEvent? parseCallEvent(Map<String, dynamic> event) {
  final scopes = <Map<String, dynamic>>[event];
  for (final key in const ['call', 'payload', 'data', 'attention']) {
    final v = event[key];
    if (v is Map) scopes.add(v.cast<String, dynamic>());
  }
  for (final scope in scopes) {
    final type = '${scope['type'] ?? scope['kind'] ?? ''}'.split('.').last;
    if (type != callPromptType && type != callStateType) continue;
    final id = scopes
        .map((s) => '${s['call_id'] ?? ''}')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (id.isEmpty) return null;
    final expires = scopes
        .map((s) => _ms(s['expires_at']))
        .firstWhere((v) => v > 0, orElse: () => 0);
    final title = '${scope['title'] ?? event['title'] ?? ''}';
    final body = '${scope['body'] ?? event['body'] ?? ''}';
    return CallEvent(
      type: type,
      callId: id,
      expiresAtMs: expires,
      state: '${scope['state'] ?? ''}',
      title: title.isEmpty ? callPromptTitle : title,
      body: body.isEmpty ? callPromptBody : body,
      auto: scopes.any((s) => s['auto'] == true),
      label: scopes
          .map((s) => '${s['label'] ?? ''}')
          .firstWhere((s) => s.isNotEmpty, orElse: () => ''),
    );
  }
  return null;
}

/// Stable per call so a call_state event can cancel the prompt.
int callNotificationId(String callId) {
  var h = 0x811c9dc5;
  for (final c in 'call|$callId'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return 0x20000000 | (h & 0x0fffffff);
}

enum CallPhase { pending, tracking }

class CallStatus {
  const CallStatus({
    required this.callId,
    required this.phase,
    required this.url,
    this.expiresAtMs = 0,
    this.title = callPromptTitle,
    this.body = callPromptBody,
    this.auto = false,
    this.label = '',
  });
  final bool auto;
  final String label;
  final String callId;
  final CallPhase phase;
  final String url;
  final int expiresAtMs;
  final String title;
  final String body;
}

class CallTracker {
  CallTracker({int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  final int Function() _now;
  final state = ValueNotifier<CallStatus?>(null);
  Timer? _expiry;

  /// Applies a call_prompt or call_state event; returns whether it changed state.
  bool apply(String url, CallEvent e) {
    final current = state.value;
    if (e.isPrompt) {
      if (e.expiresAtMs > 0 && e.expiresAtMs <= _now()) return false;
      if (current?.phase == CallPhase.tracking) return false;
      _set(CallStatus(
          callId: e.callId,
          phase: CallPhase.pending,
          url: url,
          expiresAtMs: e.expiresAtMs,
          title: e.title,
          body: e.body));
      return true;
    }
    if (e.state == 'tracking') {
      _set(CallStatus(
          callId: e.callId,
          phase: CallPhase.tracking,
          url: url,
          auto: e.auto,
          label: e.label));
      return true;
    }
    if (current != null && current.callId == e.callId) {
      _set(null);
      return true;
    }
    return false;
  }

  /// Seeds from GET /ambient/call (a pending prompt that predates this launch).
  bool applySnapshot(String url, Map<String, dynamic> body) {
    final id = '${body['call_id'] ?? ''}';
    final s = '${body['state'] ?? ''}';
    if (id.isEmpty) return false;
    if (s == 'pending') {
      return apply(
          url,
          CallEvent(
              type: callPromptType,
              callId: id,
              expiresAtMs: _ms(body['expires_at'])));
    }
    if (s == 'tracking') {
      return apply(
          url, CallEvent(type: callStateType, callId: id, state: 'tracking'));
    }
    return false;
  }

  void clear() => _set(null);

  void _set(CallStatus? next) {
    _expiry?.cancel();
    _expiry = null;
    if (next != null &&
        next.phase == CallPhase.pending &&
        next.expiresAtMs > 0) {
      final id = next.callId;
      _expiry = Timer(Duration(milliseconds: next.expiresAtMs - _now()), () {
        if (state.value?.callId == id) state.value = null;
      });
    }
    state.value = next;
  }

  /// Runs a track/ignore/stop against the daemon and updates local state.
  /// 404 and 409 mean the call is already resolved, so they just dismiss.
  Future<bool> act(DaemonClient client, String callId, String action) async {
    final int status;
    try {
      status = await client.ambientCallAction(callId, action);
    } catch (_) {
      return false;
    }
    final gone = status == 404 || status == 409;
    if (status != 200 && !gone) return false;
    if (state.value?.callId == callId) {
      if (action == callActionTrack && !gone) {
        _set(CallStatus(
            callId: callId, phase: CallPhase.tracking, url: client.baseUrl));
      } else {
        _set(null);
      }
    }
    return true;
  }

  Future<void> refresh(String url, DaemonClient client) async {
    try {
      applySnapshot(url, await client.ambientCall());
    } catch (_) {}
  }
}

final callTracker = CallTracker();

/// Routes a notification action button (`call_track` / `call_ignore`).
Future<bool> callActionForPayload(
    Map<String, dynamic> payload, String action) async {
  final id = '${payload['call_id'] ?? ''}';
  if (id.isEmpty) return false;
  final instance = await resolveInstanceForPayload(payload);
  if (instance == null) return false;
  return callTracker.act(DaemonClient(instance.url, instance.token), id, action);
}
