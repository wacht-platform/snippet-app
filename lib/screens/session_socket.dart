part of 'session.dart';

extension _SessionScreenSocketExt on _SessionScreenState {
  void _connect() {
    if (_closed || _parked) return;
    _reconnectTimer?.cancel();
    _bannerTimer
        ?.cancel(); // suppress "Reconnecting…" if we reconnect before 60s
    // Fully detach the old socket first: cancel its subscription so its onDone
    // can't fire _scheduleReconnect against the NEW channel — that cascade
    // orphaned healthy sockets and double-applied every delta.
    _sub?.cancel();
    _sub = null;
    _connectionWatchdog?.cancel();
    _channel?.sink.close();
    if (mounted) _setState(() => _connError = null);
    _freshConn = true;
    _decodeQueue = null;
    final ch = widget.client.attach(widget.sessionId);
    _channel = ch;
    _connectionWatchdog?.cancel();
    _connectionWatchdog = Timer(Duration(seconds: _state == null ? 4 : 12), () {
      if (!_closed && identical(ch, _channel)) {
        _resync(ch);
      }
    });
    _sub = ch.stream.listen(
      (msg) {
        if (!identical(ch, _channel)) return; // stale socket — ignore
        _connectionWatchdog?.cancel();
        _connectionWatchdog = null;
        // Any frame means a healthy socket — reset backoff + clear the banner.
        if (_reconnectAttempt != 0 || _connError != null) {
          _reconnectAttempt = 0;
          if (mounted) _setState(() => _connError = null);
        }
        // Flush sends queued while the socket was down, in order.
        if (_outbox.isNotEmpty) {
          for (final p in _outbox) {
            ch.sink.add(p);
          }
          _outbox.clear();
        }
        try {
          // web_socket_channel can deliver either a String or binary bytes for
          // the same text frame depending on platform/proxy. Casting only to
          // String throws, the catch resyncs forever, and the canvas stays empty.
          final raw = switch (msg) {
            final String s => s,
            final Uint8List b => utf8.decode(b, allowMalformed: true),
            final List<int> b => utf8.decode(b, allowMalformed: true),
            _ => '',
          };
          if (raw.isEmpty) return;
          if (_decodeQueue == null && raw.length < _kInlineDecodeLimit) {
            _applyFrame(ch, jsonDecode(raw));
            return;
          }
          late final Future<void> queued;
          queued = (_decodeQueue ?? Future<void>.value()).then((_) async {
            final decoded = raw.length < _kInlineDecodeLimit
                ? jsonDecode(raw)
                : await compute(_decodeFrame, raw);
            if (identical(ch, _channel)) _applyFrame(ch, decoded);
          }).catchError((Object _) {
            if (identical(ch, _channel)) _resync(ch);
          }).whenComplete(() {
            if (identical(_decodeQueue, queued)) _decodeQueue = null;
          });
          _decodeQueue = queued;
        } catch (_) {
          _resync(ch);
        }
      },
      onError: (_) => _scheduleReconnect(ch),
      onDone: () => _scheduleReconnect(ch),
      cancelOnError: true,
    );
  }

