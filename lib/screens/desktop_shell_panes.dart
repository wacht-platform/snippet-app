part of 'desktop_shell.dart';

extension _DesktopShellPanesExt on _DesktopShellState {
  Widget _tabBody(_ShellTab t, {required bool primary}) {
    if (t.isTerminal) {
      if (t.termSessionKey == null) {
        final s = _shells.byId(t.termId!);
        if (s == null) return _emptyPaneHint();
        return SessionTermView(
          key: ValueKey('shell-${t.termId}'),
          alive: s.alive,
          terminal: s.terminal,
          onInput: (bytes) => _shells.write(s.id, bytes),
          onResize: (cols, rows) => _shells.resize(s.id, cols, rows),
          onClose: () => _closePaneTab(t),
          mobileKeys: kMobile,
          showChrome: false,
        );
      }
      final host = _termHosts[t.termSessionKey];
      if (host == null || !host.terms.any((x) => x.id == t.termId)) {
        return _emptyPaneHint();
      }
      return host.buildView(t.termId!, mobileKeys: kMobile);
    }
    if (t.isDiff) {
      return GitFileDiffView(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        sessionId: t.sessionId ?? '',
        file: t.diffPath!,
        staged: t.diffStaged,
        untracked: t.diffUntracked,
        embedded: true,
      );
    }
    if (t.isFile) {
      return FileViewer(
        key: ValueKey('body-${t.key}'),
        client: t.client,
        path: t.filePath!,
        name: t.title,
        embedded: true,
        onClose: primary ? () => _closeTabByKey(t.key) : null,
      );
    }
    return SessionScreen(
      key: ValueKey('body-${t.key}'),
      client: t.client,
      sessionId: t.sessionId!,
      title: t.title,
      profile: t.profile,
      embedded: true,
      inboundShare: primary ? t.inboundShare : null,
      onShareConsumed: !primary || t.inboundShare == null
          ? null
          : () => _setState(() => t.inboundShare = null),
      acceptDrops: primary,
      mobileActive: !kMobile || !_mobileChatsOpen,
      onTitle: (title) => _onSessionTitle(t.sessionId!, title),
      onMenu: kMobile ? _showMobileChats : null,
      onOpenFileTab: (path, name) =>
          _openFileTab(t.client, t.instanceUrl, path, name),
      onOpenSession: _openSession,
      onMacStatus: (state, running) =>
          _setMacSessionStatus(t.key, state, running),
      onMacControls: !kMobile
          ? (stop, performAction) =>
              _setMacSessionControls(t.key, stop, performAction)
          : null,
      onTerminalHost:
          !kMobile ? (host, open) => _setTerminalHost(t.key, host, open) : null,
      onOpenScheduled:
          !kMobile ? () => _toggleRightPanel(_RightPanel.recurring) : null,
    );
  }

  bool _isAuxiliary(_ShellTab t) => t.isTerminal || t.isFile || t.isDiff;

  List<_ShellTab> get _mainTabs => [
        for (final t in _tabs)
          if (!_isAuxiliary(t)) t,
      ];

  String? _groupRootFor(_Pane p) {
    final stored = _groupRootKey[p];
    if (stored != null && _tabs.any((t) => t.key == stored && t.pane == p)) {
      return stored;
    }
    final active = _activeTab;
    return active != null && active.pane == p ? active.key : null;
  }

  List<_ShellTab> _tabsIn(_Pane p) {
    final root = _groupRootFor(p);
    return [
      for (final t in _tabs)
        if (t.pane == p &&
            !_hiddenTabs.contains(t.key) &&
            paneTabBelongsInGroup(
              rootKey: root,
              tabKey: t.key,
              groupSessionKey: t.groupSessionKey,
              isAuxiliary: _isAuxiliary(t),
            ))
          t,
    ];
  }

  String? _activeGroupKeyFor(_Pane p) =>
      _groupRootFor(p) ?? (_activeTab?.pane == p ? _activeTab?.key : null);

  _Pane get _focusedPane {
    if (_rightCollapsed) return _Pane.left;
    if (_activePane == _Pane.right) {
      final rightHasContent = _tabsIn(_Pane.right).isNotEmpty ||
          _rightTabs.any((r) => r.pane == _Pane.right);
      if (rightHasContent) return _Pane.right;
    }
    return _activeTab?.pane ?? _Pane.left;
  }

