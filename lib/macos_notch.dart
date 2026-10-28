import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ambient/controller.dart';
import 'api.dart';
import 'models.dart';
import 'notifications.dart';
import 'platform.dart';
import 'screens/mission_control/mission_control_state.dart'
    show
        AmbientTurn,
        isAmbientResume,
        parseAmbientTurn,
        parseAssignmentEnvelope,
        parseAutonomousRound,
        parseBoardMessage,
        parseCoordinationReply,
        parseDirectMessage,
        parseMissionEnvelope,
        parseParentMessage,
        parseWorkerQuestion,
        supersededAmbientTurns;
import 'store.dart';

class MacosNotch {
  MacosNotch._();

  static const MethodChannel _channel = MethodChannel('snippet/macos_notch');
  static bool _initialized = false;

  static DaemonClient? _defaultClient;
  static WebSocketChannel? _mcSocket;
  static StreamSubscription<dynamic>? _mcSub;
  static HarnessState? _mcState;
  static int _mcRevision = 0;
  static String _mcLiveStreamText = '';
  static String _lastNotifiedKey = '';

  static WebSocketChannel? _activeSocket;
  static StreamSubscription<dynamic>? _activeSub;
  static DaemonClient? _activeClient;
  static String? _activeSessionId;
  static String? _activePeerAgentId;
  static String _activeTitle = 'Mission Control';
  static HarnessState? _activeState;
  static int _activeRevision = 0;
  static String _liveStreamText = '';
  static Timer? _pollTimer;
  static int _nonceCounter = 1;

