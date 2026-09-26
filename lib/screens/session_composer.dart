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
    final ready = _attachments.where((a) => a.remotePath != null).toList();
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
    final markers = ready
        .map((a) => a.isImage
            ? '[attached image — call read_image on this exact path to view it: ${a.remotePath}]'
            : '[attached file — read it at this exact path: ${a.remotePath}]')
        .join('\n');
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
    final markers = ready
        .map((a) => a.isImage
            ? '[attached image — call read_image on this exact path to view it: ${a.remotePath}]'
            : '[attached file — read it at this exact path: ${a.remotePath}]')
        .join('\n');
    final body = markers.isEmpty ? text : (text.isEmpty ? markers : '$text\n\n$markers');
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
    final title = '$count  Queued messages';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TS.label(),
              ),
              const Spacer(),
              if (queue.length > 1) ...[
                GestureDetector(
                  onTap: _steerAllQueued,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('Send all',
                        style: sans(12,
                            weight: W.label, color: AppColors.accent)),
                  ),
                ),
                GestureDetector(
                  onTap: _cancelAllQueued,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('Cancel all',
                        style: sans(12, color: AppColors.fg3)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (var qi = 0; qi < queue.length; qi++) ...[
            if (qi > 0) const SizedBox(height: 6),
            _queuedItemRow(qi, queue[qi]),
          ],
        ],
      ),
    );
  }

  Widget _queuedItemRow(int qi, QueuedInput item) {
    final isHovered = _hoveredQueuedIndex == qi;
    final showActions = kMobile || isHovered;
    final text = _queuedText(item.text);
    final counts = _queuedAttachCounts(item.text);

    Widget action(String icon, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AppIcon(icon, size: 13, color: AppColors.fg3),
          ),
        ),
      );
    }

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action('trash', 'Delete', () => _cancelQueuedAt(qi)),
        action('edit', 'Edit', () => _editQueuedAt(qi)),
        action('arrow-up', 'Send now', () => _steerQueuedAt(qi)),
      ],
    );

    // 3 icons × 13px + 3 × 8px padding = 63px
    const trailingWidth = 63.0;

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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text.isEmpty ? '(attachment)' : text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1),
                  ),
                  if (counts.$1 + counts.$2 + counts.$3 > 0) ...[
                    const SizedBox(height: 4),
                    AttachmentPill(
                      audio: counts.$1,
                      images: counts.$2,
                      files: counts.$3,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (kMobile)
              actionButtons
            else
              SizedBox(
                width: trailingWidth,
                child: AnimatedOpacity(
                  opacity: showActions ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    ignoring: !showActions,
                    child: actionButtons,
                  ),
                ),
              ),
          ],
        ),
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
          _attachments.any((a) => a.remotePath != null)) &&
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
  String get _approvalLabel => (_state?.approvalMode ?? 'auto') == 'manual'
      ? 'Ask'
      : 'Auto';

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
        color: selected ? AppColors.accentBg : AppColors.surface2,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: Container(
            height: 28,
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
                    style: sans(12,
                        weight: selected ? W.label : W.body,
                        color: selected ? AppColors.accent : AppColors.fg2)),
                if (onClear != null)
                  IconBtn('x',
                      size: 22,
                      iconSize: 12,
                      tooltip: 'Clear',
                      onTap: onClear)
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
                        style: sans(11, color: AppColors.fg3)),
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
              if (_isRecording || _recordingPath != null) _recordingPanel(),
              Container(
                key: _composerCardKey,
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(R.lg),
                  border: _draggingFiles
                      ? Border.all(color: AppColors.accent, width: 1.5)
                      : null,
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
                            AppIcon('goal', size: 14, color: AppColors.accent),
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
                          const SingleActivator(LogicalKeyboardKey.enter): () {
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
                          minLines: 2,
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
                            hintText: 'Ask anything',
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
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                  // Sending to an agent remains a composer action: it
                                  // changes the destination of this message without
                                  // adding another control to the session list.
                                  Builder(
                                    builder: (ctx) => _recipientAgentId == null
                                        ? _composerChip(
                                            icon: 'agent',
                                            label: 'Send to',
                                            onTap: () => _pickRecipient(ctx),
                                          )
                                        : _composerChip(
                                            icon: 'agent',
                                            label: _recipientAgentName ??
                                                _recipientAgentId!,
                                            selected: true,
                                            onTap: () => _pickRecipient(ctx),
                                            onClear: _clearRecipient,
                                          ),
                                  ),
                                  const SizedBox(width: 6),
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
              _composerMeta(_state),
            ]),
      ),
    );
  }

  // Composer attachment row: image thumbnails + file chips, each with its own ✕.
  Widget _attachmentBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => _attachmentTile(_attachments[i]),
        ),
      ),
    );
  }

  Widget _attachmentTile(_Attachment a) {
    final thumb = a.isImage && a.localPath != null;
    final isAudio = a.isAudio;
    final body = thumb
        ? ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: Image.file(File(a.localPath!),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                cacheWidth: 72,
                cacheHeight: 72),
          )
        : Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isAudio ? AppColors.accentBg : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(isAudio ? 'mic' : (a.isImage ? 'image' : 'file'),
                  size: 12, color: isAudio ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11,
                        color: isAudio ? AppColors.accent : AppColors.fg2)),
              ),
            ]),
          );
    return Stack(children: [
      body,
      if (a.uploading)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
                color: AppColors.scrim,
                borderRadius: BorderRadius.circular(R.sm)),
            alignment: Alignment.center,
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg2)),
          ),
        ),
      Positioned(
        top: 3,
        right: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _setState(() => _attachments.remove(a)),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: AppColors.scrim, shape: BoxShape.circle),
            child: AppIcon('x', size: 11, color: AppColors.fg1),
          ),
        ),
      ),
    ]);
  }

  // ---- event → widget (pairs tool_call with its tool_result) ----
}
