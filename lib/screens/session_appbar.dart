part of 'session.dart';

extension _SessionScreenAppBarExt on _SessionScreenState {
  void _applyTermFrame(Map<String, dynamic> j) {
    final seq = (j['seq'] as num?)?.toInt() ?? 0;
    if (seq != 0 && seq == _termSeq) return;
    if (seq != 0) _termSeq = seq;
    final id = (j['id'] as String?) ?? '0';
    final op = (j['op'] as String?) ?? '';
    final cols = (j['cols'] as num?)?.toInt();
    final rows = (j['rows'] as num?)?.toInt();
    final raw = j['data'] as String?;
    final bytes = (raw == null || raw.isEmpty)
        ? Uint8List(0)
        : Uint8List.fromList(base64Decode(raw));
    if (!mounted) return;
    _setState(() {
      final pane = _ensureTerm(id);
      pane.alive = j['alive'] == true;
      if (op == 'snapshot') return;
      if (bytes.isNotEmpty) {
        pane.terminal.write(utf8.decode(bytes, allowMalformed: true));
      }
      if (cols != null) pane.cols = cols;
      if (rows != null) pane.rows = rows;
      if (op == 'out') pane.live = true;
    });
    // Only an `alive`/`live` transition or a new terminal changes what the
    // sidebar shows. Output frames must not republish: that would rebuild the
    // shell on every byte the pty writes.
    _publishTerminals();
    if (op == 'out' && j['alive'] == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeTerm(id);
      });
    }
  }

  String _nextTermTitle() {
    var n = _terms.length + 1;
    final used = _terms.map((t) => t.title).toSet();
    while (used.contains('shell $n')) {
      n++;
    }
    return 'shell $n';
  }

  _LiveTerm _ensureTerm(String id) {
    for (final t in _terms) {
      if (t.id == id) return t;
    }
    final t = _LiveTerm(id, title: _nextTermTitle());
    _terms.add(t);
    return t;
  }

  void _openTerm({bool fresh = false}) {
    // Mission Control has no working tree to shell into.
    if (_isMissionControl) return;
    // Second click on Shell hides the drawer — keep the pty so reopening is instant.
    if (!fresh && _termOpen && _terms.isNotEmpty) {
      _setState(() => _termOpen = false);
      return;
    }
    if (!fresh && _terms.isNotEmpty) {
      _setState(() => _termOpen = true);
      final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
      _send({
        'wire': 'term',
        'op': 'open',
        'id': t.id,
        'cols': t.cols,
        'rows': t.rows,
      });
      _publishTerminals();
      return;
    }
    final used = _terms.map((t) => int.tryParse(t.id) ?? 0).fold(0, math.max);
    final id = _terms.isEmpty ? '0' : '${used + 1}';
    _setState(() {
      _termOpen = true;
      _ensureTerm(id);
      _termFocus = _terms.length - 1;
    });
    _send({
      'wire': 'term',
      'op': fresh ? 'new' : 'open',
      'id': id,
      'cols': 80,
      'rows': 24,
    });
    _publishTerminals();
  }

  void _closeTerm(String id) {
    _send({'wire': 'term', 'op': 'close', 'id': id});
    _setState(() {
      _terms.removeWhere((t) => t.id == id);
      if (_terms.isEmpty) {
        _termOpen = false;
        _termFocus = 0;
      } else {
        _termFocus = _termFocus.clamp(0, _terms.length - 1);
      }
    });
    _publishTerminals();
  }

  /// Focus an existing terminal by index, opening the drawer if it is closed.
  ///
  /// Selecting a row in the shell's terminal panel must land on *that*
  /// terminal, so this takes an index rather than toggling whatever was last
  /// focused.
  void _focusTerm(int i) {
    if (_isMissionControl || i < 0 || i >= _terms.length) return;
    _setState(() {
      _termOpen = true;
      _termFocus = i;
    });
    final t = _terms[i];
    _send({
      'wire': 'term',
      'op': 'open',
      'id': t.id,
      'cols': t.cols,
      'rows': t.rows,
    });
    _publishTerminals();
  }

  /// Hand the shell a host for this session's terminals, plus whether the pane
  /// should currently be showing.
  ///
  /// Cheap and idempotent; called from the paths that can change the set, the
  /// focus, or the open flag — never from the output stream.
  void _publishTerminals() {
    final publish = widget.onTerminalHost;
    if (publish == null) return;
    publish(
      TerminalHost(
        terms: [
          for (final t in _terms)
            TerminalInfo(
              id: t.id,
              title: t.title,
              alive: t.alive,
              live: t.live,
            ),
        ],
        focus: _termFocus,
        buildView: _buildTermView,
        onFocus: _focusTermById,
        onRequestNew: () => _openTerm(fresh: true),
        onRequestClose: _closeTerm,
      ),
      // `_termOpen` is the "not minimized" flag. Minimizing hides the pane but
      // deliberately keeps the pty alive — only the sidebar destroys a shell.
      _termOpen,
    );
  }

  /// Render one terminal by id, for whichever pane is currently hosting it.
  ///
  /// The shell owns the pane; the session owns the socket and the view's input
  /// wiring, so it must supply the widget rather than expose the `Terminal`.
  Widget _buildTermView(String id, {required bool mobileKeys}) {
    final t = _terms.firstWhere((e) => e.id == id, orElse: () => _terms.first);
    return SessionTermView(
      alive: t.alive,
      terminal: t.terminal,
      onInput: (bytes) => _termInFor(t.id, bytes),
      onResize: (cols, rows) => _termResizeFor(t.id, cols, rows),
      onClose: () => _closeTerm(t.id),
      mobileKeys: mobileKeys,
      showChrome: false,
    );
  }

  /// Focus a terminal by id. The shell knows ids; the session knows order.
  void _focusTermById(String id) {
    final i = _terms.indexWhere((t) => t.id == id);
    if (i >= 0) _focusTerm(i);
  }

  void _termInFor(String id, Uint8List bytes) {
    _send({
      'wire': 'term',
      'op': 'in',
      'id': id,
      'data': base64Encode(bytes),
    });
  }

  void _termResizeFor(String id, int cols, int rows) {
    for (final t in _terms) {
      if (t.id == id) {
        t.cols = cols;
        t.rows = rows;
        break;
      }
    }
    _send({
      'wire': 'term',
      'op': 'resize',
      'id': id,
      'cols': cols,
      'rows': rows,
    });
  }

  void _termIn(Uint8List bytes) {
    if (_terms.isEmpty) return;
    final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
    _send({
      'wire': 'term',
      'op': 'in',
      'id': t.id,
      'data': base64Encode(bytes),
      'cols': t.cols,
      'rows': t.rows,
    });
  }

  void _termResize(int cols, int rows) {
    if (_terms.isEmpty) return;
    final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
    t.cols = cols;
    t.rows = rows;
    _send({
      'wire': 'term',
      'op': 'resize',
      'id': t.id,
      'cols': cols,
      'rows': rows,
    });
  }

  Future<void> _renameCurrent() async {
    if (_isMissionControl) return;
    final title = await promptText(context,
        title: 'Rename session',
        initial: _title,
        hint: 'New title',
        saveLabel: 'Rename');
    if (title == null) return;
    final before = _title;
    _setState(() => _publishTitle(title));
    try {
      await widget.client.renameSession(widget.sessionId, title);
    } catch (e) {
      if (mounted) {
        _setState(() => _publishTitle(before));
        _toast('$e');
      } else {
        _publishTitle(before);
      }
    }
  }

  // On desktop, keep chat content to a comfortable reading width (centered),
  // rather than stretching across the whole pane.
  Widget _centerWide(Widget child) => widget.embedded
      ? Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740), child: child))
      : child;

  // Mobile chat header: a back button that returns to the session list, the
  // title with a live status dot, and a compact subtitle folding in the key
  // facts (status · model · context · approval) — so there's no separate,
  // cramped desktop toolbar + scrolling chip strip on a phone.
  /// Phone session bar: back, title, and the shell action. Deliberately NO run
  /// state — the chat canvas already carries working/idle, so a second readout
  /// here was one more thing competing with the title for the same 56px.
  Widget _runningLanesBadge(HarnessState s, EdgeInsets margin) {
    final n = s.lanes.where((l) => l.running).length;
    return Tooltip(
      message: '$n parallel agent${n == 1 ? '' : 's'} running',
      child: GestureDetector(
        onTap: _showLanes,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: margin,
          child: Tag('$n ${n == 1 ? 'agent' : 'agents'}',
              tone: Tone.accent, live: true),
        ),
      ),
    );
  }

  Widget _readOnlyHeader(String status) {
    final live = status == 'running';
    final label = switch (status) {
      'running' => 'Working',
      'completed' || 'idle' => 'Finished',
      'failed' => 'Failed',
      'connecting' => 'Connecting',
      _ => status,
    };
    final (fg, _) = toneColors(live ? Tone.run : Tone.neutral);
    return Container(
      height: kMobile ? M.appBarHeight : 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.bg,
      child: Row(children: [
        IconBtn('chevron-left',
            size: kMobile ? M.minTarget : 32,
            iconSize: 20,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              _title.isEmpty ? 'Lane' : _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(kMobile ? M.sectionTitle : 15,
                  weight: W.label, color: AppColors.fg1),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: mono(11, color: fg)),
          ]),
        ),
      ]),
    );
  }

  Widget _headerStatusLine(HarnessState s) {
    final (label, dot) = switch (s.status) {
      'running' => ('Working', AppColors.run),
      'waiting_for_input' => ('Waiting for you', AppColors.accent),
      'failed' => ('Stopped on an error', AppColors.danger),
      'connecting' => ('Connecting', AppColors.fg4),
      _ => ('Idle', AppColors.fg4),
    };
    final folder = lastPathSegment(s.workspace, ifEmpty: '');
    return Row(children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(folder.isEmpty ? label : '$label · $folder',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(12, height: 16 / 12, color: AppColors.fg3)),
      ),
    ]);
  }

  Widget _mobileHeader(HarnessState? s) {
    return Container(
      height: M.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.bg,
      child: Row(children: [
        if (widget.onMenu != null)
          IconBtn('chevron-left',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Chats',
              onTap: widget.onMenu),
        // Tapping the header opens the ACTIONS panel (the chevron beside it goes
        // back to Chats). The bar is a 44px tall target, far easier to hit than
        // a glyph, and it is where a thumb naturally lands to get at "everything
        // I can do here".
        Expanded(
          child: InkWell(
            onTap: () => _openActionsDrawer(s),
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _title.isEmpty ? 'Session' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.sectionTitle().copyWith(fontSize: 17),
                  ),
                  if (s != null) ...[
                    const SizedBox(height: 1),
                    _headerStatusLine(s),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (s != null && s.lanes.any((l) => l.running))
          _runningLanesBadge(s, const EdgeInsets.only(right: 6)),
        if (!_isMissionControl)
          IconBtn('terminal',
              size: M.minTarget,
              iconSize: 19,
              tooltip: 'Shell',
              onTap: _openTerm),
      ]),
    );
  }

  /// Desktop terminal pane: a resizable split BESIDE the chat.
  ///
  /// Replaces the bottom drawer. The drawer stacked under the transcript and
  /// competed with it for height, hiding the composer; a side pane keeps both
  /// usable and is the same shape as the reference's chat/split arrangement.
  Widget _desktopTermPane() {
    final i = _termFocus.clamp(0, _terms.length - 1);
    final t = _terms[i];
    final maxW = MediaQuery.sizeOf(context).width * 0.72;
    return Row(
      // Sized to content: this is a non-flex child of the chat Row, so it must
      // not try to expand.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 6px grab zone carrying a 1px rule. A chunky grab bar would eat
        // transcript width for no benefit.
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) {
              _setState(() {
                _termWidth = (_termWidth - d.delta.dx).clamp(280.0, maxW);
              });
            },
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.border2)),
              ),
            ),
          ),
        ),
        Container(
          width: _termWidth,
          color: const Color(0xff0a0a0a),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _termTabStrip(i, compact: true),
              Expanded(
                child: SessionTermView(
                  alive: t.alive,
                  terminal: t.terminal,
                  onInput: _termIn,
                  onResize: _termResize,
                  onClose: () => _closeTerm(t.id),
                  mobileKeys: false,
                  showChrome: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobileTermTab() {
    final i = _termFocus.clamp(0, _terms.length - 1);
    final t = _terms[i];
    final folder = lastPathSegment(_state?.workspace ?? '', ifEmpty: '');
    return Material(
      color: AppColors.canvas,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 10, 0),
          child: Row(children: [
            IconBtn('chevron-left',
                size: M.minTarget,
                iconSize: 20,
                tooltip: 'Back to chat',
                onTap: () => _setState(() => _termOpen = false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shell',
                      style: TS.sectionTitle().copyWith(fontSize: 17)),
                  const SizedBox(height: 1),
                  Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: t.alive ? AppColors.ok : AppColors.fg4,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                          [
                            t.alive ? 'Running' : 'Starting',
                            if (folder.isNotEmpty) folder
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg3)),
                    ),
                  ]),
                ],
              ),
            ),
            Material(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openTerm(fresh: true),
                child: SizedBox.square(
                  dimension: 38,
                  child: Center(
                      child: AppIcon('plus', size: 18, color: AppColors.fg1)),
                ),
              ),
            ),
          ]),
        ),
        if (_terms.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: _mobileTermTabs(i),
          ),
        Expanded(
          child: SessionTermView(
            alive: t.alive,
            terminal: t.terminal,
            onInput: _termIn,
            onResize: _termResize,
            onClose: () => _closeTerm(t.id),
            mobileKeys: true,
            showChrome: false,
          ),
        ),
      ]),
    );
  }

  /// Rename a terminal from its tab. Titles are local to this client (the pty
  /// has no notion of a name), so this only has to republish to the sidebar.
  Future<void> _renameTerm(String id) async {
    final t = _terms.firstWhere((e) => e.id == id, orElse: () => _terms.first);
    final name = await promptText(context,
        title: 'Rename terminal',
        initial: t.title,
        hint: 'Terminal name',
        saveLabel: 'Rename');
    if (name == null || name.trim().isEmpty) return;
    _setState(() => t.title = name.trim());
    _publishTerminals();
  }

  Widget _mobileTermTabs(int focus) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _terms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, n) {
          final on = n == focus;
          final pane = _terms[n];
          return Material(
            color: on ? AppColors.surface2 : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.pill),
              side: BorderSide(
                  color: on ? AppColors.surface2 : AppColors.border2),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                _setState(() => _termFocus = n);
                _publishTerminals();
              },
              onLongPress: () => _renameTerm(pane.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(pane.title,
                      style:
                          sans(13, color: on ? AppColors.fg1 : AppColors.fg3)),
                  GestureDetector(
                    onTap: () => _closeTerm(pane.id),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon('x', size: 12, color: AppColors.fg4),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _termTabStrip(int focus, {required bool compact}) {
    return SizedBox(
      height: compact ? 30 : 36,
      child: Row(children: [
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(compact ? 8 : 4, 0, 4, 0),
            itemCount: _terms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, n) {
              final on = n == focus;
              final pane = _terms[n];
              return Material(
                color: on ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.xs),
                child: InkWell(
                  onTap: () {
                    _setState(() => _termFocus = n);
                    _publishTerminals();
                  },
                  // Right-click / long-press renames. A dedicated pencil button
                  // per tab would crowd a strip that already carries a close,
                  // and the gesture is discoverable in the tooltip below.
                  onSecondaryTap: () => _renameTerm(pane.id),
                  onLongPress: () => _renameTerm(pane.id),
                  borderRadius: BorderRadius.circular(R.xs),
                  child: Tooltip(
                    message: '${pane.title} — right-click to rename',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 6, 4, 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          pane.title,
                          style: sans(compact ? 12 : 13,
                              weight: on ? W.label : W.body,
                              color: on ? AppColors.fg1 : AppColors.fg3),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: () => _closeTerm(pane.id),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: AppIcon('x',
                                size: compact ? 10 : 12, color: AppColors.fg4),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        IconBtn('plus',
            size: compact ? 28 : 32,
            iconSize: compact ? 13 : 16,
            tooltip: 'New shell',
            onTap: () => _openTerm(fresh: true)),
      ]),
    );
  }

  // macOS keeps this row focused on the active session title. Workspace
  // context and Git actions live in the clickable repository bar above.
  Widget _desktopBar(HarnessState? s, bool running) {
    final mac = kMacOS;
    final title = _title.isEmpty ? 'session' : _title;
    return Container(
      height: mac ? 42 : 50,
      padding: EdgeInsets.symmetric(horizontal: mac ? 16 : 8),
      decoration: BoxDecoration(
        color: mac ? AppColors.surface1 : readingBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (!mac && widget.onMenu != null) ...[
          IconBtn('sidebar',
              size: 30, iconSize: 16, tooltip: 'Sidebar', onTap: widget.onMenu),
          const SizedBox(width: 4),
        ] else if (!mac)
          const SizedBox(width: 2),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  sans(mac ? 13 : 16, weight: W.label, color: AppColors.fg1)),
        ),
        if (s != null && s.lanes.any((l) => l.running))
          _runningLanesBadge(s, const EdgeInsets.symmetric(horizontal: 8)),
        if (mac && running)
          IconBtn('stop',
              size: 30,
              iconSize: 15,
              tooltip: 'Stop',
              onTap: () => _send({'kind': 'interrupt'})),
        if (!mac && running)
          IconBtn('stop',
              size: 32,
              iconSize: 16,
              tooltip: 'Stop',
              onTap: () => _send({'kind': 'interrupt'})),
        if (!mac) ...[
          if (!_isMissionControl)
            IconBtn('terminal',
                size: 32, iconSize: 16, tooltip: 'Shell', onTap: _openTerm),
          if (!_isMissionControl) _menu(s),
        ],
      ]),
    );
  }

  Widget _menu(HarnessState? s) {
    final view = View.of(context);
    final desktop =
        view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
    if (!desktop) {
      return IconBtn('more-vertical',
          tooltip: 'Actions', onTap: () => _openActions(s));
    }
    return PopupMenuButton<VoidCallback>(
      color: AppColors.surface1,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: appMenuShape,
      icon: AppIcon('more-vertical', color: AppColors.fg2),
      tooltip: 'Actions',
      onSelected: (fn) => fn(),
      itemBuilder: (_) => _actionItems(s),
    );
  }

  // Set an autonomous /goal: the agent drives toward it on its own until it's
  // done, you cancel, or it's rate-limited. Sent as a LoopInput over the socket.
  Future<void> _setGoal() async {
    final text = await promptText(context,
        title: 'Set goal',
        hint: 'What should the agent work toward?',
        saveLabel: 'Set goal',
        minLines: 2,
        maxLines: 4);
    final t = text?.trim();
    if (t == null || t.isEmpty) return;
    _toast('Submitting goal…');
    _send({'kind': 'set_goal', 'value': t});
    _toast('Goal set — the agent will drive toward it');
  }

  void _resumeGoal() {
    _send({'kind': 'resume_goal'});
    _toast('Resuming the goal');
  }

  void _cancelGoal() {
    _send({'kind': 'cancel_goal'});
    _toast('Cancelling the goal');
  }

  void _openAutonomy() {
    showAppSheet(context,
        title: 'Autonomous mode',
        maxWidth: 440,
        maxHeight: 680,
        child: AutonomyPanel(client: widget.client, embedded: true));
  }

  void _openRecurring() {
    // Desktop: the shell owns the panes and opens this as a right-pane readout,
    // the same shape Tasks/Lanes/Checkpoints get. A session cannot toggle a pane
    // itself, so it asks. Null on mobile, where there are no panes and the
    // drawer is the right shape for a phone.
    final toPane = widget.onOpenScheduled;
    if (toPane != null && ShellPanelScope.maybeOf(context) == null) {
      toPane();
      return;
    }
    presentScreen(context,
        style: PanelStyle.drawer,
        purpose: ShellPanelPurpose.recurring,
        originClient: widget.client,
        originSessionId: widget.sessionId,
        builder: (_, close) => RecurringScreen(
            client: widget.client,
            onClose: close,
            sessionId: widget.sessionId,
            workspace: _state?.workspace));
  }

  void _setApproval(bool manual) {
    final mode = manual ? 'manual' : 'auto';
    final s = _state;
    if (s != null) {
      _setState(() => _state = s.withApprovalMode(mode));
    }
    _send({'kind': 'set_mode', 'value': mode});
    _toast(manual ? 'Approval: ask' : 'Approval: auto');
  }

  void _performMacAction(String action, [String? extra]) {
    final s = _state;
    switch (action) {
      case 'focus_composer':
        _inputFocus.requestFocus();
        return;
      case 'rename':
        _renameCurrent();
        return;
      case 'model':
        _switchModel(context);
        return;
      case 'goal':
        final text = extra?.trim();
        if (text != null && text.isNotEmpty) {
          _send({'kind': 'set_goal', 'value': text});
          _toast('Goal set — the agent will drive toward it');
        } else if (s?.goal?.ongoing ?? false) {
          _cancelGoal();
        } else {
          _setGoal();
        }
        return;
      case 'resume_goal':
        _resumeGoal();
        return;
      case 'lanes':
        _showLanes();
        return;
      case 'files':
        final ws = s?.workspace ?? '';
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.files,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            maxWidth: 1060,
            maxHeight: 760,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
        return;
      case 'shell':
        if (!_isMissionControl) _openTerm();
        return;
      case 'shell_new':
        if (!_isMissionControl) _openTerm(fresh: true);
        return;
      // Called from the SIDEBAR's terminal panel. Creating a shell is the
      // sidebar's job; showing the resulting pane is the shell's. Kept separate
      // from `shell_new` so the sidebar's + does not depend on the pane's own
      // toggle logic.
      case 'shell_create':
        if (!_isMissionControl) _openTerm(fresh: true);
        return;
      // Destroy a shell. Only the sidebar can do this — the pane may only
      // minimize, so a pty is never lost by collapsing a view.
      case 'shell_close':
        if (extra != null && extra.isNotEmpty) _closeTerm(extra);
        return;
      case 'shell_focus':
        // `extra` is the terminal index, from the shell's terminal panel.
        final i = extra == null ? null : int.tryParse(extra);
        if (i != null) _focusTerm(i);
        return;
      case 'processes':
        presentScreen(context,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.processes,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            builder: (_, close) => ProcessesScreen(
                client: widget.client,
                sessionId: widget.sessionId,
                onClose: close));
        return;
      case 'compact':
        _confirmCompact();
        return;
      case 'checkpoints':
        _showCheckpoints();
        return;
      // Rewind / fork from a checkpoint shown in the shell's right pane. The
      // pane sends the id, so the session resolves it against live state rather
      // than the pane holding a stale Checkpoint copy.
      case 'rewind':
        final cp = _checkpointById(extra);
        if (cp != null) _confirmRewind(cp);
        return;
      case 'fork':
        _confirmFork(_checkpointById(extra));
        return;
    }
  }

  List<PopupMenuEntry<VoidCallback>> _actionItems(HarnessState? s) {
    final manual = (s?.approvalMode ?? 'auto') == 'manual';
    final ws = s?.workspace ?? '';
    PopupMenuItem<VoidCallback> item(String icon, String label, VoidCallback fn,
            {String? value}) =>
        appMenuItem(
          value: fn,
          icon: icon,
          label: label,
          detail: value,
        );
    return [
      if (_isMissionControl) item('activity', 'Autonomous mode', _openAutonomy),
      item('edit', 'Rename session', _renameCurrent),
      item('shield', 'Approval: Auto', () => _setApproval(false),
          value: manual ? null : 'on'),
      item('shield', 'Approval: Ask', () => _setApproval(true),
          value: manual ? 'on' : null),
      (s?.goal?.ongoing ?? false)
          ? (s!.goal!.paused
              ? item('play', 'Resume goal', _resumeGoal, value: 'paused')
              : item('zap', 'Cancel goal', _cancelGoal, value: 'running'))
          : item('zap', 'Set goal', _setGoal),
      if ((s?.lanes.isNotEmpty ?? false))
        item('layers', 'Lanes', _showLanes,
            value: '${s!.lanes.where((l) => l.running).length} running'),
      const PopupMenuDivider(),
      item('terminal', 'Session shell', _openTerm),
      item(
          'git-branch',
          'Git',
          () => presentScreen(context,
              builder: (_, close) => GitScreen(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  onClose: close))),
      item('folder', 'Browse', () {
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.files,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            maxWidth: 1060,
            maxHeight: 760,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
      }),
      item(
          'list',
          'Processes',
          () => presentScreen(context,
              builder: (_, close) => ProcessesScreen(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  onClose: close))),
      item('scheduled', 'Scheduled', _openRecurring),
      const PopupMenuDivider(),
      item('minimize', 'Compact history', _confirmCompact),
      item('history', 'Checkpoints', _showCheckpoints),
    ];
  }

  void _openActions(HarnessState? s) {
    void run(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    showAppSheet(context, title: 'Actions', child: _actionsPanel(s, run));
  }

  /// The action list, shared by the mobile end-drawer and the pull-up sheet so
  /// the two hosts cannot offer different actions. [run] dismisses the host,
  /// then performs the action.
  Widget _actionsPanel(HarnessState? s, void Function(VoidCallback) run,
      {void Function(VoidCallback)? navigate}) {
    navigate ??= run;
    final ws = s?.workspace ?? '';
    return _SessionActionsPanel(
      session: s,
      hideWorkspace: _isMissionControl,
      hideGoal: _isMissionControl,
      hideCheckpoints: _isMissionControl,
      onAutonomy: _isMissionControl ? () => navigate!(_openAutonomy) : null,
      onSetGoal: (text) {
        _send({'kind': 'set_goal', 'value': text});
        _toast('Goal set — the agent will drive toward it');
      },
      onCancelGoal: _cancelGoal,
      onResumeGoal: _resumeGoal,
      onLanes: () => navigate!(_showLanes),
      onGiveWork: _giveWork,
      hideShell: _isMissionControl,
      onTerm: () => run(_openTerm),
      onGit: () => navigate!(() => presentScreen(context,
          builder: (_, close) => GitScreen(
              client: widget.client,
              sessionId: widget.sessionId,
              onClose: close))),
      onFiles: () => navigate!(() {
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            maxWidth: 1060,
            maxHeight: 760,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
      }),
      onProcesses: () => navigate!(() => presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.processes,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => ProcessesScreen(
              client: widget.client,
              sessionId: widget.sessionId,
              onClose: close))),
      onRecurring: () => run(_openRecurring),
      onCompact: () => run(_confirmCompact),
      onCheckpoints: () => navigate!(_showCheckpoints),
    );
  }

  List<Widget> _statusChips(HarnessState? s, bool running) {
    final chips = <Widget>[
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: running ? AppColors.run : AppColors.fg2,
                shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(
            s?.compacting == true
                ? 'Compacting'
                : (running ? 'Running' : 'Idle'),
            style: sans(12,
                weight: W.label,
                color: s?.compacting == true
                    ? AppColors.accent
                    : (running ? AppColors.run : AppColors.fg2))),
      ]),
    ];
    if (s != null && s.workspace.isNotEmpty) {
      chips.add(_StatMeta(
          icon: 'folder',
          label: lastPathSegment(s.workspace, ifEmpty: s.workspace)));
    }
    if (s != null) {
      if (s.totalTokens > 0) {
        chips.add(_StatMeta(icon: 'zap', label: '${fmtSi(s.totalTokens)} tok'));
      }
      // Approval mode and context remaining now live in the composer, so they
      // are deliberately NOT repeated here.
      // Show for any provider that reported limits. An EXPIRED window is
      // skipped rather than printed: its percentage describes the window that
      // already rolled over, so showing it would state a stale figure as fact.
      final rp = s.ratePrimary;
      if (rp != null && !rp.isExpired) {
        chips.add(_StatMeta(
            icon: 'clipboard',
            label:
                '${rateWindowLabel(rp.windowMinutes)} · ${rp.leftPercent.round()}%',
            tone: 'run'));
      }
    }
    return chips;
  }

  Widget _statusStrip(HarnessState? s, bool running) {
    final chips = _statusChips(s, running);
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            chips[i]
          ],
        ]),
      ),
    );
  }

  Widget _disconnectedBanner() {
    if (kMobile) return _mobileDisconnectedBanner();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.dangerBg,
          border: Border(
              bottom:
                  BorderSide(color: AppColors.danger.withValues(alpha: 0.25)))),
      child: Row(children: [
        AppIcon('wifi-off', size: 15, color: AppColors.danger),
        const SizedBox(width: 9),
        Expanded(
            child: Text(
                _outbox.isEmpty
                    ? (_connError ?? 'Disconnected')
                    : '${_connError ?? 'Disconnected'} · ${_outbox.length} message${_outbox.length == 1 ? '' : 's'} will send on reconnect',
                style: sans(12, height: 1.3, color: AppColors.fg1))),
        GestureDetector(
          onTap: () {
            _reconnectAttempt = 0;
            _connect();
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('refresh', size: 13, color: AppColors.danger),
            const SizedBox(width: 5),
            Text('Retry now',
                style: sans(12, weight: W.label, color: AppColors.danger)),
          ]),
        ),
      ]),
    );
  }

  Widget _mobileDisconnectedBanner() {
    final text = _outbox.isEmpty
        ? (_connError ?? 'Disconnected')
        : '${_connError ?? 'Disconnected'} · ${_outbox.length} message${_outbox.length == 1 ? '' : 's'} will send on reconnect';
    return Padding(
      padding: const EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          AppIcon('wifi-off', size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(13, height: 18 / 13, color: AppColors.fg1)),
          ),
          TextButton(
            onPressed: () {
              _reconnectAttempt = 0;
              _connect();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text('Retry', style: sans(13, color: AppColors.danger)),
          ),
        ]),
      ),
    );
  }

  /// Open the full-screen actions panel (slides in from the right).
  ///
  /// Dismisses the keyboard first: the panel is a navigation surface, and a
  /// composer keyboard left open underneath makes the slide look broken.
  void _openActionsDrawer(HarnessState? s) {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// The phone's action list as a FULL-SCREEN panel entering from the right.
  ///
  /// Full width rather than a 320px drawer: the actions carry descriptions and
  /// expandable forms (goal, lanes), which a narrow drawer squeezes into
  /// ellipsis. The right edge distinguishes it from the Chats panel on the left.
  Widget _actionsDrawer(HarnessState? s) {
    // Closing the drawer dismisses the host, then runs the action — the drawer
    // is not a route, so `Navigator.pop` (what the sheet uses) would not close
    // it and the action would fire behind an open panel.
    void run(VoidCallback f) {
      _scaffoldKey.currentState?.closeEndDrawer();
      f();
    }

    final title = _title.isEmpty ? 'Session' : _title;
    return Drawer(
      width: MediaQuery.sizeOf(context).width,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                IconBtn('x',
                    size: M.minTarget,
                    iconSize: 20,
                    tooltip: 'Close',
                    onTap: () => _scaffoldKey.currentState?.closeEndDrawer()),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(M.gutter + 8, 0, M.gutter, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Actions',
                      style: sans(12, weight: W.strong, color: AppColors.fg4)),
                  const SizedBox(height: 2),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(26,
                          weight: FontWeight.w700,
                          spacing: -0.7,
                          height: 31 / 26,
                          color: AppColors.fg1)),
                  if (s != null) ...[
                    const SizedBox(height: 6),
                    _headerStatusLine(s),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter,
                    28 + MediaQuery.paddingOf(context).bottom),
                child: _actionsPanel(s, run, navigate: (action) => action()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