  static void ensureInitialized() {
    if (_initialized || !kMacOS) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNotificationTap':
          final arg = call.arguments;
          if (arg is String && arg.isNotEmpty) {
            try {
              final payload = jsonDecode(arg) as Map<String, dynamic>;
              onNotifTap?.call(payload);
            } catch (_) {}
          }
        case 'openConversation':
          final arg = call.arguments;
          if (arg is String && arg.isNotEmpty) {
            await _openConversation(arg);
          } else {
            await _openConversation(jsonEncode({
              'session': 'mission-control',
              'title': 'Mission Control',
            }));
          }
        case 'sendConversationReply':
          final args = call.arguments;
          if (args is Map) {
            final text = (args['text'] as String?)?.trim() ?? '';
            if (text.isNotEmpty) {
              await _sendReply(text);
            }
          }
        case 'closeConversation':
          _closeActiveConversation();
      }
    });
  }

  /// Binds the active daemon client so Mission Control chats are always watched
  /// and available in the macOS Notch even when ambient voice is inactive or
  /// another tab is selected.
  static void bindClient(DaemonClient? client) {
    if (!kMacOS) return;
    ensureInitialized();
    if (_defaultClient?.baseUrl == client?.baseUrl &&
        _defaultClient?.token == client?.token &&
        _mcSocket != null) {
      return;
    }
    _stopMcWatch();
    _defaultClient = client;
    if (client != null) {
      _startMcWatch(client);
    }
  }

  static void _startMcWatch(DaemonClient client) {
    try {
      final ch = client.attach('mission-control');
      _mcSocket = ch;
      _mcSub = ch.stream.listen(
        (msg) {
          if (!identical(ch, _mcSocket)) return;
          final raw = switch (msg) {
            final String s => s,
            final Uint8List b => utf8.decode(b, allowMalformed: true),
            final List<int> b => utf8.decode(b, allowMalformed: true),
            _ => '',
          };
          if (raw.isEmpty) return;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is! Map) return;
            final j = decoded.cast<String, dynamic>();
            final wire = j['wire'] as String? ?? 'snapshot';
            if (wire == 'stream') {
              final append = j['append'] == true;
              final chunk = (j['text'] as String?) ?? '';
              _mcLiveStreamText = append ? _mcLiveStreamText + chunk : chunk;
              if (_activeSessionId == 'mission-control') {
                _activeState = _mcState;
                _liveStreamText = _mcLiveStreamText;
                _emitSessionMessages();
              }
              return;
            }
            if (wire == 'snapshot' || wire == 'delta') {
              final rev = j['revision'];
              if (rev is int) {
                if (wire == 'snapshot') {
                  _mcRevision = rev;
                } else if (_mcRevision != 0 && rev == _mcRevision) {
                  return;
                } else {
                  _mcRevision = rev;
                }
              }
              final prev = _mcState;
              final next = (wire == 'delta' && prev != null)
                  ? prev.applyDelta(j)
                  : HarnessState.fromJson(j);
              _mcState = next;
              if (next.status != 'running') {
                _mcLiveStreamText = '';
              }
              if (wire == 'delta' &&
                  prev != null &&
                  next.events.length > prev.events.length) {
                final added = next.events.sublist(prev.events.length);
                for (final e in added.reversed) {
                  final kind = e['kind'] as String? ?? '';
                  var msgText = '';
                  if (kind == 'assistant_text' || kind == 'assistant') {
                    msgText = ((e['text'] as String?) ?? '').trim();
                  } else if (kind == 'tool_call') {
                    final tool = (e['tool_name'] as String?) ?? '';
                    if (tool == 'speak' || tool == 'ambient_speak') {
                      final args = e['arguments'];
                      msgText =
                          args is Map ? '${args['text'] ?? ''}'.trim() : '';
                    }
                  } else if (kind == 'user_question') {
                    msgText = 'Needs your input';
                  }
                  if (msgText.isNotEmpty) {
                    final cleaned =
                        msgText.replaceAll(RegExp(r'\s+'), ' ').trim();
                    showNotification(
                      title: 'Mission Control',
                      subtitle: cleaned,
                      kind: kind == 'user_question' ? 'waiting' : 'message',
                      payload: {
                        'url': client.baseUrl,
                        'session': 'mission-control',
                        'title': 'Mission Control',
                        'body': cleaned,
                        'destination': const {
                          'type': 'session',
                          'id': 'mission-control',
                        },
                      },
                    );
                    break;
                  }
                }
              }
              if (_activeSessionId == 'mission-control') {
                _activeState = next;
                _liveStreamText = _mcLiveStreamText;
                _emitSessionMessages();
              }
            }
          } catch (_) {}
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {}
  }

  static void _stopMcWatch() {
    _mcSub?.cancel();
    _mcSub = null;
    _mcSocket?.sink.close();
    _mcSocket = null;
    _mcState = null;
    _mcRevision = 0;
    _mcLiveStreamText = '';
  }

  static Future<DaemonClient?> _resolveClient(
      Map<String, dynamic> payload) async {
    final url = '${payload['url'] ?? ''}'.trim();
    final name = '${payload['name'] ?? ''}'.trim();
    if (_defaultClient != null &&
        (url.isEmpty || _defaultClient!.baseUrl == url)) {
      return _defaultClient;
    }
    final instances = await InstanceStore().load();
    if (instances.isEmpty) return _defaultClient;
    final resolved =
        instances.where((i) => url.isNotEmpty && i.url == url).firstOrNull ??
            instances
                .where((i) => name.isNotEmpty && i.label == name)
                .firstOrNull ??
            instances.first;
    final client = DaemonClient(resolved.url, resolved.token);
    if (_defaultClient == null) {
      bindClient(client);
    }
    return client;
  }

  static Future<void> _openConversation(String rawPayload) async {
    _closeActiveConversation();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(rawPayload) as Map<String, dynamic>;
    } catch (_) {
      payload = const {
        'session': 'mission-control',
        'title': 'Mission Control',
      };
    }

    final client = await _resolveClient(payload);
    if (client == null) return;
    _activeClient = client;

    final destination = payload['destination'];
    var sessionId = '${payload['session'] ?? ''}'.trim();
    _activeTitle = '${payload['title'] ?? ''}'.trim();

    if (destination is Map && destination['type'] == 'conversation') {
      final threadId = '${destination['id'] ?? ''}';
      try {
        final threads = await client.directThreads();
        for (final t in threads) {
          if (t.threadId == threadId && t.peerKind == 'agent') {
            _activePeerAgentId = t.peerId;
            if (t.title.isNotEmpty) _activeTitle = t.title;
            break;
          }
        }
        if (_activePeerAgentId != null) {
          if (_activeTitle.isEmpty) _activeTitle = 'Conversation';
          await _refreshAgentThread();
          _pollTimer = Timer.periodic(
            const Duration(seconds: 3),
            (_) => _refreshAgentThread(),
          );
          return;
        }
      } catch (_) {}
    }

    // Default to Mission Control whenever no specific session ID is given.
    if (sessionId.isEmpty) {
      sessionId = 'mission-control';
    }
    if (sessionId == 'mission-control' || _activeTitle.isEmpty) {
      _activeTitle =
          sessionId == 'mission-control' ? 'Mission Control' : 'Conversation';
    }

    _activeSessionId = sessionId;
    if (sessionId == 'mission-control') {
      bindClient(client);
      if (_mcState != null) {
        _activeState = _mcState;
        _liveStreamText = _mcLiveStreamText;
        _emitSessionMessages();
      }
      return;
    }
    _attachSession(client, sessionId);
  }

  static Future<void> _refreshAgentThread() async {
    final client = _activeClient;
    final peerId = _activePeerAgentId;
    if (client == null || peerId == null) return;
    try {
      final events = await client.agentThread(peerId: peerId, limit: 60);
      final messages = <Map<String, String>>[];
      for (final e in events) {
        final text = e.body.trim();
        if (text.isEmpty) continue;
        messages.add({
          'role': e.actorKind == 'human' ? 'user' : 'assistant',
          'text': text,
        });
      }
      _pushConversationUpdate(
        title: _activeTitle,
        status: 'idle',
        messages: messages,
      );
    } catch (_) {}
  }

  static void _attachSession(DaemonClient client, String sessionId) {
    final ch = client.attach(sessionId);
    _activeSocket = ch;
    _activeSub = ch.stream.listen(
      (msg) {
        if (!identical(ch, _activeSocket)) return;
        final raw = switch (msg) {
          final String s => s,
          final Uint8List b => utf8.decode(b, allowMalformed: true),
          final List<int> b => utf8.decode(b, allowMalformed: true),
          _ => '',
        };
        if (raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) return;
          final j = decoded.cast<String, dynamic>();
          final wire = j['wire'] as String? ?? 'snapshot';
          if (wire == 'stream') {
            final append = j['append'] == true;
            final chunk = (j['text'] as String?) ?? '';
            _liveStreamText = append ? _liveStreamText + chunk : chunk;
            _emitSessionMessages();
            return;
          }
          if (wire == 'snapshot' || wire == 'delta') {
            final rev = j['revision'];
            if (rev is int) {
              if (wire == 'snapshot') {
                _activeRevision = rev;
              } else if (_activeRevision != 0 && rev == _activeRevision) {
                return;
              } else {
                _activeRevision = rev;
              }
            }
            final cur = _activeState;
            final next = (wire == 'delta' && cur != null)
                ? cur.applyDelta(j)
                : HarnessState.fromJson(j);
            _activeState = next;
            if (sessionId == 'mission-control') {
              _activeTitle = 'Mission Control';
              _mcState = next;
            } else if (next.title != null && next.title!.trim().isNotEmpty) {
              _activeTitle = next.title!.trim();
            }
            if (next.status != 'running') {
              _liveStreamText = '';
            }
            _emitSessionMessages();
          }
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  static String _cleanUserText(String raw) {
    var t = raw.trim();
    final remIdx = t.indexOf('<system-reminder>');
    if (remIdx >= 0) {
      t = t.substring(0, remIdx).trim();
    }
    return t;
  }

  static String _ambientMeta(AmbientTurn turn) {
    final os = turn.device.split('-').first;
    final where = switch (os) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'macos' => 'Mac',
      'linux' => 'Linux',
      'windows' => 'Windows',
      _ => turn.device,
    };
    final at = turn.at;
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return [
      if (where.isNotEmpty) where,
      if (time.isNotEmpty) time,
      if (turn.mode == 'passive') 'passive',
      if (turn.wake) 'wake word',
      if (turn.interruptedReply.isNotEmpty) 'interrupted a reply',
    ].join(' · ');
  }

  static void _emitSessionMessages() {
    final state = _activeState;
    if (state == null) return;
    final superseded = supersededAmbientTurns([
      for (final e in state.events)
        if (e['kind'] == 'user_input' || e['kind'] == 'steer')
          (e['text'] as String?) ?? '',
    ]);
    final messages = <Map<String, String>>[];
    for (final e in state.events) {
      final kind = e['kind'] as String? ?? '';
      if (kind == 'user_input' || kind == 'steer') {
        final raw = (e['text'] as String?) ?? '';
        final ambient = parseAmbientTurn(raw);
        if (ambient != null) {
          if (ambient.ids.isNotEmpty &&
              ambient.ids.every(superseded.contains)) {
            continue;
          }
          if (ambient.text.trim().isNotEmpty) {
            messages.add({
              'role': 'user',
              'text': ambient.text.trim(),
              'meta': _ambientMeta(ambient),
            });
          }
          continue;
        }
        final text = _cleanUserText(raw);
        if (text.isEmpty ||
            isAmbientResume(text) ||
            text.startsWith('<ambient_context_alert') ||
            text.startsWith('<ambient_check_in') ||
            parseMissionEnvelope(text) != null ||
            parseAutonomousRound(text) != null ||
            parseWorkerQuestion(text) != null ||
            parseBoardMessage(text) != null ||
            parseDirectMessage(text) != null ||
            parseCoordinationReply(text) != null ||
            parseParentMessage(text) != null ||
            parseAssignmentEnvelope(text) != null) {
          continue;
        }
        messages.add({'role': 'user', 'text': text});
      } else if (kind == 'assistant_text' || kind == 'assistant') {
        final text = ((e['text'] as String?) ?? '').trim();
        if (text.isNotEmpty) {
          messages.add({'role': 'assistant', 'text': text});
        }
      } else if (kind == 'tool_call') {
        final tool = (e['tool_name'] as String?) ?? '';
        if (tool == 'speak' ||
            tool == 'ambient_speak' ||
            tool.endsWith('__speak')) {
          final args = e['arguments'];
          final spoken = args is Map ? '${args['text'] ?? ''}'.trim() : '';
          final idx = state.events.indexOf(e);
          var turnHasAssistantText = false;
          if (idx >= 0) {
            for (var j = idx + 1; j < state.events.length; j++) {
              final jk = state.events[j]['kind'] as String? ?? '';
              if (jk == 'user_input' || jk == 'steer') break;
              if ((jk == 'assistant_text' || jk == 'assistant') &&
                  '${state.events[j]['text'] ?? ''}'.trim().isNotEmpty) {
                turnHasAssistantText = true;
                break;
              }
            }
            if (!turnHasAssistantText) {
              for (var j = idx - 1; j >= 0; j--) {
                final jk = state.events[j]['kind'] as String? ?? '';
                if (jk == 'user_input' || jk == 'steer') break;
                if ((jk == 'assistant_text' || jk == 'assistant') &&
                    '${state.events[j]['text'] ?? ''}'.trim().isNotEmpty) {
                  turnHasAssistantText = true;
                  break;
                }
              }
            }
          }
          if (spoken.isNotEmpty && !turnHasAssistantText) {
            messages.add({
              'role': 'assistant',
              'text': spoken,
            });
          }
        }
      }
    }
    if (_liveStreamText.trim().isNotEmpty && state.status == 'running') {
      messages.add({'role': 'assistant', 'text': _liveStreamText.trim()});
    }
    final tail = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : messages;
    _pushConversationUpdate(
      title: _activeTitle,
      status: state.status,
      messages: tail,
    );
  }

  static Future<void> _sendReply(String text) async {
    unawaited(
        AmbientController.instance.voice.value?.stopNow() ?? Future.value());
    final client = _activeClient;
    final peerId = _activePeerAgentId;
    if (client != null && peerId != null) {
      try {
        await client.sendAgentMessage(toAgentId: peerId, body: text);
        await _refreshAgentThread();
      } catch (_) {}
      return;
    }

    final ch = _activeSessionId == 'mission-control' ? _mcSocket : _activeSocket;
    if (ch != null && _activeSessionId != null) {
      final nonce =
          'notch-${DateTime.now().millisecondsSinceEpoch}-${_nonceCounter++}';
      final state =
          _activeSessionId == 'mission-control' ? _mcState : _activeState;
      final running = state?.status == 'running';
      if (running) {
        ch.sink.add(jsonEncode({
          'kind': 'queue',
          'value': {'id': nonce, 'text': text},
          'nonce': nonce,
        }));
      } else {
        ch.sink.add(jsonEncode({
          'kind': 'user_message',
          'value': text,
          'nonce': nonce,
        }));
      }
    }
  }

  static void _closeActiveConversation() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _activeSub?.cancel();
    _activeSub = null;
    _activeSocket?.sink.close();
    _activeSocket = null;
    _activeClient = null;
    _activeSessionId = null;
    _activePeerAgentId = null;
    _activeState = null;
    _activeRevision = 0;
    _liveStreamText = '';
  }

  static void _pushConversationUpdate({
    required String title,
    required String status,
    required List<Map<String, String>> messages,
  }) {
    if (!kMacOS) return;
    _channel.invokeMethod<void>('updateConversation', <String, Object?>{
      'title': title,
      'status': status,
      'messages': messages,
    }).catchError((Object _) {});
  }

  static void updateAmbient({
    required bool active,
    required bool userSpeaking,
    required bool assistantSpeaking,
    required double probability,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    _channel.invokeMethod<void>('updateAmbient', <String, Object?>{
      'active': active,
      'userSpeaking': userSpeaking,
      'assistantSpeaking': assistantSpeaking,
      'probability': probability,
    }).catchError((Object _) {});
  }

  static void showNotification({
    required String title,
    required String subtitle,
    required String kind,
    required Map<String, dynamic> payload,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    final dedupeKey = '$title|$subtitle|$kind';
    if (dedupeKey == _lastNotifiedKey) return;
    _lastNotifiedKey = dedupeKey;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_lastNotifiedKey == dedupeKey) _lastNotifiedKey = '';
    });
    _channel.invokeMethod<void>('showNotification', <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'kind': kind,
      'payload': jsonEncode(payload),
    }).catchError((Object _) {});
  }
}
