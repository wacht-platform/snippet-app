part of 'session.dart';

extension _SessionScreenComposerExt on _SessionScreenState {
  void _send(Map<String, dynamic> m, {bool tracked = false}) {
    final payload = jsonEncode(m);
    final ch = _channel;
    if (ch == null) {
      if (!tracked) _outbox.add(payload); // untracked messages use outbox
      return;
    }
    try {
      ch.sink.add(payload);
    } catch (_) {
      if (!tracked) _outbox.add(payload);
      _scheduleReconnect(ch);
    }
  }

  Future<void> _sendMessage() async {
    if (_input.text.trim().isNotEmpty || _attachments.isNotEmpty) {
      HapticFeedback.lightImpact();
    }
    // The composer can be triggered by both the send button and keyboard submit;
    // serialize the entire async path so a rapid double tap cannot create two
    // distinct nonces and two server turns.
    if (_sendingMessage) return;
    _sendingMessage = true;
    try {
      await _sendMessageOnce();
    } finally {
      _sendingMessage = false;
    }
  }

  Future<void> _sendMessageOnce() async {
    // Audio can be sent directly from the composer: stop the live take, upload
    // it through the normal attachment path, then continue with the same send.
    if (_sendingAudio) return;
    if (_isRecording || _recordingPath != null) {
      _sendingAudio = true;
      if (mounted) _setState(() {});
      try {
        if (_isRecording) await _stopRecording();
        if (_recordingPath != null && !await _confirmRecording()) return;
      } finally {
        _sendingAudio = false;
        if (mounted) _setState(() {});
      }
    }
    // An upload still in flight would be silently DROPPED (only remotePath'd
    // attachments ship, then the list is cleared). The send button disables via
    // canSend, but keyboard submit bypassed it — guard here, the single choke point.
    if (_anyUploading) return;
    final t = _input.text.trim();
    final ready = _attachments.where((a) => a.ready).toList();
    if (t.isEmpty && ready.isEmpty) return;

    // A selected recipient turns this into a DIRECT MESSAGE to that agent: it
    // goes to the agent's own inbox and never becomes a turn in this session, so
    // the conversation and the work stay separate.
    final recipient = _recipientAgentId;
    if (recipient != null && recipient.isNotEmpty) {
      _sendDirectMessage(recipient, t, ready);
      return;
    }

    final running = _state?.status == 'running';
    // Reference each upload by its exact path so the agent reads it this turn.
    final markers = ready.map((a) => a.marker).join('\n');
    final msg = markers.isEmpty ? t : (t.isEmpty ? markers : '$t\n\n$markers');
    final nonce = _nextNonce();
    _setState(() {
      if (running) {
        // Hold on the daemon so TUI/app/desktop all see the same queue.
        final item = QueuedInput(id: _nextNonce(), text: msg);
        _optimisticQueued.add(item);
        _send({'kind': 'queue', 'value': item, 'nonce': nonce});
      } else {
        _send({'kind': 'user_message', 'value': msg, 'nonce': nonce},
            tracked: true);
        _trackPending(msg, nonce); // faint bubble until daemon echoes it
      }
      _attachments.clear();
    });
    if (!running) widget.onMacStatus?.call(_state, true);
    _input.clear();
    _armAckWatchdog(); // recover if this send silently dies on a dead socket
    // Sending is an explicit action — re-pin and jump to the bottom.
    _stickToBottom = true;
    _scheduleBottom();
  }

  /// Send the composer's text to a selected agent as a direct message.
  ///
  /// Deliberately separate from the session send path: a direct message goes to
  /// the agent's own inbox and must NOT become a turn in this session's
  /// transcript, so nothing here touches the socket. The recipient is cleared
  /// afterwards because the message will not appear in this transcript — leaving
  /// the composer targeted would invite sending the next thought to the wrong
  /// place.
  Future<void> _sendDirectMessage(
    String agentId,
    String text,
    List<_Attachment> ready,
  ) async {
    if (text.isEmpty && ready.isEmpty) return;
    final markers = ready.map((a) => a.marker).join('\n');
    final body =
        markers.isEmpty ? text : (text.isEmpty ? markers : '$text\n\n$markers');
    final name = _recipientAgentName ?? agentId;
    _setState(() {
      _recipientAgentId = null;
      _recipientAgentName = null;
      _attachments.clear();
    });
    _input.clear();
    try {
      await widget.client.sendAgentMessage(
        toAgentId: agentId,
        body: body,
        idempotencyKey: _nextNonce(),
        // Ask FROM this session, so the agent's reply comes back here rather
        // than only into its own inbox. Without it the exchange is one-way from
        // the session's point of view: nothing here records what was asked.
        originSession: widget.sessionId,
      );
      // No optimistic row here: the daemon records the sent message as an
      // `agent_message` event in THIS session, which now renders in the
      // transcript. A local row on top of that would show the same send twice.
      _toast('Sent to $name');
    } catch (e) {
      // Put the text back: a failed send must not cost the user what they wrote.
      _input.text = body;
      _toast('$e');
    }
  }

