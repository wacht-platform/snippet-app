part of 'session.dart';

extension _SessionScreenTranscriptExt on _SessionScreenState {
  List<Widget> _transcript(List<Map<String, dynamic>> events) {
    final out = <Widget>[];
    Map<String, dynamic>? pending;
    final run = <Widget>[]; // consecutive dense tool rows
    String? runStartKey;
    String? pendingKey;
    final eventOccurrences = <String, int>{};
    final laneRowsShown = <String>{}; // spawn cards already emitted (by id)

    String eventKey(Map<String, dynamic> event) {
      // Use the stable fields that identify a transcript event instead of
      // JSON-serializing the entire historical event on every delta. The old
      // fingerprint became O(history) work for each new tool event and made
      // a burst of tool calls wait behind repeated full-list rebuilds.
      final fingerprint = Object.hash(
        event['kind'],
        event['tool_name'],
        event['text'],
        event['id'],
        event['path'],
        event['step'],
        event['created_at'],
      ).toString();
      final occurrence = eventOccurrences.update(
        fingerprint,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      return 'transcript-event-${fingerprint.hashCode}-$occurrence';
    }

    void addEvent(String key, Widget child) {
      out.add(KeyedSubtree(
        key: ValueKey(key),
        child: child,
      ));
    }

    void addToolRow(Widget child, String key) {
      runStartKey ??= key;
      run.add(child);
    }

    DenseToolRow toolRow(String key,
        {required String tool,
        dynamic args,
        dynamic result,
        int? resultAt,
        bool clipped = false}) {
      final open = _openToolRows.contains(key);
      if (open && clipped && resultAt != null) _requestFullEvent(resultAt);
      return DenseToolRow(
        key: ValueKey('tool-row-$key'),
        tool: tool,
        args: args,
        result: result,
        open: open,
        onOpenChanged: (next) {
          if (!mounted) return;
          if (next && clipped && resultAt != null) {
            _requestFullEvent(resultAt);
          }
          _setState(() {
            if (next) {
              _openToolRows.add(key);
            } else {
              _openToolRows.remove(key);
            }
            _transcriptDirty = true;
          });
        },
      );
    }

    void flushPending(String fallbackKey) {
      final p = pending;
      if (p != null) {
        final name = _s(p['tool_name']);
        final k = pendingKey ?? fallbackKey;
        addToolRow(toolRow(k, tool: name, args: p['arguments']), k);
        pending = null;
        pendingKey = null;
      }
    }

    void endTools(String fallbackKey) {
      flushPending(fallbackKey);
      if (run.isEmpty) return;
      final start = runStartKey ?? fallbackKey;
      final isSessionRunning = _state?.status == 'running';
      final running =
          isSessionRunning && run.any((w) => w is DenseToolRow && w.pending);
      final toolKey = 'transcript-tools-$start';
      final open = _toolRunOpen[toolKey] ?? false;
      final batch = ToolBatch([
        for (final r in run.whereType<DenseToolRow>())
          ToolStep(tool: r.tool, args: r.args, result: r.result),
      ], running: running);
      final live =
          _toolBatches.putIfAbsent(toolKey, () => ValueNotifier(batch));
      // An open sheet listens to this; update it after the frame so the sheet
      // never rebuilds in the middle of the transcript's own build.
      WidgetsBinding.instance.addPostFrameCallback((_) => live.value = batch);
      out.add(KeyedSubtree(
        key: ValueKey(toolKey),
        child: ToolRun(
          List.of(run),
          running: running,
          open: open,
          batch: live,
          onOpenChanged: (nextOpen) {
            if (!mounted) return;
            _setState(() {
              _toolRunOpen[toolKey] = nextOpen;
              // The transcript is normally cached between event updates. Rebuild
              // it now so ToolRun receives the new open value immediately.
              _transcriptDirty = true;
            });
          },
        ),
      ));
      run.clear();
      runStartKey = null;
    }

    LaneInfo? liveLane(String id) {
      for (final l in _state?.lanes ?? const <LaneInfo>[]) {
        if (l.id == id) return l;
      }
      return null;
    }

    for (var idx = 0; idx < events.length; idx++) {
      final e = events[idx];
      final key = eventKey(e);
      final abs = 'event-${_transcriptStart + idx}';
      final k = e['kind'] as String? ?? '';
      switch (k) {
        case 'tool_call':
          flushPending(key);
          // Meta-tools render via their own events (note → note, ask_user →
          // user_question, delegate_task → lane_spawned). Skip their generic tool
          // lines so they don't double up.
          if (_isMetaTool(_s(e['tool_name']))) break;
          pending = e;
          pendingKey = abs;
        case 'tool_result':
          {
            final p = pending;
            if (p != null) {
              final k = pendingKey ?? abs;
              addToolRow(
                  toolRow(k,
                      tool: _s(p['tool_name']),
                      args: p['arguments'],
                      result: e['result'],
                      resultAt: _transcriptStart + idx,
                      clipped: e['result_clipped'] == true),
                  k);
              pending = null;
              pendingKey = null;
            } else {
              final name = _s(e['tool_name']);
              if (_isMetaTool(name)) break;
              addToolRow(
                  toolRow(abs,
                      tool: name,
                      result: e['result'],
                      resultAt: _transcriptStart + idx,
                      clipped: e['result_clipped'] == true),
                  abs);
            }
          }
        case 'user_input':
        case 'steer':
          endTools(key);
          final text = _s(e['text']);
          // Answers are already shown on the question card — don't also
          // render them as a user bubble.
          if (_looksLikeQuestionAnswer(text)) break;
          final envelope = parseMissionEnvelope(text);
          if (envelope != null) {
            addEvent(key, MissionEnvelopeCard(envelope: envelope));
            break;
          }
          final round = parseAutonomousRound(text);
          if (round != null) {
            addEvent(key, AutonomousRoundCard(round: round));
            break;
          }
          final workerQuestion = parseWorkerQuestion(text);
          if (workerQuestion != null) {
            addEvent(key, WorkerQuestionCard(question: workerQuestion));
            break;
          }
          final board = parseBoardMessage(text);
          if (board != null) {
            addEvent(key, BoardMessageCard(message: board));
            break;
          }
          final direct = parseDirectMessage(text);
          if (direct != null) {
            addEvent(key, DirectMessageCard(message: direct));
            break;
          }
          final reply = parseCoordinationReply(text);
          if (reply != null) {
            addEvent(key, DirectMessageCard(message: reply));
            break;
          }
          final assignment = parseAssignmentEnvelope(text);
          if (assignment != null) {
            addEvent(key, AssignmentCard(assignment: assignment));
            break;
          }
          addEvent(
              key,
              KeyedSubtree(
                child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 20),
                    child:
                        Bubble(mine: true, text: text, client: widget.client)),
              ));
        case 'assistant_text':
          endTools(key);
          final reply = _s(e['text']);
          addEvent(
              key,
              Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Bubble(mine: false, text: reply)));
        case 'agent_message':
          endTools(key);
          addEvent(
              key,
              AgentMessageCard(
                agentId: _s(e['agent_id']),
                body: _s(e['body']),
                outbound: e['outbound'] == true,
              ));
        case 'model_error':
          endTools(key);
          addEvent(key,
              NoteLine(_s(e['message']), error: true, label: 'Model error'));
        case 'invalid_tool_call':
          endTools(key);
          addEvent(
              key,
              NoteLine(_s(e['error']),
                  error: true, label: 'Invalid call · ${_s(e['tool_name'])}'));
        case 'plan_updated':
          endTools(key);
          final steps =
              (e['steps'] as List? ?? const []).whereType<Map>().toList();
          if (steps.isNotEmpty) {
            addEvent(key, _PlanCard(steps, _s(e['explanation'])));
          }
        case 'system_decision':
          endTools(key);
          // Don't render "interrupted" decisions — just noise in the chat.
          if (_s(e['step']) == 'interrupted') break;
          addEvent(key,
              SystemRow(step: _s(e['step']), reasoning: _s(e['reasoning'])));
        case 'file_presented':
          endTools(key);
          addEvent(key, _presentedFileCard(_s(e['path']), _s(e['caption'])));
        case 'lane_spawned':
          endTools(key);
          final id = _s(e['id']);
          final title = _s(e['title']);
          // Dedup by ID AND title — the same lane can be spawned with
          // different IDs on reconnect (resume), producing visual duplicates.
          if (!laneRowsShown.contains(id) &&
              !laneRowsShown.contains('t:$title')) {
            laneRowsShown.add(id);
            laneRowsShown.add('t:$title');
            addEvent(
                key,
                LaneNotice(
                  title: title,
                  live: () => liveLane(id),
                  onOpen: _showLanes,
                ));
          }
        case 'lane_cancelled':
        case 'lane_completed':
          endTools(key);
          final id = _s(e['id']);
          // The spawn card already tracks this lane live — only render a card
          // here if the spawn row is gone (e.g. compacted away).
          if (!laneRowsShown.contains(id)) {
            addEvent(
                key,
                LaneNotice(
                  title: _s(e['title']),
                  live: () => liveLane(id),
                  onOpen: _showLanes,
                  summary: _s(e['summary']),
                ));
          }
        case 'user_question':
          endTools(key);
          String? answer;
          final qi = events.indexOf(e);
          for (var j = qi + 1; j < events.length; j++) {
            final n = events[j];
            if (n['kind'] == 'user_question') break;
            if (n['kind'] == 'user_input' || n['kind'] == 'steer') {
              final t = _s(n['text']);
              if (t.trim().isNotEmpty) {
                answer = t;
                break;
              }
            }
          }
          // The open question is already the answer bar under the transcript;
          // it joins the record once answered.
          final laterQuestion =
              events.skip(qi + 1).any((n) => n['kind'] == 'user_question');
          if (answer == null && !laterQuestion && _questionOpen) break;
          addEvent(key, _QuestionRecord(e, answer: answer));
        case 'approval_request':
          break; // shown by the approval bar
        default:
          break;
      }
    }
    // Trailing tool_call/tool_result events stay in `run` until a later
    // user/assistant message would flush them. Without this, live tools
    // remain invisible until the next chat message.
    endTools('transcript-tools-tail');
    // Coordination rows go LAST: they are the most recent thing to happen to
    // this session's agent, and they read as a live footer under the work.
    for (var i = 0; i < _agentEvents.length; i++) {
      out.add(_agentEventRow(_agentEvents[i], i));
    }
    return out;
  }

  /// A file the agent handed over (`present_file`): open in the editor, or
  /// download to the device.
  Widget _presentedFileCard(String path, String caption) {
    final name = path.split('/').last;
    if (mediaKindOf(path) == MediaKind.image) {
      // Full width and left-aligned: a shrink-wrapped column was centred by
      // its parent, so a long caption pushed the image off the text's edge.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: double.infinity,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleImage(client: widget.client, path: path),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(caption, style: sans(12, height: 1.4, color: AppColors.fg3)),
            ],
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          // The icon is INSIDE the tap target. It was outside, so tapping the
          // most obviously tappable part of the card did nothing.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // ON PHONES: a full-screen route, exactly as the browser does.
                // `onOpenFileTab` creates a shell TAB, which the phone shell
                // never draws (see `openFileForViewing`), so calling it here
                // made the card inert — tapping did nothing at all.
                if (openFileForViewing(context,
                    client: widget.client, path: path, name: name)) {
                  return;
                }
                if (widget.onOpenFileTab != null) {
                  widget.onOpenFileTab!(path, name);
                } else {
                  presentScreen(
                    context,
                    builder: (_, close) => EditorScreen(
                        client: widget.client,
                        path: path,
                        name: name,
                        onClose: close),
                  );
                }
              },
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.accentBg,
                      borderRadius: BorderRadius.circular(R.sm)),
                  child: AppIcon('file', size: 16, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(13, color: AppColors.fg1)),
                        const SizedBox(height: 2),
                        Text(caption.isNotEmpty ? caption : path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.caption()),
                      ]),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () async {
              try {
                toast(context, 'Downloading $name…');
                final msg = await downloadRemoteFileWithCancel(
                    context, widget.client,
                    path: path, name: name);
                if (msg != null && mounted) toast(context, msg);
              } catch (e) {
                if (mounted) toast(context, '$e', danger: true);
              }
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: AppColors.accentFg,
              backgroundColor: AppColors.accentFill,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.xs)),
            ),
            child: Text('Download',
                style: sans(12, weight: W.label, color: AppColors.accentFg)),
          ),
        ]),
      ),
    );
  }

  String _s(dynamic v) => v?.toString() ?? '';

  /// Live thought stays until this turn produces a tool/action the user can see.
  bool _turnHasVisibleAction(List<Map<String, dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      switch (events[i]['kind'] as String? ?? '') {
        case 'user_input':
        case 'steer':
          return false;
        case 'tool_call':
        case 'tool_result':
        case 'invalid_tool_call':
        case 'plan_updated':
        case 'file_presented':
        case 'user_question':
        case 'approval_request':
        case 'lane_spawned':
        case 'lane_cancelled':
        case 'lane_completed':
        case 'assistant_text':
          return true;
      }
    }
    return false;
  }

  // Meta-tools have dedicated event rendering, so their generic tool lines are skipped.
  bool _isMetaTool(String n) =>
      n == 'update_plan' ||
      n == 'ask_user' ||
      n == 'delegate_task' ||
      n == 'cancel_delegated_task' ||
      n == 'complete_goal' ||
      n == 'monitor' ||
      n == 'present_file';

  Future<void> _switchModel([BuildContext? anchor]) async {
    ServerConfig cfg;
    try {
      cfg = await widget.client.getConfig();
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) return;
    if (cfg.profiles.isEmpty) {
      _toast('No inference profiles');
      return;
    }
    final current = _modelLabel;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor ?? context,
      verticalAnchor: _composerCardKey.currentContext,
      minWidth: 260,
      maxWidth: 360,
      items: [
        appMenuHeading<String>('Inference profile'),
        for (final p in cfg.profiles)
          appMenuRow<String>(
            value: p.name,
            icon: 'sparkles',
            label: p.name,
            description: '${p.provider} · ${p.model}',
            selected: p.name == current,
          ),
      ],
    );
    if (picked == null || picked == current) return;
    final before = _currentProfile;
    _setState(() => _currentProfile = picked);
    try {
      await widget.client.setSessionModel(widget.sessionId, picked);
      if (mounted) {
        _loadModel();
        _connect();
      }
    } catch (e) {
      if (mounted) _setState(() => _currentProfile = before);
      _toast('$e');
    }
  }

  void _showLanes() {
    if ((_state?.lanes ?? const <LaneInfo>[]).isEmpty) return;
    presentScreen(
      context,
      style: PanelStyle.drawer,
      purpose: ShellPanelPurpose.lanes,
      originClient: widget.client,
      originSessionId: widget.sessionId,
      builder: (_, close) => LanesScreen(
        liveLanes: () => _state?.lanes ?? const <LaneInfo>[],
        onClose: close,
      ),
    );
  }

  /// Message an agent from THIS session.
  ///
  /// The message carries this session as its origin, so the agent knows which
  /// session to reply in and which session to request dispatch on. Nothing here
  /// creates work: dispatching belongs to Mission Control.
  Future<void> _giveWork() async {
    final sent = await showAgentWorkSheet(
      context,
      client: widget.client,
      sessionId: widget.sessionId,
      workspaceLabel: _state?.workspace,
    );
    if (sent && mounted) {
      _toast('Sent — the agent replies in this session');
    }
  }

  void _showCheckpoints() {
    final s = _state;
    if (s == null) return;
    final cps = s.checkpoints.reversed.toList();
    final content = Column(children: [
      if (cps.isEmpty)
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text('No checkpoints yet.', style: TS.meta())),
      ...cps.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(13),
              onTap: () => _confirmRewind(c),
              child: Row(children: [
                const IconTile('history', size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.label.isEmpty ? c.id : c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.rowTitle()),
                        const SizedBox(height: 3),
                        Text(formatCheckpointDate(c.createdAt),
                            style: TS.meta()),
                      ]),
                ),
                IconBtn('git-branch',
                    size: 32,
                    iconSize: 16,
                    tooltip: 'Fork from here',
                    onTap: () => _confirmFork(c)),
              ]),
            ),
          )),
    ]);
    if (kMobile) {
      showAppSheet(context, title: 'Checkpoints', child: content);
    } else {
      presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.checkpoints,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => _SessionActionPanel(
              title: 'Checkpoints', onClose: close, child: content));
    }
  }

  /// Resolve a checkpoint id sent from the shell's right pane against live
  /// state, so the pane never holds a stale copy.
  Checkpoint? _checkpointById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in _state?.checkpoints ?? const <Checkpoint>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _confirmRewind(Checkpoint c) async {
    final ok = await confirmAction(
      context,
      title: 'Restore workspace?',
      body:
          'This rolls the workspace back to “${c.label.isEmpty ? c.id : c.label}”. Changes after this point are discarded.',
      confirmLabel: 'Restore',
      danger: false,
    );
    if (!ok) return;
    if (mounted) Navigator.pop(context); // close the sheet
    try {
      await widget.client.rewind(widget.sessionId, c.id);
      _toast('Workspace restored');
    } catch (e) {
      _toast('$e');
    }
  }

  // Kept temporarily for compatibility with any in-flight route callbacks; the
  // user-facing fork entry now lives only inside Checkpoints.
  // ignore: unused_element
  void _showForkPoints() {
    final s = _state;
    if (s == null) return;
    final cps = s.checkpoints.reversed.toList();
    showAppSheet(context,
        title: 'Fork conversation',
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Creates a new session with history up to the point you pick. '
              'This chat is left unchanged. Workspace files are shared.',
              style: sans(12, height: 1.45, color: AppColors.fg3),
            ),
          ),
          if (cps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'No checkpoints yet — you can still fork the full history.',
                      style: TS.meta()),
                  const SizedBox(height: 12),
                  Btn('Fork full history', onTap: () => _confirmFork(null)),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(13),
                onTap: () => _confirmFork(null),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: AppIcon('git-branch',
                        size: 17, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full history', style: TS.rowTitle()),
                        const SizedBox(height: 3),
                        Text('Branch everything so far', style: TS.meta()),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                ]),
              ),
            ),
            ...cps.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(13),
                    onTap: () => _confirmFork(c),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: AppIcon('git-branch',
                            size: 17, color: AppColors.fg3),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.label.isEmpty ? c.id : c.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TS.rowTitle()),
                            const SizedBox(height: 3),
                            Text(formatCheckpointDate(c.createdAt),
                                style: TS.meta()),
                          ],
                        ),
                      ),
                      AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                    ]),
                  ),
                )),
          ],
        ]));
  }

  Future<void> _confirmFork(Checkpoint? c) async {
    final label =
        c == null ? 'full history' : (c.label.isEmpty ? c.id : c.label);
    final ok = await confirmAction(
      context,
      title: 'Fork conversation?',
      body:
          'Opens a new session branched at “$label”. This chat stays as-is. Files on disk are shared.',
      confirmLabel: 'Fork',
      danger: false,
    );
    if (!ok) return;
    if (mounted) Navigator.pop(context); // close the sheet
    try {
      final result = await widget.client.forkSession(
        widget.sessionId,
        checkpoint: c?.id,
        eventIndex: c == null && (_state?.events.isNotEmpty ?? false)
            ? _state!.events.length - 1
            : null,
      );
      final id = result['id']?.toString() ?? '';
      final title = result['title']?.toString() ?? 'fork';
      if (id.isEmpty) {
        _toast('Fork created but no session id returned');
        return;
      }
      final open = widget.onOpenSession;
      if (open != null) {
        open(id, title, widget.profile);
      } else {
        _toast('Forked → $title');
      }
    } catch (e) {
      _toast('$e');
    }
  }
}
