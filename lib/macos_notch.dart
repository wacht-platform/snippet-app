import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'models.dart';
import 'notifications.dart';
import 'platform.dart';
import 'store.dart';

class MacosNotch {
  MacosNotch._();

  static const MethodChannel _channel = MethodChannel('snippet/macos_notch');
  static bool _initialized = false;

  static WebSocketChannel? _activeSocket;
  static StreamSubscription<dynamic>? _activeSub;
  static DaemonClient? _activeClient;
  static String? _activeSessionId;
  static String? _activePeerAgentId;
  static String _activeTitle = 'Conversation';
  static HarnessState? _activeState;
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

  static Future<DaemonClient?> _resolveClient(Map<String, dynamic> payload) async {
    final url = '${payload['url'] ?? ''}';
    final name = '${payload['name'] ?? ''}';
    final instances = await InstanceStore().load();
    if (instances.isEmpty) return null;
    final resolved = instances.where((i) => i.url == url).firstOrNull ??
        instances.where((i) => name.isNotEmpty && i.label == name).firstOrNull ??
        instances.first;
    return DaemonClient(resolved.url, resolved.token);
  }

  static Future<void> _openConversation(String rawPayload) async {
    _closeActiveConversation();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(rawPayload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final client = await _resolveClient(payload);
    if (client == null) return;
    _activeClient = client;

    final destination = payload['destination'];
    final sessionId = '${payload['session'] ?? ''}'.trim();
    _activeTitle = '${payload['title'] ?? 'Conversation'}'.trim();
    if (_activeTitle.isEmpty) _activeTitle = 'Conversation';

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
          await _refreshAgentThread();
          _pollTimer = Timer.periodic(
            const Duration(seconds: 3),
            (_) => _refreshAgentThread(),
          );
          return;
        }
      } catch (_) {}
    }

    if (sessionId.isNotEmpty) {
      _activeSessionId = sessionId;
      _attachSession(client, sessionId);
    } else {
      final body = '${payload['body'] ?? ''}'.trim();
      _pushConversationUpdate(
        title: _activeTitle,
        status: 'idle',
        messages: [
          if (body.isNotEmpty) {'role': 'assistant', 'text': body},
        ],
      );
    }
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
            final cur = _activeState;
            final next = (wire == 'delta' && cur != null)
                ? cur.applyDelta(j)
                : HarnessState.fromJson(j);
            _activeState = next;
            if (next.title != null && next.title!.trim().isNotEmpty) {
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

  static void _emitSessionMessages() {
    final state = _activeState;
    if (state == null) return;
    final messages = <Map<String, String>>[];
    for (final e in state.events) {
      final kind = e['kind'] as String? ?? '';
      if (kind == 'user_input' || kind == 'steer') {
        final raw = (e['text'] as String?) ?? '';
        final text = _cleanUserText(raw);
        if (text.isEmpty ||
            text.startsWith('<ambient_') ||
            text.startsWith('[mission_control_task]') ||
            text.startsWith('[coordination_board_message]')) {
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
        if (tool == 'speak' || tool == 'ambient_speak') {
          final args = e['arguments'];
          final spoken = args is Map ? '${args['text'] ?? ''}'.trim() : '';
          if (spoken.isNotEmpty) {
            messages.add({'role': 'assistant', 'text': spoken});
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
    final client = _activeClient;
    final peerId = _activePeerAgentId;
    if (client != null && peerId != null) {
      try {
        await client.sendAgentMessage(toAgentId: peerId, body: text);
        await _refreshAgentThread();
      } catch (_) {}
      return;
    }

    final ch = _activeSocket;
    if (ch != null && _activeSessionId != null) {
      final nonce = 'notch-${DateTime.now().millisecondsSinceEpoch}-${_nonceCounter++}';
      final running = _activeState?.status == 'running';
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
    _liveStreamText = '';
  }

  static void _pushConversationUpdate({
    required String title,
    required String status,
    required List<Map<String, String>> messages,
  }) {
    if (!kMacOS) return;
    _channel.invokeMethod<void>('updateConversation', {
      'title': title,
      'status': status,
      'messages': messages,
    }).catchError((_) {});
  }

  static void updateAmbient({
    required bool active,
    required bool userSpeaking,
    required bool assistantSpeaking,
    required double probability,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    _channel.invokeMethod<void>('updateAmbient', {
      'active': active,
      'userSpeaking': userSpeaking,
      'assistantSpeaking': assistantSpeaking,
      'probability': probability,
    }).catchError((_) {});
  }

  static void showNotification({
    required String title,
    required String subtitle,
    required String kind,
    required Map<String, dynamic> payload,
  }) {
    if (!kMacOS) return;
    ensureInitialized();
    _channel.invokeMethod<void>('showNotification', {
      'title': title,
      'subtitle': subtitle,
      'kind': kind,
      'payload': jsonEncode(payload),
    }).catchError((_) {});
  }
}