  bool _isImageName(String n) {
    final l = n.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif'
    ].any(l.endsWith);
  }

  // `+` tapped: desktop opens a file picker directly; mobile shows a small
  Future<void> _confirmCompact() async {
    if (_state?.compacting == true) {
      _toast('Already compacting');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Compact history?',
      body:
          'Older conversation history will be summarized into a context table. Recent messages stay. This cannot be undone.',
      confirmLabel: 'Compact',
      danger: false,
    );
    if (!ok || !mounted) return;
    _send({'kind': 'compact'});
    _toast('Compacting history');
  }

  List<QueuedInput> get _heldQueue {
    final live = _state?.queuedInputs ?? const <QueuedInput>[];
    final extra = <QueuedInput>[];
    for (final item in _optimisticQueued) {
      if (!live.any((liveItem) => liveItem.id == item.id)) extra.add(item);
    }
    final all = extra.isEmpty ? live : [...live, ...extra];
    return _queueHidden.isEmpty
        ? all
        : all.where((item) => !_queueHidden.contains(item.id)).toList();
  }

  void _syncOptimisticQueue(List<QueuedInput> live) {
    _optimisticQueued
        .removeWhere((item) => live.any((liveItem) => liveItem.id == item.id));
  }

  void _hideQueuedAt(int visible) {
    final held = _heldQueue;
    if (visible >= 0 && visible < held.length) {
      _queueHidden.add(held[visible].id);
    }
  }

  void _cancelQueuedAt(int visible) {
    if (visible < 0 || visible >= _heldQueue.length) return;
    final item = _heldQueue[visible];
    _setState(() {
      _hideQueuedAt(visible);
      if (_heldQueue.length <= 1) {
        _hoveredQueuedIndex = null;
      }
    });
    _send({'kind': 'unqueue', 'value': item.id, 'nonce': _nextNonce()});
  }

  void _editQueuedAt(int visible) {
    if (visible < 0 || visible >= _heldQueue.length) return;
    final item = _heldQueue[visible];
    final cleanText = _queuedText(item.text);
    _input.text = cleanText;
    _input.selection = TextSelection.collapsed(offset: cleanText.length);
    _cancelQueuedAt(visible);
    _inputFocus.requestFocus();
  }

  void _steerAllQueued() {
    final items = List<QueuedInput>.from(_heldQueue);
    for (final item in items) {
      final nonce = _nextNonce();
      _setState(() {
        _queueHidden.add(item.id);
        _optimisticQueued.removeWhere((queued) => queued.id == item.id);
        _trackPending(item.text, nonce);
      });
      _send({'kind': 'steer_queued', 'value': item.id, 'nonce': nonce});
    }
    if (items.isNotEmpty) _armAckWatchdog();
  }

  void _cancelAllQueued() {
    _setState(() {
      _queueHidden.addAll(_heldQueue.map((item) => item.id));
      _hoveredQueuedIndex = null;
    });
    _send({'kind': 'drop_queued'});
  }

  void _steerQueuedAt(int visible) {
    final held = _heldQueue;
    if (visible < 0 || visible >= held.length) return;
    final item = held[visible];
    final nonce = _nextNonce();
    _setState(() {
      _queueHidden.add(item.id);
      _optimisticQueued.removeWhere((queued) => queued.id == item.id);
      _trackPending(item.text, nonce);
      if (_heldQueue.length <= 1) {
        _hoveredQueuedIndex = null;
      }
    });
    _send({'kind': 'steer_queued', 'value': item.id, 'nonce': nonce});
    _armAckWatchdog();
  }

  Widget _queuedCard() {
    final queue = _heldQueue;
    if (queue.isEmpty) return const SizedBox.shrink();
    final count = queue.length;

    Widget textAction(String label, VoidCallback onTap, Color color) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: S.s6, vertical: S.s4),
            child: Text(label, style: TS.label(color)),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: S.s6),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.s12, S.s6, S.s6, S.s2),
            child: Row(children: [
              AppIcon('clock', size: 12, color: AppColors.fg3),
              const SizedBox(width: S.s6),
              Text('Queued', style: TS.meta(AppColors.fg3)),
              const SizedBox(width: S.s4),
              CountBadge(count),
              const Spacer(),
              if (count > 1) ...[
                textAction('Clear', _cancelAllQueued, AppColors.fg3),
                textAction('Send all', _steerAllQueued, AppColors.accent),
              ],
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: S.s4),
              itemCount: count,
              separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 1,
                  indent: S.s12,
                  endIndent: S.s12,
                  color: AppColors.line),
              itemBuilder: (_, qi) => _queuedItemRow(qi, queue[qi]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queuedItemRow(int qi, QueuedInput item) {
    final isHovered = _hoveredQueuedIndex == qi;
    final showActions = kMobile || isHovered;
    final text = _queuedText(item.text);
    final counts = _queuedAttachCounts(item.text);

    Widget iconAction(String icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMobile ? 34 : 26,
              child:
                  Center(child: AppIcon(icon, size: 14, color: AppColors.fg3)),
            ),
          ),
        );

    final sendNow = Tooltip(
      message: 'Send now',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _steerQueuedAt(qi),
        child: SizedBox.square(
          dimension: kMobile ? 34 : 26,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.accentFill,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon('arrow-up', size: 13, color: AppColors.accentFg),
            ),
          ),
        ),
      ),
    );

    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      iconAction('edit', 'Edit', () => _editQueuedAt(qi)),
      iconAction('x', 'Remove', () => _cancelQueuedAt(qi)),
      sendNow,
    ]);

    return MouseRegion(
      onEnter: (_) {
        if (_hoveredQueuedIndex != qi) {
          _setState(() => _hoveredQueuedIndex = qi);
        }
      },
      onExit: (_) {
        if (_hoveredQueuedIndex == qi) {
          _setState(() => _hoveredQueuedIndex = null);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.s12, S.s4, S.s4, S.s4),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text.isEmpty ? 'Attachment' : text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TS.ui(text.isEmpty ? AppColors.fg3 : AppColors.fg1),
                ),
                if (counts.$1 + counts.$2 + counts.$3 > 0) ...[
                  const SizedBox(height: S.s4),
                  AttachmentPill(
                    audio: counts.$1,
                    images: counts.$2,
                    files: counts.$3,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: S.s4),
          AnimatedOpacity(
            opacity: showActions ? 1 : 0,
            duration: Motion.quick,
            child: IgnorePointer(ignoring: !showActions, child: actions),
          ),
        ]),
      ),
    );
  }

  // Clean text for a held/pending message (markers stripped). Attachments
  // surface as AttachmentPill beside the text — same as a real Bubble.
  String _queuedText(String m) => hideAttachmentMarkers(m);

  (int audio, int images, int files) _queuedAttachCounts(String m) {
    final matches =
        RegExp(r'\[attached (image|file) —([^\]]*)\]').allMatches(m);
    final audio =
        matches.where((x) => isAudioAttachmentPath(x.group(2) ?? '')).length;
    final images = matches.where((x) => x.group(1) == 'image').length;
    return (audio, images, matches.length - images - audio);
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  bool get _canSend =>
      (_isRecording ||
          _recordingPath != null ||
          _input.text.trim().isNotEmpty ||
          _attachments.any((a) => a.ready)) &&
      !_anyUploading &&
      !_sendingAudio;

  Future<void> _ingestDroppedFiles(DropDoneDetails details) async {
    if (!kMacOS || !widget.acceptDrops) return;
    _setState(() => _draggingFiles = false);
    final files = details.files.whereType<DropItemFile>().map((item) {
      final bookmark = item.extraAppleBookmark;
      return (
        name: item.name,
        localPath: item.path,
        readBytes: () async {
          var accessed = false;
          try {
            if (bookmark != null && bookmark.isNotEmpty) {
              accessed = await DesktopDrop.instance
                  .startAccessingSecurityScopedResource(bookmark: bookmark);
            }
            return await item.readAsBytes();
          } finally {
            if (accessed) {
              await DesktopDrop.instance
                  .stopAccessingSecurityScopedResource(bookmark: bookmark!);
            }
          }
        },
      );
    }).toList();
    await _ingest(files);
  }

  /// Approval mode as shown in the composer.
  ///
  /// The daemon models exactly two modes (`auto` / `manual`), so the pill names
  /// those rather than inventing a third the backend cannot honor.
  String get _approvalLabel =>
      (_state?.approvalMode ?? 'auto') == 'manual' ? 'Ask' : 'Auto';

  /// Context still free, as a whole percent of the model's window. Null until
  /// the daemon has reported both a window size and a prompt size.
  int? get _contextLeftPct {
    final s = _state;
    if (s == null || s.contextWindow <= 0 || s.lastPromptTokens <= 0) {
      return null;
    }
    final used = s.lastPromptTokens / s.contextWindow;
    return (100 - used * 100).clamp(0, 100).round();
  }

  /// One composer footer control: icon + label + disclosure chevron.
  /// A composer chip. When [onClear] is set the chip is in a CHOSEN state: it
  /// shows the value, and the trailing affordance clears it instead of opening
  /// the picker — so a selected dispatch is dismissible without a second trip
  /// through the menu.
  Widget _composerChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool selected = false,
  }) =>
      Material(
        color: selected ? AppColors.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: kMobile ? 28 : 30,
            padding: EdgeInsets.fromLTRB(9, 0, onClear == null ? 8 : 4, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIcon(icon,
                    size: 13.5,
                    color: selected ? AppColors.accent : AppColors.fg3),
                const SizedBox(width: 6),
                Text(label,
                    style: sans(kMobile ? 12 : 13,
                        color: selected ? AppColors.accent : AppColors.fg3)),
                if (onClear != null)
                  IconBtn('x',
                      size: 22, iconSize: 12, tooltip: 'Clear', onTap: onClear)
                else ...[
                  const SizedBox(width: 5),
                  AppIcon('chevron-down',
                      size: 12,
                      color: selected ? AppColors.accent : AppColors.fg4),
                ],
              ],
            ),
          ),
        ),
      );

  /// Pick (or clear) the direct-message recipient for the composer.
  Future<void> _pickRecipient(BuildContext anchor) async {
    final current = _recipientAgentId;
    final picked = await pickAgentId(
      context,
      widget.client,
      title: 'Send to',
      // An agent already on this session is not offered again: it is reached by
      // messaging the session itself, so listing it twice would be ambiguous.
      exclude: _sessionAgentIds,
      currentAgentId: current,
      anchor: anchor,
      verticalAnchor: _composerCardKey.currentContext,
    );
    if (picked == null || !mounted) return;
    _setState(() {
      _recipientAgentId = picked.id;
      _recipientAgentName =
          picked.displayName.trim().isEmpty ? picked.id : picked.displayName;
    });
    // Pin it to the session so the composer shows WHO can be reached without
    // walking the directory again next time.
    _pinSessionAgent(picked.id);
    _toast('Sending to $_recipientAgentName');
  }

  void _clearRecipient() {
    _setState(() {
      _recipientAgentId = null;
      _recipientAgentName = null;
    });
    _toast('Back to this chat');
  }

  /// Record that `agentId` belongs to this session's roster.
  ///
  /// Session membership is tracked locally for now: choosing an agent here is
  /// what puts it on this session, and the set is what stops the picker
  /// offering the same agent twice.
  void _pinSessionAgent(String agentId) {
    if (agentId.isEmpty) return;
    _setState(() => _sessionAgentIds.add(agentId));
  }

  /// The composer's status line: where this session runs, and how much context
  /// is left. Sits under the card so the transcript keeps the full width.
  Widget _composerMeta(HarnessState? s) {
    final left = _contextLeftPct;
    final ws = s?.workspace ?? '';
    final name = ws.isEmpty ? '' : lastPathSegment(ws, ifEmpty: ws);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
      child: Row(children: [
        // ONE tight flex child absorbs the free space, pinning the trailing
        // readout to the card's right edge. A loose `Flexible` beside a
        // `Spacer` splits the free space and leaves the leftover AFTER the
        // readout, so it stops short of the edge instead of reaching it.
        Expanded(
          child: name.isEmpty
              ? const SizedBox.shrink()
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('folder', size: 11, color: AppColors.fg4),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.caption()),
                  ),
                ]),
        ),
        if (left != null) ...[
          const SizedBox(width: 8),
          // Changes as the session runs, so it needs tabular figures; and it is
          // information, not a placeholder, so `fg3` not `fg4`.
          Text('$left% context left',
              style: sans(11, tabular: true, color: AppColors.fg3)),
        ],
      ]),
    );
  }

  /// Approval picker, anchored under its composer chip.
  Future<void> _switchApproval([BuildContext? anchor]) async {
    final current = _state?.approvalMode ?? 'auto';
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor ?? context,
      verticalAnchor: _composerCardKey.currentContext,
      minWidth: 260,
      maxWidth: 320,
      items: [
        appMenuRow(
          value: 'auto',
          icon: 'zap',
          label: 'Auto',
          description: 'Run shell and file edits without asking',
          selected: current != 'manual',
        ),
        appMenuRow(
          value: 'manual',
          icon: 'shield',
          label: 'Ask',
          description: 'Pause for approval on each change',
          selected: current == 'manual',
        ),
      ],
    );
    if (picked == null || picked == current) return;
    _setApproval(picked == 'manual');
  }

  Widget _inputBar(bool running) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        // Inset from the pane on EVERY layout. Embedded used to be 0, which is
        // why the composer stuck to the sides of the shell.
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
            8,
            kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
            10 + (keyboard > 0 ? 8 : mq.padding.bottom)),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_heldQueue.isNotEmpty) _queuedCard(),
              if (_attachments.isNotEmpty) _attachmentBar(),
              if (kMobile && (_isRecording || _recordingPath != null))
                ValueListenableBuilder<int>(
                  valueListenable: _recorderTick,
                  builder: (_, __, ___) => _mobileRecorder(running),
                )
              else ...[
                if (_isRecording || _recordingPath != null)
                  ValueListenableBuilder<int>(
                    valueListenable: _recorderTick,
                    builder: (_, __, ___) => _recordingPanel(),
                  ),
                Container(
                  key: _composerCardKey,
                  decoration: BoxDecoration(
                    color: AppColors.raised,
                    borderRadius: BorderRadius.circular(18),
                    border: _draggingFiles
                        ? Border.all(color: AppColors.accent, width: 1.5)
                        : Border.all(color: AppColors.border),
                  ),
                  // The card owns the inset and the rows sit inside it, so there is
                  // no per-row vertical padding to keep in sync. Slightly taller
                  // than it is wide-padded, so the field reads as a writing area.
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_state?.goal?.ongoing == true) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(R.sm),
                            ),
                            child: Row(children: [
                              AppIcon('goal',
                                  size: 14, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_state!.goal!.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(12, color: AppColors.fg2)),
                              ),
                              Text(_state!.goal!.paused ? 'paused' : 'active',
                                  style: mono(10, color: AppColors.accent)),
                              const SizedBox(width: 5),
                              IconBtn('x',
                                  size: 26,
                                  iconSize: 13,
                                  tooltip: 'Cancel goal',
                                  onTap: _cancelGoal),
                            ]),
                          ),
                        ],
                        CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter):
                                () {
                              if (!kMobile && _canSend) _sendMessage();
                            },
                            const SingleActivator(LogicalKeyboardKey.enter,
                                meta: true): () {
                              if (_canSend) _sendMessage();
                            },
                            const SingleActivator(LogicalKeyboardKey.enter,
                                control: true): () {
                              if (_canSend) _sendMessage();
                            },
                          },
                          child: TextField(
                            controller: _input,
                            focusNode: _inputFocus,
                            // Two lines minimum: a single-line field read as a
                            // cramped search box, and it hid the fact that the
                            // composer accepts multi-line prose.
                            minLines: kMobile ? 1 : 2,
                            maxLines: 8,
                            cursorColor: AppColors.accent,
                            onSubmitted: (_) => _sendMessage(),
                            style: TS.body(AppColors.fg1),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              // The card supplies the inset; this only adds the gap
                              // between the text and the control row beneath it.
                              contentPadding:
                                  const EdgeInsets.fromLTRB(2, 2, 8, 10),
                              border: InputBorder.none,
                              hintText:
                                  kMobile ? 'Reply to Snippet' : 'Ask anything',
                              hintStyle: TS.body(AppColors.fg4),
                            ),
                          ),
                        ),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(R.sm),
                                child: InkWell(
                                  onTap: _onAttachTap,
                                  borderRadius: BorderRadius.circular(R.sm),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: AppIcon('plus',
                                        size: 18, color: AppColors.fg3),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // The chip group SCROLLS and the mic/send controls are
                              // pinned outside it. Three chips plus two buttons
                              // overflowed a narrow phone, which pushed Send off the
                              // card; a scrolling group plus fixed trailing controls
                              // cannot.
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Sending to an agent remains a composer action: it
                                        // changes the destination of this message without
                                        // adding another control to the session list.
                                        if (!_isMissionControl) ...[
                                          Builder(
                                            builder: (ctx) =>
                                                _recipientAgentId == null
                                                    ? _composerChip(
                                                        icon: 'agent',
                                                        label: 'Send to',
                                                        onTap: () =>
                                                            _pickRecipient(ctx),
                                                      )
                                                    : _composerChip(
                                                        icon: 'agent',
                                                        label: _recipientAgentName ??
                                                            _recipientAgentId!,
                                                        selected: true,
                                                        onTap: () =>
                                                            _pickRecipient(ctx),
                                                        onClear:
                                                            _clearRecipient,
                                                      ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        // Approval mode lives here instead of the tool
                                        // band, so the setting sits next to what it
                                        // governs.
                                        Builder(
                                          builder: (ctx) => _composerChip(
                                            icon: 'shield',
                                            label: _approvalLabel,
                                            onTap: () => _switchApproval(ctx),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Builder(builder: (chipCtx) {
                                          return _composerChip(
                                            icon: 'sparkles',
                                            label: _modelLabel ?? 'Auto',
                                            onTap: () => _switchModel(chipCtx),
                                          );
                                        }),
                                      ]),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (kCanRecord) ...[
                                Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(R.sm),
                                  child: InkWell(
                                    onTap: _onMicTap,
                                    borderRadius: BorderRadius.circular(R.sm),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: AppIcon(
                                          _isRecording ? 'mic-off' : 'mic',
                                          size: 18,
                                          color: _isRecording
                                              ? AppColors.danger
                                              : AppColors.fg3),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _input,
                                builder: (_, __, ___) {
                                  final queue = running && _canSend;
                                  final stop = running && !queue;
                                  return _SendBtn(
                                      enabled: stop || _canSend,
                                      running: stop,
                                      onTap: stop
                                          ? () => _send({'kind': 'interrupt'})
                                          : (_canSend ? _sendMessage : null));
                                },
                              ),
                            ]),
                      ]),
                ),
              ],
              _composerMeta(_state),
            ]),
      ),
    );
  }

  // Composer attachment row: image thumbnails and file cards, each with its
  // own remove button and an upload overlay until the file reaches the daemon.
  Widget _attachmentBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(top: 6, right: 6),
          itemCount: _attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _attachmentTile(_attachments[i]),
        ),
      ),
    );
  }

  Widget _attachmentTile(_Attachment a) {
    const side = 56.0;
    final kind = a.isAudio
        ? MediaKind.audio
        : (a.isImage ? MediaKind.image : mediaKindOf(a.name));
    final Widget body;
    final pasted = a.pastedText;
    if (pasted != null) {
      final lines = '\n'.allMatches(pasted.trimRight()).length + 1;
      final firstLine = pasted.trim().split('\n').first.trim();
      body = GestureDetector(
        onTap: () => _editPasted(a),
        child: Container(
          height: side,
          width: 176,
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                AppIcon('file-text', size: 12, color: AppColors.fg3),
                const SizedBox(width: 5),
                Text('Pasted · $lines lines',
                    style: sans(11, weight: W.label, color: AppColors.fg2)),
              ]),
              const SizedBox(height: 4),
              Text(firstLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(11, color: AppColors.fg3)),
            ],
          ),
        ),
      );
    } else if (a.isImage &&
        ((a.localPath != null && File(a.localPath!).existsSync()) ||
            a.remotePath != null)) {
      // A restored draft may have lost its local file (phones clear picker
      // caches); the uploaded copy on the daemon stands in.
      final local = a.localPath != null && File(a.localPath!).existsSync();
      body = Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: local
            ? Image.file(File(a.localPath!),
                fit: BoxFit.cover, cacheWidth: 168, cacheHeight: 168)
            : Image(
                image: ResizeImage(widget.client.imageProvider(a.remotePath!),
                    width: 168, height: 168),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                    color: AppColors.surface2,
                    child: Center(
                        child:
                            AppIcon('image', size: 16, color: AppColors.fg4)))),
      );
    } else {
      final ext =
          a.name.contains('.') ? a.name.split('.').last.toUpperCase() : 'FILE';
      body = Container(
        height: side,
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: a.isAudio ? AppColors.accentBg : AppColors.surface3,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: AppIcon(
                a.isAudio ? 'mic' : (kind == MediaKind.pdf ? 'pdf' : 'file'),
                size: 16,
                color: a.isAudio ? AppColors.accent : AppColors.fg2),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.isAudio ? 'Voice note' : a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, weight: W.label, color: AppColors.fg1)),
                Text(a.isAudio ? 'Audio' : (ext.length > 6 ? 'FILE' : ext),
                    style: mono(10, color: AppColors.fg3)),
              ],
            ),
          ),
        ]),
      );
    }
    return Stack(clipBehavior: Clip.none, children: [
      body,
      if (a.uploading)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
                color: AppColors.scrim,
                borderRadius: BorderRadius.circular(R.md)),
            alignment: Alignment.center,
            child: Spinner(size: 16, color: AppColors.fg1),
          ),
        ),
      Positioned(
        top: -6,
        right: -6,
        child: Semantics(
          button: true,
          label: 'Remove ${a.name}',
          child: GestureDetector(
            onTap: () => _setState(() => _attachments.remove(a)),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              child: AppIcon('x', size: 10, color: AppColors.fg1),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Open a pasted-text card to read or edit it, move it back into the message
  /// as plain text, or drop it.
  Future<void> _editPasted(_Attachment a) async {
    final result = await presentScreen<(String, String)>(
      context,
      builder: (_, close) =>
          _PastedEditor(text: a.pastedText ?? '', onClose: close),
    );
    if (!mounted || result == null) return;
    final (action, text) = result;
    _setState(() {
      switch (action) {
        case 'save':
          if (text.trim().isEmpty) {
            _attachments.remove(a);
          } else {
            a.pastedText = text;
          }
        case 'inline':
          _attachments.remove(a);
          final current = _input.text;
          final joined = current.trim().isEmpty ? text : '$current\n$text';
          _input.value = TextEditingValue(
            text: joined,
            selection: TextSelection.collapsed(offset: joined.length),
          );
        case 'remove':
          _attachments.remove(a);
      }
    });
  }

  // ---- event → widget (pairs tool_call with its tool_result) ----
}

/// Full view of a pasted-text card: edit it, put it back into the message as
/// plain text, or remove it. Pops with (action, text).
class _PastedEditor extends StatefulWidget {
  final String text;
  final VoidCallback onClose;
  const _PastedEditor({required this.text, required this.onClose});

  @override
  State<_PastedEditor> createState() => _PastedEditorState();
}

class _PastedEditorState extends State<_PastedEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done(String action) => Navigator.of(context).pop((action, _text.text));

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(_text.text.trimRight()).length + 1;
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        child: Column(children: [
          SnAppBar(
            title: 'Pasted text',
            subtitle: '$lines lines',
            onBack: () => _done('save'),
            actions: [
              IconBtn('trash', tooltip: 'Remove', onTap: () => _done('remove')),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                style: mono(13, height: 1.45, color: AppColors.fg1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              TextButton(
                onPressed: () => _done('inline'),
                child: Text('Insert as text',
                    style: sans(13, color: AppColors.fg2)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _done('save'),
                child: Text('Done',
                    style:
                        sans(13, weight: W.label, color: AppColors.accentFg)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