  void _activateIn(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _setState(() {
      _activePane = p;
      _activeKey[p] = tab.key;
      final root =
          _isAuxiliary(tab) ? tab.groupSessionKey ?? _groupRootFor(p) : tab.key;
      if (root != null) _groupRootKey[p] = root;
      if (!_isAuxiliary(tab)) _activeIndex = i;
    });
    _persistTabs();
    _syncPage();
  }

  void _moveTo(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    if (tab.pane == p) return;
    final targetRoot = _groupRootFor(p);
    _setState(() {
      _activePane = p;
      tab.pane = p;
      if (!_isAuxiliary(tab)) _activeIndex = i;
      if (_isAuxiliary(tab)) {
        if (targetRoot != null) {
          tab.groupSessionKey = targetRoot;
          _groupRootKey[p] = targetRoot;
        } else {
          _groupRootKey[p] = tab.groupSessionKey ?? tab.key;
        }
      } else {
        _groupRootKey[p] = tab.key;
        tab.groupSessionKey = null;
      }
      _dockAux(p, tab.key);
    });
    _persistTabs();
  }

  void _dockAux(_Pane p, String key) {
    _activePane = p;
    _activeKey[p] = key;
    if (p == _Pane.right) {
      _rightCollapsed = false;
    }
  }

  void _closePaneTab(_ShellTab t) {
    final pane = t.pane;
    final tabs = _tabsIn(pane);
    final idx = tabs.indexOf(t);
    String? nextKey;
    if (idx >= 0) {
      if (idx + 1 < tabs.length) {
        nextKey = tabs[idx + 1].key;
      } else if (idx - 1 >= 0) {
        nextKey = tabs[idx - 1].key;
      }
    }
    final i = _tabs.indexOf(t);
    if (i >= 0) {
      _closeTab(i);
      if (nextKey != null && mounted) {
        final key = nextKey;
        _setState(() => _activeKey[pane] = key);
      }
    }
  }

