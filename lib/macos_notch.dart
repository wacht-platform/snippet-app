import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ambient/controller.dart';
import 'api.dart';
import 'call_tracking.dart';
import 'models.dart';
import 'notch_home.dart';
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
import 'tool_activity.dart' show ToolStep, toolSentence;
import 'session_quick_send.dart'
    show
        QuickAction,
        QuickAnswer,
        QuickApprove,
        QuickDeny,
        QuickReply,
        quickSend,
        quickSendForPayload,
        resolveInstanceForPayload;

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
        case 'notchAction':
          final args = call.arguments;
          if (args is Map) {
            await _sendNotchAction(
                '${args['action'] ?? ''}', '${args['text'] ?? ''}');
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
        case 'toggleAmbient':
          await _toggleAmbient();
        case 'homeAction':
          final home = call.arguments;
          if (home is Map) await NotchHome.handleAction(home);
        case 'bannerAction':
          final args = call.arguments;
          if (args is Map) {
            await _bannerAction('${args['action'] ?? ''}', '${args['payload'] ?? ''}');
          }
        case 'callAction':
          final args = call.arguments;
          if (args is Map) {
            await _callAction('${args['action'] ?? ''}');
          }
      }
    });
    callTracker.state.addListener(_syncCall);
  }

  static Future<void> _bannerAction(String action, String payload) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final attn = data['attention'];
    final QuickAction? send = switch (action) {
      'approve' => const QuickApprove(),
      'deny' => const QuickDeny(),
      final a when a.startsWith('choice:') => () {
          final value = a.substring(7);
          final q = attn is Map ? '${attn['text'] ?? ''}'.trim() : '';
          return QuickAnswer(q.isEmpty ? value : '$q\n→ $value');
        }(),
      _ => null,
    };
    if (send != null) await quickSendForPayload(data, send);
  }

  static String? _notchCallKey;

  static Future<void> _callAction(String action) async {
    final status = callTracker.state.value;
    if (status == null || !const {'track', 'ignore', 'stop'}.contains(action)) {
      return;
    }
    final instance = await resolveInstanceForPayload({'url': status.url});
    if (instance == null) return;
    await callTracker.act(
        DaemonClient(instance.url, instance.token), status.callId, action);
  }

  static void _syncCall() {
    final c = callTracker.state.value;
    final key = c == null ? null : '${c.callId}|${c.phase.name}';
    if (key == _notchCallKey) return;
    _notchCallKey = key;
    final future = switch (c?.phase) {
      CallPhase.pending => _channel.invokeMethod<void>('callPrompt', {
          'callId': c!.callId,
          'expiresAtMs': c.expiresAtMs,
          'title': 'Conversation',
          'message': c.title,
        }),
      CallPhase.tracking =>
        _channel.invokeMethod<void>('callTracking', {'callId': c!.callId}),
      null => _channel.invokeMethod<void>('callClear'),
    };
    future.catchError((Object _) {});
  }

  static Future<void> _toggleAmbient() async {
    final client = await _resolveClient(const {});
    if (client == null) return;
    final ctrl = AmbientController.instance;
    final nextOn = !ctrl.running;
    final (_, err) = await ctrl.setEnabled(client, nextOn);
    showNotification(
      title: 'Ambient Voice',
      subtitle: err != null
          ? 'Error: $err'
          : (nextOn ? 'Listening turned on (⌥⇧Space)' : 'Listening turned off'),
      kind: 'ambient',
      payload: {
        'url': client.baseUrl,
        'session': 'mission-control',
        'title': 'Mission Control',
      },
    );
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
    NotchHome.bind(client);
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
    final openType = payload['type'];
    if (openType == 'openArtifact' || openType == 'openImage') {
      final actionPayload = <String, dynamic>{
        ...payload,
        'url': client.baseUrl
      };
      await _channel.invokeMethod<void>('openInApp', actionPayload);
      return;
    }

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
      final messages = <Map<String, dynamic>>[];
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
      if (turn.userVoice != null) 'voice ${(turn.userVoice! * 100).round()}%',
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
    final messages = <Map<String, dynamic>>[];
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
        messages
            .add({'role': 'user', 'text': text, 'meta': '', 'type': 'message'});
      } else if (kind == 'assistant_text' || kind == 'assistant') {
        var text = ((e['text'] as String?) ?? '').trim();
        final idx = state.events.indexOf(e);
        if (idx > 0) {
          for (var j = idx - 1; j >= 0; j--) {
            final jk = state.events[j]['kind'] as String? ?? '';
            if (jk == 'user_input' || jk == 'steer') break;
            if (jk == 'tool_call') {
              final tool = (state.events[j]['tool_name'] as String?) ?? '';
              if (tool == 'speak' ||
                  tool == 'ambient_speak' ||
                  tool.endsWith('__speak')) {
                final args = state.events[j]['arguments'];
                final spoken =
                    args is Map ? '${args['text'] ?? ''}'.trim() : '';
                if (spoken.isNotEmpty) {
                  if (text == spoken) {
                    text = '';
                    break;
                  } else if (text.startsWith(spoken)) {
                    text = text.substring(spoken.length).trimLeft();
                  }
                }
              }
            }
          }
        }
        if (text.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'text': text,
            'meta': '',
            'type': 'message'
          });
        }
      } else if (kind == 'tool_call') {
        final tool = (e['tool_name'] as String?) ?? '';
        if (tool == 'speak' ||
            tool == 'ambient_speak' ||
            tool.endsWith('__speak')) {
          final args = e['arguments'];
          final spoken = args is Map ? '${args['text'] ?? ''}'.trim() : '';
          if (spoken.isNotEmpty) {
            messages.add({
              'role': 'assistant',
              'text': spoken,
              'meta': 'Said aloud',
              'type': 'message',
            });
          }
        } else if (tool.isNotEmpty && !_notchHiddenTools.contains(tool)) {
          final step =
              ToolStep(tool: tool, args: e['arguments'], result: e['result']);
          messages.add({
            'role': 'activity',
            'text': toolSentence(step),
            'meta': '',
            'type': 'activity',
            'live': step.running,
          });
        }
      } else if (kind == 'artifact_presented') {
        final title = '${e['title'] ?? 'Artifact'}';
        messages.add({
          'role': 'artifact',
          'text': title,
          'meta': '',
          'type': 'artifact',
          'title': title,
          'id': '${e['id'] ?? ''}',
          'url': '${e['url'] ?? ''}',
        });
      } else if (kind == 'file_presented') {
        final path = '${e['path'] ?? ''}';
        if (_imageExt.hasMatch(path)) {
          messages.add({
            'role': 'image',
            'text': '${e['caption'] ?? path}',
            'meta': '',
            'type': 'image',
            'path': path,
          });
        }
      }
    }
    if (_liveStreamText.trim().isNotEmpty && state.status == 'running') {
      messages.add({
        'role': 'assistant',
        'text': _liveStreamText.trim(),
        'meta': '',
        'type': 'message'
      });
    }
    final waiting = state.status == 'waiting_for_input';
    final approval = waiting && state.pendingQuestion == null
        ? state.events.lastWhere((e) => e['kind'] == 'approval_request',
            orElse: () => const {})
        : const <String, dynamic>{};
    final tail = finishNotchItems(
      messages,
      running: state.status == 'running',
      lanes: [
        for (final lane in state.lanes)
          if (lane.status == 'running')
            {
              'title': lane.title,
              'state': lane.status,
              'activity': lane.activity ?? '',
              'id': lane.id
            }
      ],
      pendingQuestion: waiting ? state.pendingQuestion : null,
      approval: approval.isEmpty ? null : approval,
    );
    _pushConversationUpdate(
      title: _activeTitle,
      status: state.status,
      messages: tail,
    );
  }

  static Future<void> _sendNotchAction(String action, String text) async {
    if (action == 'openArtifact' || action == 'openImage') {
      await _channel.invokeMethod<void>('openInApp', {
        'url': (_activeClient ?? _defaultClient)?.baseUrl ?? '',
        'session': _activeSessionId ?? 'mission-control',
        'title': _activeTitle,
      });
      return;
    }
    final QuickAction quickAction = switch (action) {
      'answer' =>
        QuickAnswer(notchAnswerText(_activeState?.pendingQuestion, text)),
      'approve' => const QuickApprove(),
      'deny' => const QuickDeny(),
      _ => QuickReply(text),
    };
    final client = _activeClient ?? _defaultClient;
    final session = _activeSessionId ?? 'mission-control';
    if (client != null) {
      await quickSend(client: client, session: session, action: quickAction);
    } else {
      await quickSendForPayload({'session': session}, quickAction);
    }
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

    final ch =
        _activeSessionId == 'mission-control' ? _mcSocket : _activeSocket;
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
    required List<Map<String, dynamic>> messages,
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
    final channel = notchChannel(payload, title);
    final head = title.trim();
    if (channel != head && head.isNotEmpty && head != 'Snippet') {
      subtitle = subtitle.trim().isEmpty ? head : '$head · $subtitle';
    }
    title = channel;
    final dedupeKey = '$title|$subtitle|$kind';
    if (dedupeKey == _lastNotifiedKey) return;
    _lastNotifiedKey = dedupeKey;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_lastNotifiedKey == dedupeKey) _lastNotifiedKey = '';
    });
    NotchHome.remember(
        title: title, subtitle: subtitle, kind: kind, payload: payload);
    _channel.invokeMethod<void>('showNotification', <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'kind': kind,
      'payload': jsonEncode(payload),
    }).catchError((Object _) {});
  }
}