  void _applyFrame(WebSocketChannel ch, Object? decoded) {
    try {
      if (decoded is! Map) return;
      final j = decoded.cast<String, dynamic>();
      if (!mounted) return;
      // Only snapshot/delta carry HarnessState. Stream frames are live
      // token/thinking updates with no events — applying them via
      // fromJson wiped the transcript to empty until the next real state
      // frame (often only after a TUI-side persist).
      final wire = j['wire'] as String? ?? 'snapshot';
      if (wire == 'history') {
        final rawEvents = j['events'];
        final older = rawEvents is List
            ? rawEvents
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
            : const <Map<String, dynamic>>[];
        if (older.isNotEmpty) {
          _setState(() {
            _state = _state?.prependEvents(older);
            _transcriptStart = (j['start'] as num?)?.toInt() ?? 0;
            _transcriptDirty = true;
          });
        } else {
          _transcriptStart = 0;
        }
        _setState(() => _loadingOlderTranscript = false);
        return;
      }
      if (wire == 'event') {
        final index = (j['index'] as num?)?.toInt();
        final event = j['event'];
        final cur = _state;
        if (index != null && event is Map && cur != null) {
          final rel = index - _transcriptStart;
          if (rel >= 0 && rel < cur.events.length) {
            _setState(() {
              _state = cur.replaceEvent(rel, event.cast<String, dynamic>());
              _transcriptDirty = true;
            });
          }
        }
        return;
      }
      if (wire == 'term') {
        _applyTermFrame(j);
        return;
      }
      if (wire == 'stream') {
        final text = (j['text'] as String?) ?? '';
        final thinking = (j['thinking'] as String?) ?? '';
        final visible = j['text_visible'] == true;
        if (!mounted) return;
        // Ignore non-empty stream while the run is idle/stopped — a late
        // frame after commit would re-show thinking/answer next to the
        // durable AssistantText (duplicate bubble + sticky reasoning).
        final status = _state?.status;
        final liveOk = status == null ||
            status == 'running' ||
            status == 'waiting_for_input' ||
            (text.isEmpty && thinking.isEmpty);
        if (!liveOk) {
          if (_liveText.isNotEmpty ||
              _liveThinking.isNotEmpty ||
              _liveTextVisible) {
            _setState(() {
              _liveText = '';
              _liveThinking = '';
              _liveTextVisible = false;
            });
          }
          return;
        }
        // Throttle stream frames: store latest payload and flush at most
        // every 50ms to avoid rebuilding the full widget tree on every token.
        _pendingLiveText = text;
        _pendingLiveThinking = thinking;
        _pendingLiveTextVisible = visible;
        if (_streamFlushTimer?.isActive ?? false) return;
        _streamFlushTimer =
            Timer(const Duration(milliseconds: 50), () => _flushStreamFrame());
        return;
      }
      if (wire != 'snapshot' && wire != 'delta') return;
      final cur = _state;
      // Reject duplicate/out-of-order attach frames before applying them.
      // Replayed equal revisions are harmless and should not churn a healthy
      // socket; only a non-consecutive newer revision requires resync.
      final revision = j['revision'];
      if (revision is int) {
        if (wire == 'snapshot') {
          _lastAttachRevision = revision;
        } else if (_lastAttachRevision != 0 &&
            revision == _lastAttachRevision) {
          return;
        } else if (_lastAttachRevision != 0 &&
            revision != _lastAttachRevision + 1) {
          _resync(ch);
          return;
        } else {
          _lastAttachRevision = revision;
        }
      }
      final next = (wire == 'delta' && cur != null)
          ? cur.applyDelta(j)
          : HarnessState.fromJson(j);
      // Drift check: our event log must line up with the server's count — a
      // mismatch (dropped/bad frame) resyncs via reconnect, since a fresh
      // socket's first frame is always a full snapshot.
      final ec = j['event_count'];
      if (wire == 'delta' && ec is int && next.events.length != ec) {
        _resync(ch);
        return;
      }
      // A reversed transcript is anchored at offset 0 (latest). No initial
      // jump is needed; preserve whether the user has scrolled into history.
      final follow = _stickToBottom;
      _syncOptimisticQueue(next.queuedInputs);
      _queueHidden.removeWhere((id) =>
          !next.queuedInputs.any((item) => item.id == id) &&
          !_optimisticQueued.any((item) => item.id == id));
      // Held messages live on the daemon (`queued_inputs`) and flush there
      // when the run lands on idle. Clients only display / enqueue / cancel.
      // A pending approval/answer is acknowledged the moment the run leaves
      // waiting_for_input — clear it so its watchdog can't fire a needless
      // resync (and so a resent decision isn't double-applied).
      if (next.status != 'waiting_for_input' && _pendingDecision != null) {
        _pendingDecision = null;
        _decisionTimer?.cancel();
      }
      // Retire optimistic bubbles once the daemon has echoed them:
      // 1) FIFO by echo-count delta (prev→next) when we have prior state
      // 2) by per-item baseline (covers missed delta / same-count snapshot)
      // 3) by normalized text match against the authoritative event log
      //    (every frame — not only snapshots — so stuck faint bubbles clear)
      final prevEchoes = cur == null ? null : _userEchoCount(cur.events);
      final nextEchoes = _userEchoCount(next.events);
      if (prevEchoes != null) {
        var retired = (nextEchoes - prevEchoes).clamp(0, _pending.length);
        while (retired-- > 0) {
          _popPendingFront();
        }
      } else if (wire != 'delta') {
        // first-ever snapshot: nothing optimistic predates it
        _clearPendingAll();
      }
      if (_pending.isNotEmpty) {
        _retirePendingByBaseline(nextEchoes);
        _retirePendingAlreadyEchoed(next.events);
      }
      // First full snapshot after a (re)connect is authoritative: anything
      // still in _pending was never received by the server — resend it with
      // the same nonce so the server deduplicates if it DID land.
      if (_freshConn && wire != 'delta') {
        _freshConn = false;
        for (var i = 0; i < _pending.length; i++) {
          final m = _pending[i];
          final nonce = i < _pendingNonce.length ? _pendingNonce[i] : null;
          final msg = nonce != null
              ? {'kind': 'user_message', 'value': m, 'nonce': nonce}
              : {'kind': 'user_message', 'value': m};
          try {
            ch.sink.add(jsonEncode(msg));
          } catch (_) {
            _outbox.add(jsonEncode(msg));
          }
        }
        // A decision still pending while the snapshot STILL shows the run
        // waiting means it never landed — resend it. (If it had landed, the
        // status/clear above already dropped it, so no double-approve.)
        if (_pendingDecision != null && next.status == 'waiting_for_input') {
          final payload = jsonEncode(_pendingDecision);
          try {
            ch.sink.add(payload);
          } catch (_) {
            _outbox.add(payload);
          }
        }
      }
      // Only rebuild the transcript widget list when events actually
      // changed — status-only deltas waste a full transcript rebuild.
      final eventsChanged = cur == null ||
          next.events.length != cur.events.length ||
          (next.events.isNotEmpty &&
              cur.events.isNotEmpty &&
              next.events.last != cur.events.last);
      // The open question moves between the answer bar and the transcript.
      final questionFlipped = cur == null ||
          (next.status == 'waiting_for_input' &&
                  next.pendingQuestion != null) !=
              (cur.status == 'waiting_for_input' &&
                  cur.pendingQuestion != null);
      if (eventsChanged || questionFlipped) _transcriptDirty = true;
      if (wire == 'snapshot') {
        final offset = (j['event_offset'] as num?)?.toInt();
        _transcriptStart = offset ?? 0;
      }
      _setState(() {
        _state = next;
        if (!_isMissionControl) {
          final nextTitle = next.title ?? widget.title;
          if (nextTitle != _title && nextTitle.isNotEmpty) {
            _title = nextTitle;
            widget.onTitle?.call(nextTitle);
          }
        }
        // Snapshot/delta commit durable events; drop the live answer so it
        // doesn't double-render against AssistantText once it lands.
        if (wire == 'snapshot' || wire == 'delta') {
          _liveText = '';
          _liveTextVisible = false;
          // Thought process is live-only until the first tool/action of
          // this turn. After that the UI should show the action, not
          // leftover reasoning.
          if (next.status != 'running' || _turnHasVisibleAction(next.events)) {
            _liveThinking = '';
            _pendingLiveThinking = '';
            _streamFlushTimer?.cancel();
            _streamFlushTimer = null;
          }
        }
      });
      widget.onMacStatus?.call(next, next.status == 'running');
      if (wire == 'delta') {
        widget.client.deviceEvents.addAttachedToolResults(
          j,
          session: widget.sessionId,
          workspace: next.workspace,
        );
      }
      widget.onMacControls
          ?.call(() => _send({'kind': 'interrupt'}), _performMacAction);
      // Re-arm (or cancel) the ack watchdog against the new _pending state.
      _armAckWatchdog();
      if (follow) _scheduleBottom();
    } catch (_) {
      // A frame we couldn't apply would silently corrupt the transcript —
      // resync instead of swallowing it.
      _resync(ch);
    }
  }