  void _closeTabAt(_ShellTab t, {bool force = false}) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _closeTab(i, force: force);
  }

  Widget _bodyRow({required bool topInset}) => ShellSplitView(
        sidebar: _sidebar(topInset: topInset),
        paneWidth: _paneWidth,
        leftCollapsed: _leftCollapsed,
        rightCollapsed: _rightCollapsed,
        leftTabs: _tabsIn(_Pane.left),
        rightTabs: _tabsIn(_Pane.right),
        readouts: _rightTabs,
        activeKey: _activeKey,
        focusedPane: _focusedPane,
        statusForTab: _statusForTab,
        canCloseTab: (t) => _canCloseTab(t) || t.isTerminal,
        tabBodyBuilder: (t, primary) => _tabBody(t, primary: primary),
        readoutBodyBuilder: (r) {
          final tab = _activeTab;
          final controls = tab == null ? null : _macSessionControls[tab.key];
          final s = tab == null ? null : _macSessionStatuses[tab.key]?.state;
          return _rightTabBody(r, s, controls);
        },
        fallbackBuilder: _paneFallback,
        onPaneResize: (delta) => _setState(() {
          final max = MediaQuery.sizeOf(context).width * 0.72;
          _paneWidth = (_paneWidth - delta).clamp(kPaneMinWidth, max);
        }),
        onExpandPane: (p) => _setState(() {
          if (p == _Pane.left) {
            _leftCollapsed = false;
          } else {
            _rightCollapsed = false;
          }
        }),
        onMoveTab: _moveTo,
        onMoveReadout: _moveReadout,
        onActivateTab: _activateIn,
        onActivateReadout: (p, r) => _setState(() => _activeKey[p] = r.key),
        onDismissTab: (p, t) {
          if (t.isTerminal) {
            _hideTabView(p, t);
          } else {
            _closePaneTab(t);
          }
        },
        onCloseReadout: (r) => _closeRightTab(r.key),
      );

  void _moveReadout(_Pane p, _RightTab r) {
    if (r.pane == p) return;
    _setState(() {
      final from = r.pane;
      r.pane = p;
      _rightCollapsed = false;
      if (_activeKey[from] == r.key) _activeKey.remove(from);
      _activeKey[p] = r.key;
    });
  }

  Widget _paneFallback(_Pane p) {
    if (p == _Pane.right) return _emptyPaneHint();
    return _client == null ? _welcome() : _recentPlaceholder();
  }

  void _newGlobalShell() {
    final root = _activeTab;
    if (root == null) return;
    final s = _shells.create();
    _setState(() {
      _tabs.add(_ShellTab.terminal(
        client: root.client,
        instanceUrl: root.instanceUrl,
        termId: s.id,
        termSessionKey: null,
        title: s.title,
        pane: root.pane,
        groupSessionKey: root.key,
      ));
      _groupRootKey[root.pane] = root.key;
      _activeKey[root.pane] = _tabs.last.key;
    });
    _persistTabs();
  }

  void _focusGlobalShell(String id) {
    _shells.focus(id);
    for (final t in _tabs) {
      if (t.isTerminal && t.termSessionKey == null && t.termId == id) {
        final root = _tabs.firstWhere(
          (candidate) => candidate.key == t.groupSessionKey,
          orElse: () => t,
        );
        final i = _tabs.indexOf(root);
        _setState(() {
          if (!_isAuxiliary(root) && i >= 0) _activeIndex = i;
          _hiddenTabs.remove(t.key);
          _groupRootKey[t.pane] = root.key;
          _activeKey[t.pane] = t.key;
        });
        _syncPage();
        return;
      }
    }
  }

  void _closeGlobalShell(String id) {
    _shells.close(id);
    _syncGlobalShellTabs();
  }

  void _syncGlobalShellTabs() {
    if (!mounted) return;
    final live = {for (final s in _shells.shells) s.id: s};
    var changed = false;
    _setState(() {
      final seen = <String>{};
      _tabs.removeWhere((t) {
        if (!t.isTerminal || t.termSessionKey != null) return false;
        final id = t.termId!;
        final duplicate = !seen.add(id);
        final stale = !live.containsKey(id);
        if (!duplicate && !stale) return false;
        _activeKey.removeWhere((_, key) => key == t.key);
        _hiddenTabs.remove(t.key);
        changed = true;
        return true;
      });

      final owner = _activeTab;
      if (owner != null) {
        for (final s in live.values) {
          if (seen.contains(s.id)) continue;
          _tabs.add(_ShellTab.terminal(
            client: owner.client,
            instanceUrl: owner.instanceUrl,
            termId: s.id,
            termSessionKey: null,
            title: s.title,
            pane: owner.pane,
            groupSessionKey: owner.key,
          ));
          seen.add(s.id);
          changed = true;
        }
      }
      for (final t in _tabs) {
        if (t.isTerminal && t.termSessionKey == null) {
          final s = live[t.termId];
          if (s != null && s.title != t.title) {
            t.title = s.title;
            changed = true;
          }
        }
      }
      _normalizeActiveIndex();
    });
    if (changed) _persistTabs();
  }

  void _hideTabView(_Pane p, _ShellTab t) {
    _setState(() {
      _hiddenTabs.add(t.key);
      if (_activeKey[p] == t.key) {
        _activeKey.remove(p);
      }
    });
    _persistTabs();
  }

  Widget _emptyPaneHint() => const EmptyPaneHint();

  Widget _rightTabBody(
    _RightTab t,
    HarnessState? s,
    _MacSessionControls? controls,
  ) =>
      RightTabBody(
        tab: t,
        state: s,
        controls: controls,
        client: _client,
        activeSessionId: _activeTab?.sessionId,
      );

  Widget _mainPane({VoidCallback? onMenu}) => MainPaneView(
        client: _client,
        tabs: _tabs,
        activeIndex: _activeIndex,
        pageController: _pageController,
        onPageChanged: (i) {
          _setState(() => _activeIndex = i);
          _persistTabs();
          _scrollStripToActive();
          _refreshMacGit();
        },
        tabBodyBuilder: (t, primary) => _tabBody(t, primary: primary),
        welcomeView: _welcome(),
        recentPlaceholder: _recentPlaceholder(),
        tabStrip: _tabStrip(onMenu),
        onMenu: onMenu,
      );

  void _openShellSettings() {
    final c = _client;
    if (c == null) return;
    final inst = _active;
    presentScreen(context,
        maxWidth: 860,
        maxHeight: 600,
        builder: (_, close) => _SettingsPanel(
              client: c,
              instances: _instances,
              active: inst,
              onRemove: _removeInstance,
              onRename: _renameInstance,
              onSelect: _selectInstance,
              onAdd: _onInstanceAdded,
              onClose: close,
            ));
  }

  Widget _tabStrip(VoidCallback? onMenu) => CardTabStrip(
        controller: _stripController,
        tabs: _tabs,
        activeIndex: _activeIndex,
        onMenu: onMenu,
        subtitleForTab: _tabSubtitle,
        canCloseTab: _canCloseTab,
        onActivateTab: _activateTab,
        onTabMenu: _tabMenu,
        onCloseTab: _closeTab,
        onNewTab: _newSessionFlow,
        isFileActive: _activeTab?.isFile == true,
        onDownloadFile: _downloadActiveFile,
        onEditFile: _editActiveFile,
        chipKeyFor: (key) => _chipKeys.putIfAbsent(key, () => GlobalKey()),
      );

  String _tabSubtitle(_ShellTab t) {
    if (t.isFile) {
      final path = t.filePath ?? '';
      final slash = path.lastIndexOf('/');
      final parent = slash > 0 ? path.substring(0, slash) : '';
      return lastPathSegment(parent, ifEmpty: 'file');
    }
    if (t.isMissionControl) return 'orchestration';
    return _macRepositoryLabel();
  }

  Widget _recentPlaceholder() => ShellRecentPlaceholder(
        sessions: _sessions,
        sessionsLoading: _sessionsLoading,
        onOpenSession: _openSession,
      );

  Widget _welcome() => ShellWelcomeView(onAddInstance: _addInstanceFlow);

  Future<void> _addInstanceFlow() async {
    final inst = kMobile
        ? await showModal<Instance>(context, const AddInstanceScreen(),
            width: 480, height: 520)
        : await showAddMachineDialog(context);
    if (inst != null) await _onInstanceAdded(inst);
  }

  Future<void> _renameInstance(Instance inst, String name) async {
    final items = _instances
        .map((e) => e.url == inst.url
            ? Instance(name: name, url: e.url, token: e.token)
            : e)
        .toList();
    await _store.save(items);
    if (!mounted) return;
    _setState(() {
      _instances = items;
      if (_active?.url == inst.url) {
        _active = items.firstWhere((e) => e.url == inst.url);
      }
    });
  }

  Future<void> _onInstanceAdded(Instance inst) async {
    final items = [..._instances]..removeWhere((e) => e.url == inst.url);
    items.add(inst);
    await _store.save(items);
    if (!mounted) return;
    _setState(() => _instances = items);
    _selectInstance(inst);
    _refreshHealth();
  }

  Future<void> _removeInstance(Instance inst) async {
    final items = [..._instances]..removeWhere((e) => e.url == inst.url);
    await _store.save(items);
    if (!mounted) return;
    _setState(() {
      _instances = items;
      for (final tab in _tabs.where((t) => t.instanceUrl == inst.url)) {
        _clearTabState(tab.key);
      }
      _tabs.removeWhere((t) => t.instanceUrl == inst.url);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_active?.url == inst.url) {
        _active = items.isNotEmpty ? items.first : null;
        _client =
            _active != null ? DaemonClient(_active!.url, _active!.token) : null;
        _liveStatus.clear();
      }
    });
    _ensurePinnedMissionControl();
    _connectEventsWatch();
    _syncPage();
  }

  Widget _macWindowBar() => MacWindowBar(
        canNavigateBack: _canNavigateBack,
        canNavigateForward: _canNavigateForward,
        onNavigateBack: _navigateBack,
        onNavigateForward: _navigateForward,
        tabsRow: _mainTabsRow(),
        onOpenSettings: _openShellSettings,
        machineSwitcher: _topMachineSwitcher(),
      );

  Widget _topMachineSwitcher() => TopMachineSwitcher(
        active: _active,
        isHealthy: _active == null ? null : _health[_active!.url],
        hasInstances: _instances.isNotEmpty,
        onAdd: _addInstanceFlow,
        onOpenList: _openTopMachines,
        anchorKey: _topMachineKey,
      );

  Future<void> _openTopMachines() async {
    _refreshHealth();
    await showTopMachinesPopover(
      context: context,
      anchorKey: _topMachineKey,
      content: _MachineList(
        instances: _instances,
        active: _active,
        health: _health,
        onSelect: _selectInstance,
        onAdd: _addInstanceFlow,
        onManage: _manageMachine,
      ),
    );
  }

  void _manageMachine(Instance i) => showManageMachineSheet(
        context: context,
        instance: i,
        onRename: _renameInstance,
        onRemove: _removeInstance,
      );
}
