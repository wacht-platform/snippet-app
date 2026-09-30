part of 'desktop_shell.dart';

extension _DesktopShellTabsExt on _DesktopShellState {
  void _scrollStripToActive() {
    final t = _activeTab;
    if (t == null) return;
    final ctx = _chipKeys[t.key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.5,
          duration: Motion.base,
          curve: Motion.enter);
    }
  }

  void _persistTabs() {
    _persistTabsDebounce?.cancel();
    _persistTabsDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _store.saveOpenTabs(
        _tabs
            .map((t) => OpenTabDescriptor(
                  instanceUrl: t.instanceUrl,
                  sessionId: t.sessionId,
                  filePath: t.filePath,
                  title: t.title,
                  profile: t.profile,
                  diffPath: t.diffPath,
                  diffStaged: t.diffStaged,
                  diffUntracked: t.diffUntracked,
                  pane: t.pane.name,
                  groupSessionKey: t.groupSessionKey,
                  termSessionKey: t.termSessionKey,
                  termId: t.termId,
                  board: t.isBoard,
                ))
            .toList(),
        _activeIndex,
      );
    });
  }

  Future<void> _restoreTabs(List<Instance> instances) async {
    final saved = await _store.loadOpenTabs();
    if (!mounted || saved.tabs.isEmpty) return;
    final byUrl = {for (final inst in instances) inst.url: inst};
    final restored = <_ShellTab>[];
    for (final descriptor in saved.tabs) {
      final inst = byUrl[descriptor.instanceUrl];
      if (inst == null) continue;
      final client = DaemonClient(inst.url, inst.token);
      final pane =
          descriptor.pane == _Pane.right.name ? _Pane.right : _Pane.left;
      if (!shouldRestoreShellTab(descriptor, mobile: kMobile)) {
        continue;
      } else if (descriptor.board) {
        restored.add(_ShellTab.board(
          client: client,
          instanceUrl: inst.url,
          pane: pane,
          groupSessionKey: descriptor.groupSessionKey,
        ));
      } else if (descriptor.isDiff) {
        restored.add(_ShellTab.diff(
          client: client,
          instanceUrl: inst.url,
          sessionId: descriptor.sessionId,
          diffPath: descriptor.diffPath!,
          title: descriptor.title,
          diffStaged: descriptor.diffStaged,
          diffUntracked: descriptor.diffUntracked,
          pane: pane,
          groupSessionKey: descriptor.groupSessionKey,
        ));
      } else if (descriptor.isFile) {
        restored.add(_ShellTab.file(
          client: client,
          instanceUrl: inst.url,
          filePath: descriptor.filePath!,
          title: descriptor.title,
          pane: pane,
          groupSessionKey: descriptor.groupSessionKey,
        ));
      } else if (descriptor.sessionId != null) {
        final mc = isMissionControlTab(
            sessionId: descriptor.sessionId, title: descriptor.title);
        if (mc &&
            restored
                .any((t) => t.isMissionControl && t.instanceUrl == inst.url)) {
          continue;
        }
        restored.add(_ShellTab.session(
          client: client,
          instanceUrl: inst.url,
          sessionId: mc ? 'mission-control' : descriptor.sessionId,
          title: mc ? 'Mission Control' : descriptor.title,
          profile: descriptor.profile,
          pane: pane,
          groupSessionKey: descriptor.groupSessionKey,
        ));
      }
    }
    if (!mounted) return;
    _setState(() {
      if (restored.isNotEmpty) {
        _tabs
          ..clear()
          ..addAll(restored);
        _activeIndex = saved.activeIndex.clamp(0, restored.length - 1);
        _normalizeActiveIndex();
        final active = _activeIndex >= 0 ? _tabs[_activeIndex] : null;
        _active = active == null ? null : byUrl[active.instanceUrl];
        _client =
            _active == null ? null : DaemonClient(_active!.url, _active!.token);
      }
    });
    _ensurePinnedMissionControl();
    _persistTabs();
    _syncPage();
  }

  _ShellTab _mcTabFor(Instance inst) => _ShellTab.session(
        client: DaemonClient(inst.url, inst.token),
        instanceUrl: inst.url,
        sessionId: 'mission-control',
        title: 'Mission Control',
      );

  void _ensurePinnedMissionControl() {
    final inst = _active;
    final client = _client;
    if (inst == null) return;
    if (client != null) unawaited(client.mcOpen().catchError((_) => ''));
    var same = 0;
    var foreign = 0;
    var extras = 0;
    var leftover = false;
    for (final t in _tabs) {
      if (!t.isMissionControl) continue;
      if (t.instanceUrl != inst.url) {
        foreign++;
        continue;
      }
      if (same == 0) {
        leftover =
            !isDedicatedMcSession(t.sessionId) || t.title != 'Mission Control';
      } else {
        extras++;
      }
      same++;
    }
    final alreadyPinned = same == 1 &&
        extras == 0 &&
        foreign == 0 &&
        !leftover &&
        _tabs.isNotEmpty &&
        _tabs.first.isMissionControl &&
        _tabs.first.instanceUrl == inst.url;
    if (alreadyPinned) {
      if (_activeIndex < 0) {
        _setState(() => _activeIndex = 0);
        _persistTabs();
        _syncPage();
      }
      return;
    }
    if (foreign > 0 || extras > 0 || leftover) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _setState(() {
      final activeKey = (_activeIndex >= 0 && _activeIndex < _tabs.length)
          ? _tabs[_activeIndex].key
          : null;
      SharedInbound? share;
      _ShellTab? kept;
      final next = <_ShellTab>[];
      for (final t in _tabs) {
        if (!t.isMissionControl) {
          next.add(t);
          continue;
        }
        if (t.instanceUrl != inst.url) {
          _clearTabState(t.key);
          continue;
        }
        if (kept == null) {
          kept = t;
          share = t.inboundShare;
        } else {
          _clearTabState(t.key);
        }
      }
      if (kept == null ||
          !isDedicatedMcSession(kept.sessionId) ||
          kept.title != 'Mission Control') {
        kept = _mcTabFor(inst)..inboundShare = share ?? kept?.inboundShare;
      }
      next.insert(0, kept);
      _tabs
        ..clear()
        ..addAll(next);
      final idx =
          activeKey == null ? 0 : _tabs.indexWhere((t) => t.key == activeKey);
      _activeIndex = idx >= 0 ? idx : 0;
    });
    _persistTabs();
    _syncPage();
  }

  void _openMissionControlTab() {
    final inst = _active;
    if (inst == null) return;
    _ensurePinnedMissionControl();
    final i = _tabs
        .indexWhere((t) => t.isMissionControl && t.instanceUrl == inst.url);
    if (i >= 0) {
      _activateTab(i);
      if (kMobile) {
        _setState(() {
          _mobileChatsOpen = false;
          _pushMobileRoute(_MobileRoute(
            home: _mobileHome,
            agent: _mobileAgent,
            settingsSection: _mobileSettingsSection,
            inSession: true,
            sessionTabIndex: i,
          ));
        });
      }
    }
  }

  void _closeOthers(int keep) {
    if (keep < 0 || keep >= _tabs.length) return;
    final kept = _tabs[keep];
    final url = _active?.url;
    final pinned = _tabs
        .where((tab) => tab.isMissionControl && tab.instanceUrl == url)
        .toList();
    final survivors = <_ShellTab>[
      ...pinned.where((tab) => !identical(tab, kept)),
      kept,
    ];
    final keptKeys = survivors.map((tab) => tab.key).toSet();
    final removedKeys = _tabs
        .where((tab) => !keptKeys.contains(tab.key))
        .map((tab) => tab.key)
        .toList();
    _setState(() {
      _tabs
        ..clear()
        ..addAll(survivors);
      _activeIndex = _tabs.indexWhere((tab) => identical(tab, kept));
      if (_activeIndex < 0) _activeIndex = 0;
      for (final key in removedKeys) {
        _clearTabState(key);
      }
    });
    _ensurePinnedMissionControl();
    _persistTabs();
    _syncPage();
  }

  void _closeAllTabs() {
    final url = _active?.url;
    _setState(() {
      for (final tab in _tabs.where((t) =>
          !t.isMissionControl || (url != null && t.instanceUrl != url))) {
        _clearTabState(tab.key);
      }
      _tabs.removeWhere(
          (t) => !t.isMissionControl || (url != null && t.instanceUrl != url));
      _activeIndex = _tabs.isEmpty ? -1 : 0;
    });
    _ensurePinnedMissionControl();
    _persistTabs();
    _syncPage();
  }

  void _tabMenu(int i) {
    if (i < 0 || i >= _tabs.length) return;
    final t = _tabs[i];
    Offset? anchor;
    final key = _chipKeys[t.key];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      anchor = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
    }
    showTabContextMenu(
      context: context,
      tab: t,
      index: i,
      hasNonMissionControlTabs: _tabs.any((tab) => !tab.isMissionControl),
      onCloseTab: () => _closeTab(i),
      onCloseOthers: () => _closeOthers(i),
      onCloseAll: _closeAllTabs,
      position: anchor,
    );
  }

  bool _canCloseTab(_ShellTab t) => _isAuxiliary(t) && !t.isTerminal;

  bool _canCloseTopTab(_ShellTab t) => !t.isMissionControl;

  void _closeTab(int i, {bool force = false}) {
    if (i < 0 || i >= _tabs.length) return;
    if (!force && !_canCloseTab(_tabs[i])) return;
    final key = _tabs[i].key;
    _setState(() {
      final orphans = [
        for (final t in _tabs)
          if (t.groupSessionKey == key) t,
      ];
      for (final t in orphans) {
        _clearTabState(t.key);
        _activeKey.removeWhere((_, k) => k == t.key);
      }
      _tabs.removeWhere((t) => t.groupSessionKey == key);

      _clearTabState(key);
      _activeKey.removeWhere((_, k) => k == key);
      _tabs.removeWhere((t) => t.key == key);
      _groupRootKey.removeWhere((_, root) => !_tabs.any((t) => t.key == root));
      _normalizeActiveIndex(i);
    });
    _persistTabs();
    _syncPage();
  }

  void _normalizeActiveIndex([int removedAt = -1]) {
    if (_tabs.isEmpty) {
      _activeIndex = -1;
      return;
    }
    if (removedAt >= 0 && removedAt < _activeIndex) _activeIndex--;
    final i = _activeIndex;
    if (i >= 0 && i < _tabs.length && !_isAuxiliary(_tabs[i])) return;
    _activeIndex = _tabs.indexWhere((t) => !_isAuxiliary(t));
  }

  void _activateTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _setState(() {
      _activeIndex = i;
      final tab = _tabs[i];
      _activePane = tab.pane;
      _groupRootKey[tab.pane] = tab.key;
      _activeKey[tab.pane] = tab.key;
    });
    _persistTabs();
    _syncPage();
  }

  (_ShellTab?, _RightTab?) _shownItemInPane(_Pane p) {
    final list = _tabsIn(p);
    final readouts = [
      for (final r in _rightTabs)
        if (r.pane == p) r
    ];
    final key = _activeKey[p];

    final selectedTab = list.where((t) => t.key == key).firstOrNull;
    _RightTab? selectedReadout;
    for (final r in readouts) {
      if (r.key == key) selectedReadout = r;
    }
    final shownTab = selectedTab ??
        (selectedReadout == null && list.isNotEmpty ? list.first : null);
    final shownReadout = selectedReadout ??
        (shownTab == null && readouts.isNotEmpty ? readouts.first : null);
    return (shownTab, shownReadout);
  }

  void _closeActiveTab() {
    final primaryPane = _focusedPane;
    final secondaryPane = primaryPane == _Pane.left ? _Pane.right : _Pane.left;

    bool tryCloseInwardTabIn(_Pane p) {
      if (p == _Pane.right &&
          _rightCollapsed &&
          _tabsIn(p).isEmpty &&
          !_rightTabs.any((r) => r.pane == p)) {
        return false;
      }
      final (shownTab, shownReadout) = _shownItemInPane(p);
      if (shownReadout != null) {
        final navigator = shownReadout.request?.navigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
          return true;
        }
        _closeRightTab(shownReadout.key);
        return true;
      }
      if (shownTab != null && _isAuxiliary(shownTab)) {
        if (shownTab.isTerminal) {
          _hideTabView(p, shownTab);
        } else {
          _closePaneTab(shownTab);
        }
        return true;
      }
      return false;
    }

    if (tryCloseInwardTabIn(primaryPane)) return;
    if (!_rightCollapsed && tryCloseInwardTabIn(secondaryPane)) return;

    final active = _activeTab;
    if (active != null && _canCloseTopTab(active)) {
      _closeTabAt(active, force: true);
    }
  }

  void _activateMainTab(int index) {
    final mains = _mainTabs;
    if (mains.isEmpty) return;
    if (index >= mains.length) {
      index = mains.length - 1;
    }
    if (index < 0) index = 0;
    _activateTabAt(mains[index]);
  }

  void _activateRelativeMainTab(int delta) {
    final mains = _mainTabs;
    if (mains.length < 2) return;
    final active = _activeTab;
    final currentIndex = active != null ? mains.indexOf(active) : -1;
    final nextIndex = currentIndex >= 0
        ? (currentIndex + delta) % mains.length
        : 0;
    final target = mains[nextIndex < 0 ? nextIndex + mains.length : nextIndex];
    _activateTabAt(target);
  }

  void _openFileTab(DaemonClient client, String url, String path, String name) {
    final pane = _focusedPane;
    final group = _activeGroupKeyFor(pane);
    if (group == null) return;
    final existing = _tabs.indexWhere(
        (t) => t.isFile && t.instanceUrl == url && t.filePath == path);
    _setState(() {
      if (existing >= 0) {
        final t = _tabs[existing];
        t
          ..pane = pane
          ..groupSessionKey = group;
        _dockAux(pane, t.key);
      } else {
        _tabs.add(_ShellTab.file(
          client: client,
          instanceUrl: url,
          filePath: path,
          title: name,
          pane: pane,
          groupSessionKey: group,
        ));
        _dockAux(pane, _tabs.last.key);
      }
    });
    _persistTabs();
    _syncPage();
  }

  void _openDiffTab(
    DaemonClient client,
    String url,
    String sessionId,
    GitFile f,
  ) {
    final pane = _focusedPane;
    final group = _activeGroupKeyFor(pane);
    if (group == null) return;
    final staged = f.staged && !f.unstaged;
    final name = lastPathSegment(f.path, ifEmpty: f.path);
    final existing = _tabs.indexWhere((t) =>
        t.isDiff &&
        t.instanceUrl == url &&
        t.diffPath == f.path &&
        t.diffStaged == staged);
    _setState(() {
      if (existing >= 0) {
        final t = _tabs[existing];
        t
          ..pane = pane
          ..groupSessionKey = group;
        _dockAux(pane, t.key);
      } else {
        _tabs.add(_ShellTab.diff(
          client: client,
          instanceUrl: url,
          sessionId: sessionId,
          diffPath: f.path,
          title: name,
          diffStaged: staged,
          diffUntracked: f.untracked,
          pane: pane,
          groupSessionKey: group,
        ));
        _dockAux(pane, _tabs.last.key);
      }
    });
    _persistTabs();
    _syncPage();
  }

  void _closeTabByKey(String key) {
    final t = _tabs.where((t) => t.key == key).firstOrNull;
    if (t != null) {
      _closePaneTab(t);
    } else {
      final i = _tabs.indexWhere((t) => t.key == key);
      if (i >= 0) _closeTab(i);
    }
  }

  bool get _canNavigateBack => _activeIndex > 0;
  bool get _canNavigateForward =>
      _activeIndex >= 0 && _activeIndex < _tabs.length - 1;

  void _navigateBack() {
    if (_canNavigateBack) _activateTab(_activeIndex - 1);
  }

  void _navigateForward() {
    if (_canNavigateForward) _activateTab(_activeIndex + 1);
  }

  void _activateTabAt(_ShellTab t) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _activateTab(i);
  }

  Widget _mainTabsRow() => MainTabsStrip(
        controller: _stripController,
        tabs: _mainTabs,
        activeTab: _activeTab,
        statusForTab: _statusForTab,
        canCloseTab: _canCloseTopTab,
        onActivateTab: _activateTabAt,
        onCloseTab: (t) => _closeTabAt(t, force: true),
        onNewSession: _newSessionFlow,
        chipKeyFor: (key) => _chipKeys.putIfAbsent(key, () => GlobalKey()),
      );

  Future<void> _downloadActiveFile() async {
    final tab = _activeTab;
    if (tab == null || !tab.isFile) return;
    try {
      final message = await downloadRemoteFileWithCancel(
        context,
        tab.client,
        path: tab.filePath!,
        name: tab.title,
      );
      if (!mounted) return;
      if (message != null) toast(context, message);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  void _editActiveFile() {
    final tab = _activeTab;
    if (tab == null || !tab.isFile) return;
    presentScreen(
      context,
      style: PanelStyle.dialog,
      dismissible: false,
      builder: (_, close) => EditorScreen(
        client: tab.client,
        path: tab.filePath!,
        name: tab.title,
        onClose: close,
      ),
    );
  }
}
