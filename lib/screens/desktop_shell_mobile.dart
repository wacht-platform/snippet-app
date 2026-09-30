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
