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
        if (kMobile || Navigator.of(context).canPop())
          IconBtn('chevron-left',
              size: kMobile ? M.minTarget : 32,
              iconSize: 20,
              tooltip: 'Back',
              onTap: () => Navigator.of(context).maybePop())
        else
          const SizedBox(width: 6),
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

  void _openPullRequests() {
    final status = _github;
    if (status == null) return;
    final reveal = widget.onShowPullRequests;
    if (reveal != null) {
      reveal(status);
      return;
    }
    openPullRequests(context,
        client: widget.client, session: widget.sessionId, status: status);
  }

  void _openDeliverables() {
    final files = <({String path, String caption})>[
      for (final e in _state?.events ?? const <Map<String, dynamic>>[])
        if (e['kind'] == 'file_presented')
          (
            path: e['path']?.toString() ?? '',
            caption: e['caption']?.toString() ?? ''
          ),
    ];
    if (kMobile) {
      showArtifactSheet(
          context,
          (close) => SessionDeliverables(
                client: widget.client,
                session: widget.sessionId,
                files: files,
                onOpenFileTab: widget.onOpenFileTab,
                onClose: close,
              ));
      return;
    }
    presentScreen(context,
        style: PanelStyle.drawer,
        maxWidth: 560,
        purpose: ShellPanelPurpose.deliverables,
        originClient: widget.client,
        originSessionId: widget.sessionId,
        builder: (_, close) => SessionDeliverables(
              client: widget.client,
              session: widget.sessionId,
              files: files,
              onOpenFileTab: widget.onOpenFileTab,
              onClose: close,
            ));
  }

  Widget _mobileHeader(HarnessState? s) {
    final ws = s?.workspace.trim() ?? '';
    final folder = ws.isEmpty ? '' : lastPathSegment(ws, ifEmpty: ws);
    final sub = [
      if (folder.isNotEmpty) folder,
      if ((_modelLabel ?? '').isNotEmpty) _modelLabel!,
    ].join(' · ');
    return MobileBackBar(
      title: _title.isEmpty ? 'Session' : _title,
      subtitle: sub,
      onBack: widget.onMenu ?? () => Navigator.maybePop(context),
      onTitleTap: () => _openActionsDrawer(s),
      trailing: [
        if (s != null && s.lanes.any((l) => l.running)) ...[
          RoundBtn(
            tooltip: 'Parallel agents',
            onTap: _showLanes,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const WorkingMochi(size: 15),
              Text('${s.lanes.where((l) => l.running).length}',
                  style: sans(10.5, weight: W.label, height: 1.1, color: AppColors.fg2)),
            ]),
          ),
          const SizedBox(width: 8),
        ],
        if (!_isMissionControl)
          RoundBtn(icon: 'terminal', tooltip: 'Shell', onTap: _openTerm),
      ],
    );
  }

  bool get _hasTermDock => !kMobile && !_isMissionControl && !widget.readOnly;

  Widget _withTermDock(Widget chat) {
    if (!_hasTermDock) return chat;
    final open = _termOpen && _terms.isNotEmpty;
    return LayoutBuilder(builder: (context, box) {
      final maxH = (box.maxHeight - 120).clamp(120.0, double.infinity);
      final height = !open
          ? 0.0
          : _termMax
              ? box.maxHeight
              : _termHeight.clamp(120.0, maxH);
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _termMax ? 0 : height,
          child: chat,
        ),
        if (open)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: _desktopTermDock(maxH),
          ),
      ]);
    });
  }

  Widget _desktopTermDock(double maxH) {
    final i = _termFocus.clamp(0, _terms.length - 1);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 36,
            child: Row(children: [
              Expanded(child: _termTabStrip(i)),
              _dockAction('plus', 'New terminal', () => _openTerm(fresh: true)),
              _dockAction(
                  _termMax ? 'shrink' : 'expand',
                  _termMax ? 'Restore' : 'Maximize',
                  () => _setState(() => _termMax = !_termMax)),
              _dockAction('chevron-down', 'Hide terminal', () {
                _setState(() {
                  _termOpen = false;
                  _termMax = false;
                });
                _publishTerminals();
              }),
              const SizedBox(width: 8),
            ]),
          ),
          Expanded(
            child: SessionTermView(
              key: ValueKey('dock-term-${_terms[i].id}'),
              alive: _terms[i].alive,
              terminal: _terms[i].terminal,
              onInput: _termIn,
              onResize: _termResize,
              onClose: () => _closeTerm(_terms[i].id),
              mobileKeys: false,
              showChrome: false,
              flat: true,
            ),
          ),
        ]),
        if (!_termMax)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => _setState(() {
                  _termHeight = (_termHeight - d.delta.dy).clamp(120.0, maxH);
                }),
                onDoubleTap: () => _setState(() => _termMax = true),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _dockAction(String icon, String tooltip, VoidCallback onTap) =>
      IconBtn(icon, size: 26, iconSize: 13, tooltip: tooltip, onTap: onTap);

  Widget _mobileTermTab() {
    final i = _termFocus.clamp(0, _terms.length - 1);
    final t = _terms[i];
    return Material(
      color: AppColors.canvas,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MobileBackBar(
          title: _terms.length > 1 ? 'Shell ${i + 1}' : 'Shell',
          subtitle: t.alive ? null : 'Starting…',
          onBack: () => _setState(() => _termOpen = false),
          trailing: [
            RoundBtn(
                icon: 'plus',
                tooltip: 'New shell',
                onTap: () => _openTerm(fresh: true)),
          ],
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

  Widget _termTabStrip(int focus) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 10, right: 8),
      itemCount: _terms.length,
      separatorBuilder: (_, __) => const SizedBox(width: 2),
      itemBuilder: (_, n) {
        final pane = _terms[n];
        return _DockTab(
          title: pane.title,
          alive: pane.alive,
          selected: n == focus,
          onTap: () {
            _setState(() => _termFocus = n);
            _publishTerminals();
          },
          onRename: () => _renameTerm(pane.id),
          onClose: () => _closeTerm(pane.id),
        );
      },
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
        if (!mac && !_isMissionControl) _menu(s),
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
    if (!kMobile) {
      presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.autonomy,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => AutonomyPanel(client: widget.client));
      return;
    }
    showAppSheet(context,
        title: 'Automated wakes',
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
        _switchModel(_modelChipKey.currentContext ?? context);
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
      case 'actions':
        _openActions(_state);
        return;
      case 'autonomy':
        if (_isMissionControl) _openAutonomy();
        return;
      case 'pull_requests':
        final status = _github;
        if (status == null) {
          _toast('Pull requests need the GitHub CLI signed in for this repo');
          return;
        }
        final number = int.tryParse(extra ?? '');
        if (number != null && widget.onShowPullRequests == null) {
          openPullRequest(context,
              client: widget.client,
              session: widget.sessionId,
              status: status,
              number: number);
        } else {
          _openPullRequests();
        }
        return;
      case 'artifacts':
        _openDeliverables();
        return;
      case 'artifact':
        if (extra != null && extra.isNotEmpty) {
          openArtifact(context,
              client: widget.client, session: widget.sessionId, id: extra);
        }
        return;
      case 'task':
        if (extra != null && extra.isNotEmpty) {
          openTaskDetail(context, widget.client, extra);
        }
        return;
      case 'file_changes':
        final steps = sessionChangeSteps(_state?.events ?? const []);
        if (kMobile) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FileChangesScreen(steps: steps)));
        } else {
          presentScreen<void>(context,
              maxWidth: 760,
              maxHeight: 640,
              builder: (_, close) => FileChangesScreen(steps: steps));
        }
        return;
      case 'memory':
        if (!kMobile) {
          presentScreen(context,
              style: PanelStyle.drawer,
              maxWidth: 560,
              purpose: ShellPanelPurpose.memory,
              originClient: widget.client,
              originSessionId: widget.sessionId,
              builder: (_, close) => DeskMemoryView(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  workspace: _state?.workspace));
          return;
        }
        presentScreen(context,
            builder: (_, close) => MemoryScreen(
                client: widget.client,
                embedded: true,
                onBack: close));
        return;
      case 'recurring':
        _openRecurring();
        return;
      case 'approval':
        _setApproval(extra == 'ask');
        return;
      case 'git':
        presentScreen(context,
            builder: (_, close) => GitScreen(
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

  Widget _contextMeter(int used, int win) {
    final frac = (used / win).clamp(0.0, 1.0);
    String k(int v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Context', style: sans(12.5, color: AppColors.fg2))),
          Text('${k(used)} / ${k(win)}', style: mono(11, color: AppColors.fg4)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 24; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < (frac * 24).round()
                    ? (frac > 0.8 ? AppColors.danger : AppColors.fg3)
                    : AppColors.line,
              ),
            ),
        ]),
      ]),
    );
  }

  List<PopupMenuEntry<VoidCallback>> _actionItems(HarnessState? s) {
    final ws = s?.workspace ?? '';
    PopupMenuItem<VoidCallback> item(String icon, String label, VoidCallback fn,
            {String? value}) =>
        appMenuItem(
          value: fn,
          icon: icon,
          label: label,
          detail: value,
        );
    final win = s?.contextWindow ?? 0;
    final used = s?.lastPromptTokens ?? 0;
    return [
      if (win > 0 && used > 0) ...[
        PopupMenuItem<VoidCallback>(
          enabled: false,
          height: 64,
          child: _contextMeter(used, win),
        ),
        const PopupMenuDivider(),
      ],
      if (_isMissionControl) item('activity', 'Automated wakes', _openAutonomy),
      item('edit', 'Rename session', _renameCurrent),
      (s?.goal?.ongoing ?? false)
          ? (s!.goal!.paused
              ? item('play', 'Resume goal', _resumeGoal, value: 'paused')
              : item('goal', 'Cancel goal', _cancelGoal, value: 'running'))
          : item('goal', 'Set goal', _setGoal),
      if ((s?.lanes.isNotEmpty ?? false))
        item('layers', 'Lanes', _showLanes,
            value: '${s!.lanes.where((l) => l.running).length} running'),
      const PopupMenuDivider(),
      item(
          'git-branch',
          'Git',
          () => presentScreen(context,
              builder: (_, close) => GitScreen(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  onClose: close))),
      item('layers', 'Artifacts & files', _openDeliverables),
      if (_github != null)
        item('git-branch', 'Pull requests', _openPullRequests),
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

    showAppSheet(context,
        title: 'Actions',
        maxWidth: 420,
        maxHeight: 680,
        child: _actionsPanel(s, run));
  }

  /// The action list, shared by the mobile end-drawer and the pull-up sheet so
  /// the two hosts cannot offer different actions. [run] dismisses the host,
  /// then performs the action.
  Widget _actionsPanel(HarnessState? s, void Function(VoidCallback) run,
      {void Function(VoidCallback)? navigate}) {
    navigate ??= run;
    final ws = s?.workspace ?? '';
    final changeSteps = sessionChangeSteps(s?.events ?? const []);
    return _SessionActionsPanel(
      session: s,
      fileChangeCount: fileChanges(changeSteps).length,
      onFileChanges: () => navigate!(() => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => FileChangesScreen(steps: changeSteps)))),
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
      onDeliverables: () => navigate!(_openDeliverables),
      onPullRequests:
          _github == null ? null : () => navigate!(_openPullRequests),
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
      onMemory: () => navigate!(() => presentScreen(context,
          builder: (_, close) => MemoryScreen(
              client: widget.client,
              embedded: true,
              onBack: close))),
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
        chips.add(_StatMeta(icon: 'activity', label: '${fmtSi(s.totalTokens)} tok'));
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
            MobileBackBar(
              title: title,
              subtitle: 'Actions',
              onTitleTap: () {},
            ),
            const SizedBox(height: 8),
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

class _DockTab extends StatefulWidget {
  const _DockTab({
    required this.title,
    required this.alive,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onClose,
  });

  final String title;
  final bool alive;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onClose;

  @override
  State<_DockTab> createState() => _DockTabState();
}

class _DockTabState extends State<_DockTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    final fg = on || _hover ? AppColors.fg1 : AppColors.fg3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onRename,
        onDoubleTap: widget.onRename,
        child: Tooltip(
          message: 'Double-click to rename',
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 1.5,
                  color: on ? AppColors.fg2 : Colors.transparent,
                ),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('terminal',
                  size: 12, color: on ? AppColors.fg2 : AppColors.fg4),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: sans(12.5, weight: on ? W.label : W.body, color: fg)),
              if (!widget.alive) ...[
                const SizedBox(width: 6),
                Text('exited', style: sans(11, color: AppColors.fg4)),
              ],
              SizedBox(
                width: 20,
                child: on || _hover
                    ? GestureDetector(
                        onTap: widget.onClose,
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AppIcon('x', size: 10, color: AppColors.fg3),
                        ),
                      )
                    : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
