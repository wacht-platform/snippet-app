part of 'desktop_shell.dart';

extension _DesktopShellMobileExt on _DesktopShellState {
  bool get _mobileDrilledDown =>
      _mobileSettingsSection != null || _mobileAgent != null;

  void _pushMobileRoute(_MobileRoute route) {
    if (!kMobile) return;
    if (_mobileRouteHistory.isNotEmpty && _mobileRouteHistory.last == route) {
      return;
    }
    final isTopLevel =
        !route.inSession && route.agent == null && route.settingsSection == null;
    if (isTopLevel) {
      final existingIndex = _mobileRouteHistory.lastIndexOf(route);
      if (existingIndex >= 0) {
        _mobileRouteHistory.removeRange(
            existingIndex + 1, _mobileRouteHistory.length);
        return;
      }
    }
    _mobileRouteHistory.add(route);
  }

  bool _handleMobileBack() {
    if (!kMobile) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_mobileRouteHistory.length <= 1) {
      return false;
    }
    _setState(() {
      _mobileRouteHistory.removeLast();
      final prev = _mobileRouteHistory.last;
      _mobileHome = prev.home;
      _mobileAgent = prev.agent;
      _mobileSettingsSection = prev.settingsSection;
      _mobileChatsOpen = !prev.inSession;
      if (prev.inSession &&
          prev.sessionTabIndex != null &&
          prev.sessionTabIndex! < _tabs.length) {
        _activeIndex = prev.sessionTabIndex!;
      }
    });
    return true;
  }

  void _showMobileChats() {
    if (!kMobile) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_handleMobileBack()) {
      _setState(() {
        _mobileChatsOpen = true;
      });
    }
  }


  void _startOnMission() {
    if (!kMobile || _active == null) return;
    final i = _tabs.indexWhere(
        (t) => t.isMissionControl && t.instanceUrl == _active!.url);
    if (i < 0) return;
    _activateTab(i);
    _setState(() {
      _mobileHome = MobileHome.chats;
      _mobileAgent = null;
      _mobileSettingsSection = null;
      _mobileChatsOpen = false;
      _mobileRouteHistory
        ..clear()
        ..add(_MobileRoute(
            home: MobileHome.chats, inSession: true, sessionTabIndex: i));
    });
  }

  void _goMission() {
    final h = _mobileRouteHistory;
    if (h.length > 1) {
      final prev = h[h.length - 2];
      final idx = prev.sessionTabIndex;
      if (prev.inSession &&
          idx != null &&
          idx < _tabs.length &&
          _tabs[idx].isMissionControl) {
        _handleMobileBack();
        return;
      }
    }
    _openMissionControlTab();
  }

  void _goMobileHome(MobileHome home,
      {SettingsPage? section, CoordinationAgent? agent}) {
    FocusManager.instance.primaryFocus?.unfocus();
    _setState(() {
      _mobileHome = home;
      _mobileSettingsSection = null;
      _mobileAgent = null;
      _mobileChatsOpen = true;
      _pushMobileRoute(_MobileRoute(home: home));
      if (section != null) {
        _mobileSettingsSection = section;
        _pushMobileRoute(_MobileRoute(home: home, settingsSection: section));
      }
      if (agent != null) {
        _mobileAgent = agent;
        _pushMobileRoute(_MobileRoute(home: home, agent: agent));
      }
    });
  }

  void _openMobileMenu() {
    showMobileMenu(
      context,
      client: _client,
      newSessionSubtitle: _active?.label ?? '',
      onPick: (pick) {
        switch (pick) {
          case MobileMenuPick.newSession:
            _newSessionFlow();
          case MobileMenuPick.tasks:
            _goMobileHome(MobileHome.tasks);
          case MobileMenuPick.agents:
            _goMobileHome(MobileHome.agents);
          case MobileMenuPick.usage:
            _goMobileHome(MobileHome.settings, section: SettingsPage.usage);
          case MobileMenuPick.machines:
            _goMobileHome(MobileHome.settings, section: SettingsPage.general);
        }
      },
      onAgent: (a) => _goMobileHome(MobileHome.agents, agent: a),
    );
  }

  Widget _mobileTopBar({required bool mission}) => MobileTopBar(
        mission: mission,
        sessionsBusy: mission &&
            (_sessions ?? const <SessionInfo>[]).any((s) =>
                !isDedicatedMcSession(s.id) &&
                s.status == 'running'),
        onMission: _goMission,
        onSessions: () => _goMobileHome(MobileHome.chats),
        onMenu: _openMobileMenu,
        onSettings: () => _goMobileHome(MobileHome.settings),
      );

  Widget _mobileShell() {
    final tab = _activeTab;
    final visible = _appForeground && !_mobileChatsOpen &&
        _mobileHome == _MobileHome.chats &&
        tab != null && !tab.isBoard && !tab.isFile && !tab.isDiff && !tab.isTerminal;
    reportVisibleNotificationSession(
        visible ? tab.instanceUrl : null, visible ? tab.sessionId : null);
    return MobileShell(
      activeTabBody: tab != null ? _tabBody(tab, primary: true) : null,
      sidebar: _sidebar(
        topInset: false,
        onAfterPick: () {
          if (_tabs.isNotEmpty) {
            _setState(() {
              _mobileChatsOpen = false;
              _pushMobileRoute(_MobileRoute(
                home: _mobileHome,
                agent: _mobileAgent,
                settingsSection: _mobileSettingsSection,
                inSession: true,
                sessionTabIndex: _activeIndex,
              ));
            });
          }
        },
      ),
      hasActiveTab: tab != null,
      chatsOpen: _mobileChatsOpen,
      drilledDown: _mobileDrilledDown,
      mobileHome: _mobileHome,
      canPopRoute: _mobileRouteHistory.length > 1,
      onPopRoute: () {
        _handleMobileBack();
      },
      onClearDrillDown: () {
        _handleMobileBack();
      },
      onMobileHome: (home) {
        _setState(() {
          _mobileHome = home;
          _mobileSettingsSection = null;
          _mobileAgent = null;
          _pushMobileRoute(_MobileRoute(home: home));
        });
      },
      onCloseChats: () {
        if (_tabs.isNotEmpty) {
          _setState(() {
            _mobileChatsOpen = false;
            _pushMobileRoute(_MobileRoute(
              home: _mobileHome,
              agent: _mobileAgent,
              settingsSection: _mobileSettingsSection,
              inSession: true,
              sessionTabIndex: _activeIndex,
            ));
          });
        }
      },
      onOpenChats: () {
        _handleMobileBack();
      },
    );
  }
}

class _MobileRoute {
  final MobileHome home;
  final CoordinationAgent? agent;
  final SettingsPage? settingsSection;
  final bool inSession;
  final int? sessionTabIndex;

  const _MobileRoute({
    required this.home,
    this.agent,
    this.settingsSection,
    this.inSession = false,
    this.sessionTabIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MobileRoute &&
          runtimeType == other.runtimeType &&
          home == other.home &&
          agent?.id == other.agent?.id &&
          settingsSection == other.settingsSection &&
          inSession == other.inSession &&
          sessionTabIndex == other.sessionTabIndex;

  @override
  int get hashCode =>
      Object.hash(home, agent?.id, settingsSection, inSession, sessionTabIndex);
}