const _notchHiddenTools = {
  'ask_user',
  'present_file',
  'update_plan',
  'set_session_title'
};
final _imageExt = RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false);

/// Shapes the ordered transcript rows for the notch: activity only for the
/// current turn (last two finished steps, a "+N steps" line, the live step),
/// a 40-row cap, running lanes, then the pending question or approval last.
List<Map<String, dynamic>> finishNotchItems(
  List<Map<String, dynamic>> ordered, {
  bool running = false,
  List<Map<String, String>> lanes = const [],
  Map<String, dynamic>? pendingQuestion,
  Map<String, dynamic>? approval,
}) {
  final lastUser = ordered.lastIndexWhere((m) => m['role'] == 'user');
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < ordered.length; i++) {
    final m = ordered[i];
    if (m['type'] == 'activity' && i < lastUser) continue;
    out.add(Map<String, dynamic>.of(m));
  }
  final steps = [
    for (var i = 0; i < out.length; i++)
      if (out[i]['type'] == 'activity') i
  ];
  for (final i in steps) {
    out[i]['live'] = false;
  }
  if (running && steps.isNotEmpty) {
    final last = ordered.lastWhere((m) => m['type'] == 'activity');
    if (last['live'] == true) out[steps.last]['live'] = true;
  }
  final finished = steps.where((i) => out[i]['live'] != true).toList();
  if (finished.length > 2) {
    final drop = finished.sublist(0, finished.length - 2).toSet();
    final summaryAt = drop.first;
    out[summaryAt] = {
      'role': 'activity',
      'text': '+${drop.length} steps',
      'meta': '',
      'type': 'activity',
      'state': 'summary',
    };
    drop.remove(summaryAt);
    for (final i in drop.toList()..sort((a, b) => b - a)) {
      out.removeAt(i);
    }
  }
  final capped = out.length > 40 ? out.sublist(out.length - 40) : out;
  for (final lane in lanes) {
    capped.add({
      'role': 'lane',
      'text':
          lane['activity']?.isNotEmpty == true ? lane['activity'] : 'Working',
      'meta': '',
      'type': 'lane',
      'title': lane['title'] ?? '',
      'state': lane['state'] ?? '',
      'id': lane['id'] ?? '',
    });
  }
  final questions = pendingQuestion?['questions'];
  if (questions is List && questions.length > 1) {
    capped.add({
      'role': 'question',
      'text':
          '${questions.length} questions are waiting. Open the app to answer them.',
      'meta': '',
      'type': 'question',
      'id': '',
      'choices': <String>[],
      'answerKind': 'free_text',
    });
  } else if (questions is List &&
      questions.isNotEmpty &&
      questions.first is Map) {
    final q = questions.first as Map;
    final ak = q['answer_kind'] is Map ? q['answer_kind'] as Map : const {};
    final kind = '${ak['kind'] ?? 'free_text'}';
    final choices = switch (kind) {
      'yes_no' => ['Yes', 'No'],
      'confirm' => [
          '${ak['confirm_label'] ?? 'Confirm'}',
          '${ak['cancel_label'] ?? 'Cancel'}'
        ],
      'single_choice' || 'multi_choice' => [
          for (final c in (ak['choices'] as List? ?? const []).whereType<Map>())
            '${c['label'] ?? c['value'] ?? ''}'
        ],
      _ => <String>[],
    };
    capped.add({
      'role': 'question',
      'text': '${q['text'] ?? ''}',
      'meta': questions.length > 1 ? '1 of ${questions.length}' : '',
      'type': 'question',
      'id': '${q['id'] ?? ''}',
      'choices': choices,
      'answerKind': kind == 'multi_choice' ? 'multi' : kind,
    });
  } else if (approval != null) {
    capped.add({
      'role': 'approval',
      'text':
          '${approval['summary'] ?? approval['text'] ?? approval['tool_name'] ?? 'Approval required'}',
      'meta': '',
      'type': 'approval',
      'id': '${approval['id'] ?? ''}',
    });
  }
  return capped;
}

/// Matches the session screen's answer format for a single pending question.
String notchAnswerText(Map<String, dynamic>? pendingQuestion, String answer) {
  final questions = pendingQuestion?['questions'];
  if (questions is List && questions.length == 1 && questions.first is Map) {
    return '${(questions.first as Map)['text']}\n→ $answer';
  }
  return answer;
}

/// Where a notch notification came from, shown in the left wing.
String notchChannel(Map<String, dynamic> payload, String title) {
  final destination = (payload['destination'] as Map?) ?? const {};
  final session =
      (payload['session'] ?? destination['session'] ?? '').toString();
  final kind = (payload['kind'] ?? '').toString();
  if (session == 'mission-control' ||
      destination['type'] == 'task' ||
      kind == 'ping') {
    return 'Mission Control';
  }
  if (kind == 'direct_message.sent') return 'Message';
  final head = title.trim();
  if (head.isNotEmpty && head != 'Snippet') return head;
  final workspace = (payload['workspace'] ?? '').toString().trim();
  if (workspace.isNotEmpty) {
    final parts = workspace.split('/').where((p) => p.isNotEmpty);
    if (parts.isNotEmpty) return parts.last;
  }
  return 'Snippet';
}