  // Tear down this socket and rejoin — the fresh connection opens with a full
  // snapshot, which reconciles any local drift.
  void _resync(WebSocketChannel ch) {
    if (!identical(ch, _channel)) return;
    ch.sink.close();
    _scheduleReconnect(ch);
  }

  // Reconnect with exponential backoff (1,2,4,8,15,30s). Deduped so onError+onDone
  // don't double-schedule; reset to 0 on any healthy frame or app-resume. Only the
  // CURRENT channel may schedule — a detached socket's late onDone is ignored.
  void _scheduleReconnect(WebSocketChannel ch) {
    if (_closed || _parked) return;
    if (!identical(ch, _channel)) return; // stale socket
    if (_reconnectTimer?.isActive ?? false) return; // already pending
    _channel = null;
    const steps = [1, 2, 4, 8, 15, 30];
    final delay = steps[_reconnectAttempt.clamp(0, steps.length - 1)];
    _reconnectAttempt++;
    // Delay the banner briefly so transient handoffs do not flash a warning.
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_closed && _channel == null) {
        _setState(() => _connError = 'Reconnecting…');
      }
    });
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_closed) _connect();
    });
  }

  // Stream frames may be a full buffer or a tailed snippet (`…\\n\\n` + last
  // N chars). Never shrink what we already show while the run is live.
  String _mergeLiveThinking(String prev, String next) {
    var incoming = next;
    if (incoming.startsWith('…')) {
      incoming = incoming.replaceFirst(RegExp(r'^…+\s*'), '');
    }
    if (incoming.isEmpty) return prev;
    if (prev.isEmpty) return incoming;
    if (incoming == prev) return prev;
    if (incoming.startsWith(prev)) return incoming;
    if (prev.startsWith(incoming)) return prev;
    if (incoming.contains(prev) && incoming.length >= prev.length) {
      return incoming;
    }
    if (prev.endsWith(incoming) || prev.contains(incoming)) return prev;
    // Overlapping tail/head (tailed snapshots) — grow instead of mash.
    final maxOverlap =
        prev.length < incoming.length ? prev.length : incoming.length;
    for (var n = maxOverlap; n >= 24; n--) {
      if (prev.endsWith(incoming.substring(0, n))) {
        return prev + incoming.substring(n);
      }
    }
    // New thought signature: replace the previous snapshot instead of appending.
    return incoming;
  }

  String? _latestCompactionDetail(List<Map<String, dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e['type'] != 'system_decision') continue;
      final step = e['step']?.toString() ?? '';
      if (step == 'history_compaction_pass' ||
          step == 'history_compaction_skipped') {
        final r = e['reasoning']?.toString().trim() ?? '';
        return r.isEmpty ? null : r;
      }
    }
    return null;
  }

  // Throttled stream frame flush — called by the 50ms timer.
  void _flushStreamFrame() {
    if (_closed || !mounted) return;
    final hideThought = _turnHasVisibleAction(_state?.events ?? const []);
    final text = _pendingLiveText;
    final thinking = hideThought
        ? ''
        : _mergeLiveThinking(_liveThinking, _pendingLiveThinking);
    final visible = _pendingLiveTextVisible;
    _liveFrame.value = _LiveFrame(
      text: text,
      thinking: thinking,
      visible: visible,
    );
    if (_stickToBottom && (text.isNotEmpty || thinking.isNotEmpty)) {
      _scheduleBottom();
    }
  }
}

const int _kInlineDecodeLimit = 64 * 1024;

Object? _decodeFrame(String raw) => jsonDecode(raw);
