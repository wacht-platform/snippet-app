import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../command_palette.dart';
import '../device_events.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../share_inbound.dart';
import '../shells.dart';
import '../store.dart';
import '../term.dart' show SessionTermView;
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart';
import 'editor.dart';
import 'files.dart';
import 'git.dart';
import 'inbound_share_picker.dart';
import 'mission_control.dart';
import 'mobile_shell.dart';
import 'new_session_picker.dart';
import 'session.dart';
import 'settings_panel.dart';
import 'shell_card_tab_strip.dart';
import 'shell_main_pane.dart';
import 'shell_models.dart';
import 'shell_nav.dart';
import 'shell_pane_view.dart';
import 'shell_rail.dart';
import 'shell_rail_tools.dart';
import 'shell_shortcuts.dart';
import 'shell_sidebar_host.dart';
import 'shell_split_view.dart';
import 'shell_welcome.dart';
import 'shell_window_bar.dart';

export 'inbound_share_picker.dart';
export 'mobile_shell.dart';
export 'settings_panel.dart';
export 'shell_card_tab_strip.dart';
export 'shell_components.dart';
export 'shell_main_pane.dart';
export 'shell_models.dart';
export 'shell_pane_view.dart';
export 'shell_rail_tools.dart';
export 'shell_shortcuts.dart';
export 'shell_sidebar_host.dart';
export 'shell_split_view.dart';
export 'shell_welcome.dart';
export 'shell_window_bar.dart';
export 'sidebar.dart';


class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

typedef _Pane = ShellPane;
typedef _MobileHome = MobileHome;
typedef _ShellTab = ShellTab;
typedef _MacSessionStatus = MacSessionStatus;
typedef _MacSessionControls = MacSessionControls;
typedef _RightPanel = RightPanel;
typedef _RightTab = RightTab;

class _DesktopShellState extends State<DesktopShell>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final InstanceStore _store = InstanceStore();
  List<Instance> _instances = const [];
  Instance? _active;
  DaemonClient? _client;
  final List<_ShellTab> _tabs = [];
  int _activeIndex = -1;
  final PageController _pageController = PageController();
  final ScrollController _stripController = ScrollController();
  final Map<String, GlobalKey> _chipKeys = {};

  /// Daemon-wide interactive shells.
  ///
  /// Owns its own socket (`/shells`), so a shell survives switching or closing a
  /// session — which is the whole point of it being global. Its tab list is
  /// mirrored into `_tabs` by `_syncGlobalShellTabs` so shells are ordinary pane
  /// tabs, draggable and closeable like anything else.
  final ShellsController _shells = ShellsController();

  /// The selected MAIN workspace tab — what the window bar highlights and what
  /// the left pane shows when no auxiliary tab is covering it.
  ///
  /// Deliberately main-only: an auxiliary tab (terminal, preview, diff) is a
  /// per-pane choice and must not move the window bar's selection.
  _ShellTab? get _activeTab {
    final i = _activeIndex;
    if (i >= 0 && i < _tabs.length && !_isAuxiliary(_tabs[i])) return _tabs[i];
    final mains = _mainTabs;
    return mains.isEmpty ? null : mains.first;
  }

  String? get _sessionId => _activeTab?.sessionId;

  /// A tab's session run state, for tinting its icon.
  ///
  /// Prefers the live status the session publishes (`_macSessionStatuses`, kept
  /// current by `_setMacSessionStatus`) and falls back to the list's cached
  /// status, so a tab reads correctly even before its session first reports.
  String? _statusForTab(_ShellTab t) {
    final live = _macSessionStatuses[t.key];
    if (live != null) {
      return live.state?.status ?? (live.running ? 'running' : 'idle');
    }
    for (final s in _sessions ?? const <SessionInfo>[]) {
      if (s.id == t.sessionId) return s.status;
    }
    return null;
  }

  bool _loading = true;
  // Session list lives here (not in the sidebar) so it survives drawer open/close
  // and is shared with the "recent sessions" placeholder.
  List<SessionInfo>? _sessions;
  bool _sessionsLoading = false;
  // Non-null when the last session fetch failed — rendered as an offline/retry
  // state so an unreachable daemon doesn't masquerade as "No chats yet".
  String? _sessionsError;
  bool _drawerOpen = false;

  /// Phone navigation is intentionally not a collapsed desktop drawer. Chats is
  /// a full-screen home, and one active session is its own full-screen reading
  /// surface with a clear return affordance.
  bool _mobileChatsOpen = true;

  /// Which place the phone home is showing.
  ///
  /// Owned by the SHELL, not the sidebar: `_mobileShell`'s back handler must see
  /// it, or pressing back from Settings would exit the app instead of returning
  /// to Chats. Desktop navigates with the sidebar rail, so this is phone-only.
  _MobileHome _mobileHome = _MobileHome.agents;

  /// Phone drill-down: which settings section is open, and which agent's detail.
  ///
  /// Both live HERE rather than inside their own screens because two things
  /// outside them must read them: the back handler (to unwind one level at a
  /// time) and the bar's visibility (to hide itself while drilled down).
  _SettingsPage? _mobileSettingsSection;
  CoordinationAgent? _mobileAgent;

  /// True while a nested phone screen is open, in which case the bar hides.
  ///
  /// The bar names the app's TOP LEVEL. Leaving it up inside a nested screen
  /// gives that screen a second exit that skips the level you are in, and makes
  /// the bar read as part of the sub-screen.
  bool get _mobileDrilledDown =>
      _mobileSettingsSection != null || _mobileAgent != null;

  final List<_MobileRoute> _mobileRouteHistory = [
    const _MobileRoute(home: MobileHome.agents),
  ];

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
    setState(() {
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

  // url → reachable, from a short /health ping (drives the machine status dots).
  final Map<String, bool> _health = {};
  final Map<String, _MacSessionStatus> _macSessionStatuses = {};
  final Map<String, _MacSessionControls> _macSessionControls = {};

  /// Terminals, bridged from each mounted `SessionScreen`.
  ///
  /// The session owns the pty and the ids; the SHELL owns the pane. A terminal
  /// therefore outlives switching sessions — which it must, because you start a
  /// shell and then keep reading the chat.
  final Map<String, TerminalHost> _termHosts = {};

  /// Whether each tab's session currently wants its terminal pane open.
  /// `_termOpen` in the session; the shell honours it but can also minimize
  /// independently without killing the pty.
  final Map<String, bool> _termPaneOpen = {};

  GitStatus? _macGit;
  String _macGitKey = '';

  Timer? _sessionsTicker;
  bool _appForeground = true;
  WebSocketChannel? _eventsChannel;
  StreamSubscription? _eventsSub;
  Timer? _eventsReconnect;
  int _eventsGeneration = 0;
  // Live status from /events (and open-tab callbacks). Survives a slow
  // /sessions refetch so the list doesn't flicker back to stale.
  final Map<String, String> _liveStatus = {};

  /// Which agents are working in each session, as display initials.
  ///
  /// Keyed by session id. Shown inline on the session rows — the phone card and
  /// the desktop sidebar row both render it — so "who is working where" is
  /// answerable without opening anything. Kept separate from [_sessions] so a
  /// coordination failure can never take the session list down with it.
  bool _sidebarGit = false;


  /// Secondary-pane width, dragged by its handle. Width-driven rather than a
  /// flex ratio because a flex ratio cannot be dragged and has no natural size.
  double _paneWidth = kPaneDefaultWidth;

  /// Which contextual sidebar the rail is showing. Purely a shell concern: the
  /// conversation you're reading stays put while this changes.
  ShellSection _section = ShellSection.sessions;

  /// Detail shown in the right pane. Null = pane hidden, so the transcript gets
  /// the full width until something asks for detail — a pane that is always
  /// present would cost space even when nothing needs inspecting.
  /// Tabs open in the secondary pane: session readouts and agent details.
  ///
  /// A LIST, not one exclusive selection. Lanes, Checkpoints, Usage and a named
  /// agent are independent things; keeping one meant closing one to open
  /// another, which is why the rail buttons behaved like radio buttons.
  ///
  /// These share ONE strip and ONE selection with docked `_ShellTab`s — see
  /// `_activeKey`. Rendering them as a separate, mutually-exclusive view is what
  /// made a dropped tab hide the readout that was already there.
  final List<_RightTab> _rightTabs = [];

  /// The user collapsed a pane. Hiding a pane is always a view action and never
  /// destroys anything — a terminal tab lives on in the sidebar, and its pty
  /// stays alive, so re-opening is instant.
  bool _rightCollapsed = false;
  bool _leftCollapsed = false;

  /// Terminal tabs the user dismissed from a pane's strip.
  ///
  /// Dismissing a terminal closes only its VIEW. The pty keeps running in the
  /// daemon and the shell stays listed in the Terminals panel, so re-opening is
  /// instant. Without this the chip's close hid the whole PANE the terminal
  /// lived in — conversation included — instead of just the terminal's view.
  final Set<String> _hiddenTabs = {};

  /// Which tab each pane is showing, keyed by pane. Separate from `_activeIndex`
  /// so the two containers keep independent selections.
  final Map<_Pane, String> _activeKey = {};

  /// The pane that was last activated or interacted with.
  _Pane _activePane = _Pane.left;

  /// Root session selected for each inner tab group. A root is always present as
  /// that group's first, locked tab; its files, diffs and terminals reference it
  /// through `_ShellTab.groupSessionKey`.
  final Map<_Pane, String> _groupRootKey = {};

  /// True when this readout is the tab the pane is currently showing.
  ///
  /// Reads the pane's ONE selection slot, which docked `_ShellTab`s share — a
  /// readout and a docked tab can never both be "active".
  bool _rightPanelActive(_RightPanel p) {
    final key = _RightTab.panel(p).key;
    return _activeKey[_Pane.right] == key || _activeKey[_Pane.left] == key;
  }

  /// Open a readout in the pane, focusing it if it is already open.
  ///
  /// Toggling CLOSED when the same panel is already focused keeps the old
  /// affordance (tap the lit button to dismiss), while a different panel ADDS a
  /// tab instead of replacing one — that replacement was the bug.
  void _toggleRightPanel(_RightPanel p) {
    if (p == _RightPanel.none) return;
    final key = _RightTab.panel(p).key;
    setState(() {
      _rightCollapsed = false;
      // Focused already? Dismiss it, wherever it currently lives.
      if (_activeKey[_Pane.right] == key) {
        _closeRightTab(key);
        return;
      }
      if (_activeKey[_Pane.left] == key) {
        _closeRightTab(key);
        return;
      }
      // The rail button opens a readout in the SECONDARY pane, so re-target it
      // if a drag previously parked it on the left.
      final existing = _rightTabs.where((t) => t.key == key).firstOrNull;
      if (existing == null) {
        _rightTabs.add(_RightTab.panel(p));
      } else {
        existing.pane = _Pane.right;
      }
      _activePane = _Pane.right;
      _activeKey[_Pane.right] = key;
    });
  }

  /// Open an agent's detail as a pane tab, focusing it if already open.
  void _openRightAgent(CoordinationAgent a) {
    final key = _RightTab.agent(a).key;
    setState(() {
      _rightCollapsed = false;
      final existing = _rightTabs.where((t) => t.key == key).firstOrNull;
      if (existing == null) {
        _rightTabs.add(_RightTab.agent(a));
      } else {
        existing.pane = _Pane.right;
      }
      _activePane = _Pane.right;
      _activeKey[_Pane.right] = key;
    });
  }

  /// Close ONE readout tab. Does not collapse the pane — other tabs may remain,
  /// and even an empty pane stays open so the next rail tap lands somewhere.
  void _closeRightTab(String key) {
    if (!mounted) return;
    setState(() {
      _rightTabs.removeWhere((t) => t.key == key);
      for (final pane in _Pane.values) {
        if (_activeKey[pane] != key) continue;
        // Fall back to another readout in the SAME pane, else hand the slot
        // back to that pane's docked tabs (or leave it empty).
        final rest = [
          for (final r in _rightTabs)
            if (r.pane == pane) r,
        ];
        if (rest.isNotEmpty) {
          _activeKey[pane] = rest.last.key;
        } else {
          _activeKey.remove(pane);
        }
      }
    });
  }

  /// The button list at the far right of the navigation band.
  ///
  /// Same shape as the icon strip over the sidebar, per the steer. Carries the
  /// session-scoped actions the removed bottom strip held — but ONLY what the
  /// LHS panels do NOT provide: Git, Files and Terminals have panels of their
  /// own, so repeating them here would be two doors to one room.
  ///
  /// The cluster is inline for EVERY session, including Mission Control: a "⋯"
  /// that hides four one-tap actions behind a menu is friction, and it made MC
  /// the only session whose controls were not visible.
  ///
  /// What differs is the CONTENT, because MC is not a workspace session. It
  /// orchestrates, so it gets the board and the agents it assigns; the
  /// authoring trio (goal, lanes, checkpoints) belongs to a session that owns a
  /// working tree, and MC's own menus never offered them.
  /// Sections the sidebar strip hides for the ACTIVE session.
  ///
  /// Mission Control has no working tree — it orchestrates other sessions — so
  /// its Terminal and Git Diff are two buttons that open empty panels. Hiding
  /// them is honest about what MC can do.
  Set<ShellSection> get _hiddenSections =>
      (_activeTab?.isMissionControl ?? false)
          ? const {ShellSection.terminal, ShellSection.git}
          : const {};

  /// The section actually rendered.
  ///
  /// `_section` is sticky, so switching to Mission Control while Terminal is
  /// selected would leave a hidden section live — the strip would show no lit
  /// button while the panel below still rendered a terminal MC cannot have. The
  /// clamp falls back to Sessions, which is never hidden.
  ShellSection get _effectiveSection =>
      _hiddenSections.contains(_section) ? ShellSection.sessions : _section;

  List<Widget> _railTools() => buildShellRailTools(
        activeTab: _activeTab,
        macSessionStatus: _activeTab == null
            ? null
            : _macSessionStatuses[_activeTab!.key],
        isRightPanelActive: _rightPanelActive,
        onToggleRightPanel: _toggleRightPanel,
        onSessionAction: _dispatchSessionAction,
        onOpenGoalPopover: _openGoalPopover,
      );

  Future<void> _openGoalPopover(BuildContext btnCtx) => showGoalPopover(
        context: context,
        anchorContext: btnCtx,
        onSetGoal: (text) => _dispatchSessionAction('goal', text),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInstances();
    // Tapping a session notification opens it in-place (consistent with the app),
    // not a separate full-screen route.
    if (kCanNotify) onNotifTap = _onNotif;
    _startSessionsTicker();
    if (!kMobile) HardwareKeyboard.instance.addHandler(_handleGlobalShortcuts);
    if (kMobile) ShareInbound.listen(_onInboundShare);
    // Global shells mirror into tabs whenever the daemon reports a change: a
    // reconnect adopts whatever ptys already exist, so live shells never vanish
    // from the strip just because the socket dropped.
    _shells.addListener(_syncGlobalShellTabs);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kMobile) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalShortcuts);
    }
    _sessionsTicker?.cancel();
    _stopEventsWatch();
    _persistTabsDebounce?.cancel();
    _pageController.dispose();
    _stripController.dispose();
    _shells.removeListener(_syncGlobalShellTabs);
    // Closes the socket only. Never the ptys: a shell outlives this window, which
    // is the entire point of it being daemon-wide.
    _shells.dispose();
    if (onNotifTap == _onNotif) onNotifTap = null;
    if (kMobile) ShareInbound.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    _appForeground = fg;
    if (fg) {
      _startSessionsTicker();
      _connectEventsWatch();
      if (mounted && !_sessionsLoading) _loadSessions();
    } else {
      _sessionsTicker?.cancel();
      _sessionsTicker = null;
    }
  }

  void _startSessionsTicker() {
    _sessionsTicker?.cancel();
    final period = Duration(seconds: kMobile ? 90 : 30);
    _sessionsTicker = Timer.periodic(period, (_) {
      if (!mounted || !_appForeground) return;
      if (!_sessionsLoading) _loadSessions();
      _refreshHealth();
    });
  }

  late final _shortcutsHandler = ShellShortcutsHandler(
    onCloseActiveTab: _closeActiveTab,
    onNewSession: _newSessionFlow,
    onActivateRelativeTab: _activateRelativeMainTab,
    onActivateTab: _activateMainTab,
    onOpenActiveFiles: _openActiveFiles,
    onOpenMacGit: _openMacGit,
    onToggleSidebar: _toggleSidebar,
    onToggleRightPanel: _toggleSecondaryPane,
    onOpenCommandPalette: _openCommandPalette,
    onFocusComposer: () =>
        _macSessionControls[_activeTab?.key]?.performAction('focus_composer'),
    onStopRunningTask: () => _macSessionControls[_activeTab?.key]?.stop(),
    onShowShortcuts: _showDesktopShortcuts,
  );

  bool _handleGlobalShortcuts(KeyEvent event) =>
      _shortcutsHandler.handleKeyEvent(event);

  /// Drop every per-tab bookkeeping entry for a tab that is going away.
  ///
  /// Kept in one place so a newly added map cannot be forgotten at the six
  /// teardown sites.
  void _clearTabState(String key) {
    _macSessionStatuses.remove(key);
    _macSessionControls.remove(key);
    _termHosts.remove(key);
    _termPaneOpen.remove(key);
  }

  void _setMacSessionStatus(String key, HarnessState? state, bool running) {
    _macSessionStatuses[key] = _MacSessionStatus(state, running);
    final status = state?.status ?? (running ? 'running' : 'idle');
    String? sessionId;
    for (final t in _tabs) {
      if (t.key == key) {
        sessionId = t.sessionId;
        break;
      }
    }
    if (sessionId != null) _patchSessionStatus(sessionId, status);
    if (mounted) setState(() {});
  }

  /// Record a tab's terminal host so the shell's pane can render it.
  ///
  /// Skips `setState` when nothing actually changed: `SessionScreen` publishes
  /// this on every `alive`/`live` transition, and rebuilding the whole shell to
  /// discover an identical list would be wasted frames.
  void _setTerminalHost(String key, TerminalHost host, bool open) {
    final prev = _termHosts[key];
    final prevTerms = prev?.terms ?? const <TerminalInfo>[];
    final hostTerms = host.terms;
    final changed = prev == null ||
        prevTerms.length != hostTerms.length ||
        host.focus != prev.focus ||
        [_termPaneOpen[key] != open].any((x) => x) ||
        [
          for (var i = 0; i < hostTerms.length; i++)
            prevTerms[i].id != hostTerms[i].id ||
                prevTerms[i].title != hostTerms[i].title ||
                prevTerms[i].alive != hostTerms[i].alive ||
                prevTerms[i].live != hostTerms[i].live,
        ].any((x) => x);

    _termHosts[key] = host;
    // Capture BEFORE assigning: the un-minimize check below compares against
    // the previous value, and assigning first made it permanently false.
    final wasOpen = _termPaneOpen[key] ?? false;
    _termPaneOpen[key] = open;

    // A terminal is a TAB like anything else: reconcile the strip against the
    // session's live list so a new pty gets a tab and an exited one loses it.
    final tabsChanged = _reconcileTermTabs(key, host);

    // A terminal created from the SIDEBAR must reveal its pane: creating is the
    // sidebar's job, showing the result is the shell's.
    if (prevTerms.isEmpty && hostTerms.isNotEmpty) {
      _rightCollapsed = false;
      _showTabPane(key, host);
    }
    // An explicit open from the sidebar un-minimizes. Without this, tapping a
    // terminal in the sidebar would flip the session's flag while the shell kept
    // showing nothing.
    if (open && !wasOpen && hostTerms.isNotEmpty) {
      _rightCollapsed = false;
      _showTabPane(key, host);
    }
    if ((changed || tabsChanged) && mounted) setState(() {});
  }

  /// Reveal the pane holding a session's terminal tab.
  void _showTabPane(String sessionKey, TerminalHost host) {
    final id = host.activeId;
    if (id == null) return;
    for (final t in _tabs) {
      if (t.isTerminal && t.termSessionKey == sessionKey && t.termId == id) {
        // A terminal is AUXILIARY: selecting it docks it in its pane without
        // moving the window bar's selection.
        _dockAux(t.pane, t.key);
        return;
      }
    }
  }

  /// Add tabs for new terminals and drop tabs whose pty is gone.
  ///
  /// Returns true when the tab list changed, so the caller can repaint.
  bool _reconcileTermTabs(String sessionKey, TerminalHost host) {
    final live = {for (final t in host.terms) t.id: t};
    var changed = false;

    // Gone: the pty exited or the sidebar destroyed it. Remove the TAB only —
    // never `_clearTabState`, which is keyed by session and would wipe the host
    // shared with this session's other terminals.
    final stale = [
      for (final t in _tabs)
        if (t.isTerminal &&
            t.termSessionKey == sessionKey &&
            !live.containsKey(t.termId))
          t,
    ];
    for (final t in stale) {
      final i = _tabs.indexOf(t);
      if (i < 0) continue;
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        _activeIndex = -1;
      } else if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      } else if (i < _activeIndex) {
        _activeIndex--;
      }
      changed = true;
    }

    // New: give each live pty a tab, docked where it was requested.
    _ShellTab? owner;
    for (final t in _tabs) {
      if (t.key == sessionKey) {
        owner = t;
        break;
      }
    }
    if (owner == null) return changed;
    for (final info in host.terms) {
      final exists = _tabs.any((t) =>
          t.isTerminal &&
          t.termSessionKey == sessionKey &&
          t.termId == info.id);
      if (exists) continue;
      // A session terminal is a sibling of its one locked conversation root.
      // Selecting another session hides it but leaves the session-owned pty
      // untouched; returning to the session restores the tab and scrollback.
      final target = owner.pane;
      _tabs.add(_ShellTab.terminal(
        client: owner.client,
        instanceUrl: owner.instanceUrl,
        termSessionKey: sessionKey,
        termId: info.id,
        title: info.title,
        pane: target,
        groupSessionKey: owner.key,
      ));
      if (_groupRootFor(target) == owner.key) {
        _activeKey[target] = _tabs.last.key;
      }
      changed = true;
    }

    // Renames: the sidebar can retitle a terminal, and the tab follows.
    for (final t in _tabs) {
      if (t.isTerminal && t.termSessionKey == sessionKey) {
        final info = live[t.termId];
        if (info != null && info.title != t.title) {
          t.title = info.title;
          changed = true;
        }
      }
    }
    return changed;
  }

  void _patchSessionStatus(String sessionId, String status) {
    if (sessionId.isEmpty || status.isEmpty) return;
    _liveStatus[sessionId] = status;
    final sessions = _sessions;
    if (sessions == null) return;
    final i = sessions.indexWhere((s) => s.id == sessionId);
    if (i < 0 || sessions[i].status == status) return;
    _sessions = [
      for (var n = 0; n < sessions.length; n++)
        n == i ? sessions[n].withStatus(status) : sessions[n],
    ];
  }

  void _applyLiveStatus(List<SessionInfo> sessions) {
    if (_liveStatus.isEmpty) return;
    for (var i = 0; i < sessions.length; i++) {
      final live = _liveStatus[sessions[i].id];
      if (live != null && live.isNotEmpty && sessions[i].status != live) {
        sessions[i] = sessions[i].withStatus(live);
      }
    }
  }

  void _stopEventsWatch() {
    _eventsGeneration++;
    _eventsReconnect?.cancel();
    _eventsReconnect = null;
    _eventsSub?.cancel();
    _eventsSub = null;
    _eventsChannel?.sink.close();
    _eventsChannel = null;
  }

  void _connectEventsWatch() {
    final c = _client;
    if (c == null) {
      _stopEventsWatch();
      return;
    }
    _stopEventsWatch();
    final generation = _eventsGeneration;
    try {
      final ch = c.events();
      _eventsChannel = ch;
      _eventsSub = ch.stream.listen(
        (msg) {
          if (generation != _eventsGeneration || !identical(ch, _eventsChannel)) {
            return;
          }
          final event = DeviceEvent.decode(msg);
          if (event == null) return;
          final kind = event.kind;
          if (kind == 'models' || kind == 'config') {
            c.invalidateConfig();
            modelsRevision.value++;
          }
          final session = event.session;
          final status = event.status;
          if (session.isEmpty || status.isEmpty) return;
          if (!mounted) return;
          _patchSessionStatus(session, status);
          setState(() {});
        },
        onDone: _scheduleEventsReconnect,
        onError: (_) => _scheduleEventsReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleEventsReconnect();
    }
  }

  void _scheduleEventsReconnect() {
    if (!mounted || !_appForeground || _client == null) return;
    _eventsReconnect?.cancel();
    _eventsReconnect = Timer(const Duration(seconds: 3), () {
      if (mounted && _appForeground) _connectEventsWatch();
    });
  }

  void _setMacSessionControls(String key, VoidCallback stop,
      void Function(String action, [String? extra]) performAction) {
    _macSessionControls[key] = _MacSessionControls(stop, performAction);
    if (mounted && _activeTab?.key == key) setState(() {});
  }

  void _syncPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _activeIndex >= 0) {
        _pageController.jumpToPage(_activeIndex);
      }
      _scrollStripToActive();
    });
    _refreshMacGit();
  }

  Future<void> _refreshMacGit() async {
    if (!kMacOS) return;
    final tab = _activeTab;
    final sessionId = tab?.sessionId;
    final key = tab?.key ?? '';
    _macGitKey = key;
    if (sessionId == null || tab == null) {
      if (mounted && _macGit != null) {
        setState(() => _macGit = null);
      }
      return;
    }
    try {
      final status = await tab.client.gitStatus(sessionId);
      if (!mounted || _activeTab?.key != key || _macGitKey != key) return;
      setState(() => _macGit = status.ok ? status : null);
    } catch (_) {
      if (mounted && _activeTab?.key == key && _macGitKey == key) {
        setState(() => _macGit = null);
      }
    }
  }

  String _macRepositoryLabel() {
    final tab = _activeTab;
    if (tab == null) return _active?.label ?? 'Workspace';
    if (tab.isFile) {
      final path = tab.filePath ?? '';
      final slash = path.lastIndexOf('/');
      final parent = slash > 0 ? path.substring(0, slash) : '';
      return lastPathSegment(parent, ifEmpty: 'Workspace');
    }
    final id = tab.sessionId;
    SessionInfo? session;
    if (id != null) {
      for (final candidate in _sessions ?? const <SessionInfo>[]) {
        if (candidate.id == id) {
          session = candidate;
          break;
        }
      }
    }
    return lastPathSegment(session?.folder ?? '',
        ifEmpty: _active?.label ?? 'Workspace');
  }

  /// The active tab's workspace folder, or null when it cannot be resolved
  /// (no session open, file tab, or the folder is not in the list yet). The
  /// files panel falls back to the daemon home when this is null.
  String? _activeWorkspaceFolder() {
    final id = _activeTab?.sessionId;
    if (id == null) return null;
    for (final candidate in _sessions ?? const <SessionInfo>[]) {
      if (candidate.id == id) {
        final folder = candidate.folder.trim();
        return folder.isEmpty ? null : folder;
      }
    }
    return null;
  }


  // Bring the active tab's chip into view in the strip.
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

  Timer? _persistTabsDebounce;
  void _persistTabs() {
    // Debounce rapid tab mutations (close/open/reorder) to avoid N
    // sequential SharedPreferences writes in a single frame.
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
                  // Which pane a tab sits in is a property OF the tab, so a
                  // restart must not collapse every split back to the left.
                  pane: t.pane.name,
                  groupSessionKey: t.groupSessionKey,
                  termSessionKey: t.termSessionKey,
                  termId: t.termId,
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
      // Restore the pane a tab was in, so a restart does not collapse the split.
      // Terminal tabs are NOT restored: a pty does not outlive the daemon
      // connection, so the sidebar re-offers the live set once a session
      // publishes again.
      final pane =
          descriptor.pane == _Pane.right.name ? _Pane.right : _Pane.left;
      if (descriptor.isTerminal) {
        continue;
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
    setState(() {
      if (restored.isNotEmpty) {
        _tabs
          ..clear()
          ..addAll(restored);
        // `saved.activeIndex` indexes the whole list, which can now point at an
        // AUXILIARY tab (a terminal or preview). Normalize so the window bar
        // lands on a main workspace tab, not on a pane's docked content.
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
        setState(() => _activeIndex = 0);
        _persistTabs();
        _syncPage();
      }
      return;
    }
    if (foreign > 0 || extras > 0 || leftover) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
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
        setState(() {
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
    setState(() {
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
    setState(() {
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

  /// Pane-strip rule: an inner tab group is session-rooted, so the conversation
  /// root itself is permanent for the lifetime of its group and only the
  /// supporting content beside it closes.
  bool _canCloseTab(_ShellTab t) => _isAuxiliary(t) && !t.isTerminal;

  /// Window-bar rule: the FIRST level is a plain list of open workspaces, so any
  /// of them closes — that is the whole point of a window bar. Only the pinned
  /// Mission Control tab is exempt.
  ///
  /// Using `_canCloseTab` here is what made top tabs unclosable: it is written
  /// for the pane strip, where a session root must stay, and a session tab is
  /// never "auxiliary".
  bool _canCloseTopTab(_ShellTab t) => !t.isMissionControl;

  void _closeTab(int i, {bool force = false}) {
    if (i < 0 || i >= _tabs.length) return;
    if (!force && !_canCloseTab(_tabs[i])) return;
    final key = _tabs[i].key;
    setState(() {
      // Closing a level-1 workspace must take its level-2 children with it.
      // Leaving them behind orphaned the aux tabs: their group root no longer
      // existed, so `_groupRootFor` fell back to whatever was active and the
      // strip showed files and terminals belonging to a closed conversation.
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
      // A pane selection pointing at a tab that no longer exists would leave
      // that pane blank instead of falling back to its default content.
      _activeKey.removeWhere((_, k) => k == key);
      _tabs.removeWhere((t) => t.key == key);
      // Drop group roots that no longer anchor anything, so a reopened
      // conversation does not inherit a dead group.
      _groupRootKey.removeWhere((_, root) => !_tabs.any((t) => t.key == root));
      _normalizeActiveIndex(i);
    });
    _persistTabs();
    _syncPage();
  }

  /// Keep `_activeIndex` pointing at a MAIN workspace tab after a mutation.
  ///
  /// [removedAt] is the index a tab was just removed from, or -1. Recomputing
  /// beats hand-rolling the off-by-one at each call site, and it is the only way
  /// to stay correct when the removed tab was AUXILIARY — closing a terminal or
  /// a preview must not move the window bar's selection.
  void _normalizeActiveIndex([int removedAt = -1]) {
    if (_tabs.isEmpty) {
      _activeIndex = -1;
      return;
    }
    if (removedAt >= 0 && removedAt < _activeIndex) _activeIndex--;
    final i = _activeIndex;
    if (i >= 0 && i < _tabs.length && !_isAuxiliary(_tabs[i])) return;
    // No valid main selection — fall to the first main tab, or -1 if the shell
    // somehow holds auxiliary tabs only.
    _activeIndex = _tabs.indexWhere((t) => !_isAuxiliary(t));
  }

  void _activateTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    // PageView keeps each session mounted. Remove focus from the old composer
    // before changing pages so the platform text-input client cannot remain
    // attached to the previous session after a swipe or tab tap.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activeIndex = i;
      final tab = _tabs[i];
      _activePane = tab.pane;
      // The window bar switches the selected nested group, not merely the
      // highlight: the conversation becomes the locked first item in its own
      // full-width inner strip.
      _groupRootKey[tab.pane] = tab.key;
      _activeKey[tab.pane] = tab.key;
    });
    _persistTabs();
    _syncPage();
  }

  /// Active tab or readout currently showing in pane [p].
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

    // 1. Prioritize closing the active inward tab in the focused pane.
    if (tryCloseInwardTabIn(primaryPane)) return;

    // 2. If the focused pane has no inward tab, check if the other visible pane has an inward tab.
    if (!_rightCollapsed && tryCloseInwardTabIn(secondaryPane)) return;

    // 3. No inward tab is active/open in any visible pane — the session tab is open.
    // Close the outward tab (the active workspace session).
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

  void _activateRelativeTab(int delta) => _activateRelativeMainTab(delta);

  void _toggleSidebar() {
    setState(() => _leftCollapsed = !_leftCollapsed);
  }

  void _toggleSecondaryPane() {
    setState(() => _rightCollapsed = !_rightCollapsed);
  }

  void _openActiveFiles() {
    if (kMobile) {
      _macSessionControls[_activeTab?.key]?.performAction('files');
    } else {
      setState(() {
        if (_section == ShellSection.files && !_leftCollapsed) {
          _leftCollapsed = true;
        } else {
          _section = ShellSection.files;
          _leftCollapsed = false;
        }
      });
    }
  }

  void _openMacGit() {
    setState(() {
      _sidebarGit = !_sidebarGit;
      if (_section == ShellSection.git && !_leftCollapsed) {
        _leftCollapsed = true;
      } else {
        _section = ShellSection.git;
        _leftCollapsed = false;
      }
    });
  }

  void _openCommandPalette() {
    showCommandPalette(
      context,
      sessions: _sessions ?? const <SessionInfo>[],
      onOpenChat: (s) => _openSession(s.id, s.title, s.profile),
      commands: [
        PaletteCommand(
          'plus',
          'New Session',
          '⌘/Ctrl T',
          _newSessionFlow,
        ),
        PaletteCommand(
          'sidebar',
          'Toggle Primary Sidebar',
          '⌘/Ctrl B',
          _toggleSidebar,
        ),
        PaletteCommand(
          'layout-sidebar-right',
          'Toggle Secondary Panel',
          '⌘/Ctrl \\',
          _toggleSecondaryPane,
        ),
        PaletteCommand(
          'file',
          'Open File Tree',
          '⌘/Ctrl ⇧ E',
          _openActiveFiles,
        ),
        PaletteCommand(
          'git-branch',
          'Open Git Diff',
          '⌘/Ctrl ⇧ G',
          _openMacGit,
        ),
        PaletteCommand(
          'terminal',
          'Open Terminals',
          '',
          () => setState(() {
            _section = ShellSection.terminal;
            _leftCollapsed = false;
          }),
        ),
        PaletteCommand(
          'agent',
          'Open Agents',
          '',
          () => setState(() {
            _section = ShellSection.agents;
            _leftCollapsed = false;
          }),
        ),
        PaletteCommand(
          'message-text',
          'Open Chats List',
          '',
          () => setState(() {
            _section = ShellSection.sessions;
            _leftCollapsed = false;
          }),
        ),
        PaletteCommand(
          'help-circle',
          'Keyboard Shortcuts',
          '⌘/Ctrl /',
          _showDesktopShortcuts,
        ),
        PaletteCommand(
          'stop-circle',
          'Stop Active Run',
          '⌘/Ctrl .',
          () => _macSessionControls[_activeTab?.key]?.stop(),
        ),
      ],
    );
  }

  void _showDesktopShortcuts() => showDesktopShortcutsDialog(context);

  void _onNotif(Map<String, dynamic> m) async {
    if (!mounted) return;
    final url = '${m['url']}';
    final sid = '${m['session'] ?? ''}';
    if (url.isEmpty || sid.isEmpty) return;
    // Cold-start taps can race _loadInstances — make sure the list is in before
    // resolving, then resolve the instance (and its token) from the STORE, not
    // the payload. An unknown/removed instance is ignored gracefully instead of
    // crashing the shell on a null _active.
    if (_loading) {
      final items = await _store.load();
      if (!mounted) return;
      if (_instances.isEmpty) _instances = items;
    }
    Instance? inst;
    for (final i in _instances) {
      if (i.url == url) {
        inst = i;
        break;
      }
    }
    final resolved = inst;
    if (resolved == null) {
      toast(context, 'That machine is no longer saved.', danger: true);
      return;
    }
    setState(() {
      _active = resolved;
      _client = DaemonClient(resolved.url, resolved.token);
      _sessions = null;
      _liveStatus.clear();
    });
    // AFTER setState: setClient notifies, which re-enters via
    // `_syncGlobalShellTabs` -> setState, and calling setState during setState
    // throws. Global shells are per-machine, so they reconnect here.
    _shells.setClient(_client);
    _connectEventsWatch();
    _openSession(sid, '${m['title'] ?? 'session'}', null);
    _loadSessions();
  }

  Future<void> _loadInstances() async {
    final items = await _store.load();
    if (!mounted) return;
    setState(() {
      _instances = items;
      _active ??= items.isNotEmpty ? items.first : null;
      _client =
          _active != null ? DaemonClient(_active!.url, _active!.token) : null;
      _loading = false;
    });
    // Wire the daemon-wide shell socket on COLD START too. `_selectInstance` and
    // `_onNotif` already do this; skipping it here left the Terminal tab with no
    // `/shells` connection, so a shell created from the sidebar was an optimistic
    // local row with no pty behind it — a black pane with only a caret.
    _shells.setClient(_client);
    await _restoreTabs(items);
    _ensurePinnedMissionControl();
    _connectEventsWatch();
    _loadSessions();
    _refreshHealth();
  }

  Future<void> _refreshHealth() async {
    await Future.wait(_instances.map((i) async {
      final ok = await DaemonClient(i.url, i.token).health();
      if (mounted && _health[i.url] != ok) setState(() => _health[i.url] = ok);
    }));
  }

  Future<void> _loadSessions() async {
    final c = _client;
    if (c == null) {
      setState(() => _sessions = <SessionInfo>[]);
      return;
    }
    setState(() => _sessionsLoading = true);
    try {
      final s = await c.sessions(limit: 60);
      // A slow response for a PREVIOUS instance must not render under (or route
      // taps to) the one selected since.
      if (!identical(c, _client)) return;
      // Mission Control stays pinned at the top of the list; leftover titled
      // chats that alias it are still collapsed so it isn't listed twice.
      // Agent inboxes are mailboxes, never human chat sessions.
      s.removeWhere((row) =>
          (isMissionControlListRow(row) && !isDedicatedMcSession(row.id)) ||
          isInboxSessionRow(row));
      s.sort((a, b) {
        final am = isDedicatedMcSession(a.id);
        final bm = isDedicatedMcSession(b.id);
        if (am != bm) return am ? -1 : 1;
        return b.lastActive.compareTo(a.lastActive);
      });
      _applyLiveStatus(s);
      if (mounted) {
        setState(() {
          _sessions = s;
          _sessionsLoading = false;
          _sessionsError = null;
        });
      }
      // Decoration only, fired after the list is already on screen. Kept out of
      // the request above so a coordination outage can never blank the list.
    } catch (_) {
      // Unreachable daemon must not masquerade as "No chats yet" — surface it.
      if (identical(c, _client) && mounted) {
        setState(() {
          _sessionsLoading = false;
          _sessionsError =
              'Can\'t reach this machine — check the daemon/tunnel.';
        });
      }
    }
  }


  // Start a chat by picking a folder using NewSessionPicker on both desktop and mobile.
  Future<void> _newSessionFlow() async {
    final c = _client;
    final active = _active;
    if (c == null) return;
    await presentScreen(
      context,
      style: PanelStyle.dialog,
      // Wider and shorter than a default dialog: this is a folder BROWSER, so
      // horizontal room is what buys legibility (deep paths and long folder
      // names), while extra height only stretched a list that rarely fills it —
      // leaving a tall empty box around short content.
      maxWidth: 440,
      maxHeight: 500,
      builder: (_, close) => NewSessionPicker(
        client: c,
        machineLabel: active?.label ?? '',
        // Deliberately NOT `_activeWorkspaceFolder()`. This picker is the entry
        // point for a NEW conversation and must stand on its own: inheriting the
        // open session's workspace both implied a dependency on one existing and
        // silently narrowed where a new chat could start. Null lets the daemon
        // answer with its home directory, which is the sane default.
        startPath: null,
        onClose: close,
        onOpenFolder: (folder) async {
          try {
            final id = await c.openSession(folder, newConversation: true);
            _openSession(id, 'New session', null);
            _loadSessions();
          } catch (e) {
            // Surfaced by the picker as a toast; keep the screen open so the
            // folder choice is not lost on a transient failure.
            if (mounted) toast(context, '$e', danger: true);
            rethrow;
          }
          close();
        },
      ),
    );
  }

  void _selectInstance(Instance inst) {
    setState(() {
      _active = inst;
      _client = DaemonClient(inst.url, inst.token);
      _sessions = null;
      _liveStatus.clear();
    });
    // See `_onInboundShare`: must follow the setState block.
    _shells.setClient(_client);
    _ensurePinnedMissionControl();
    _connectEventsWatch();
    _loadSessions();
  }

  void _openSession(String id, String title, String? profile,
      {SharedInbound? share}) {
    if (isMissionControlTab(sessionId: id, title: title)) {
      _openMissionControlTab();
      _attachShareToActive(share);
      return;
    }
    final client = _client;
    final url = _active?.url;
    if (client == null || url == null) return;
    final existing =
        _tabs.indexWhere((t) => t.instanceUrl == url && t.sessionId == id);
    setState(() {
      if (existing >= 0) {
        _tabs[existing].title = title;
        _tabs[existing].profile = profile;
        if (share != null) _tabs[existing].inboundShare = share;
        _activeIndex = existing;
      } else {
        _tabs.add(_ShellTab.session(
            client: client,
            instanceUrl: url,
            sessionId: id,
            title: title,
            profile: profile,
            inboundShare: share));
        _activeIndex = _tabs.length - 1;
      }
      final root = _tabs[_activeIndex];
      _groupRootKey[root.pane] = root.key;
      _activeKey[root.pane] = root.key;
      if (kMobile) {
        _mobileChatsOpen = false;
        _pushMobileRoute(_MobileRoute(
          home: _mobileHome,
          agent: _mobileAgent,
          settingsSection: _mobileSettingsSection,
          inSession: true,
          sessionTabIndex: _activeIndex,
        ));
      }
    });
    _persistTabs();
    _syncPage();
  }

  void _onSessionTitle(String sessionId, String title) {
    if (title.trim().isEmpty) return;
    var changed = false;
    for (final t in _tabs) {
      if (t.sessionId == sessionId && t.title != title) {
        t.title = title;
        changed = true;
      }
    }
    final sessions = _sessions;
    if (sessions != null) {
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].id == sessionId && sessions[i].title != title) {
          sessions[i] = sessions[i].withTitle(title);
          changed = true;
        }
      }
    }
    if (!changed) return;
    if (mounted) setState(() {});
    _persistTabs();
  }

  void _attachShareToActive(SharedInbound? share) {
    if (share == null) return;
    final i = _activeIndex;
    if (i < 0 || i >= _tabs.length) return;
    setState(() => _tabs[i].inboundShare = share);
  }

  List<_ShellTab> _shareTargets() {
    final url = _active?.url;
    if (url == null) return const [];
    final seen = <String>{};
    final out = <_ShellTab>[];
    for (final t in _tabs) {
      if (t.isFile || t.instanceUrl != url || t.sessionId == null) continue;
      if (!seen.add(t.key)) continue;
      out.add(t);
    }
    return out;
  }

  Future<void> _onInboundShare(SharedInbound share) async {
    if (!mounted || share.isEmpty) return;
    final client = _client;
    if (client == null) {
      if (mounted) toast(context, 'Add a machine first.', danger: true);
      return;
    }
    if (_sessions == null || _sessions!.isEmpty) {
      await _loadSessions();
      if (!mounted) return;
    }
    final cached = List<SessionInfo>.from(_sessions ?? const []);
    final open = _shareTargets();
    final openIds = {
      for (final t in open)
        if (!t.isMissionControl) t.sessionId,
    };
    final rest = cached.where((s) => !openIds.contains(s.id)).toList();
    final picked = await showInboundSharePicker(
      context: context,
      openTabs: open,
      restSessions: rest,
      machineLabel: _active?.label ?? 'this machine',
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    if (picked == 'mission-control') {
      _openSession('mission-control', 'Mission Control', null, share: share);
      return;
    }
    SessionInfo? match;
    for (final s in cached) {
      if (s.id == picked) {
        match = s;
        break;
      }
    }
    _openSession(picked, match?.title ?? 'session', match?.profile,
        share: share);
  }

  void _openFileTab(DaemonClient client, String url, String path, String name) {
    final pane = _focusedPane;
    final group = _activeGroupKeyFor(pane);
    if (group == null) return;
    final existing = _tabs.indexWhere(
        (t) => t.isFile && t.instanceUrl == url && t.filePath == path);
    setState(() {
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

  /// Open one changed file as a tab, so a git diff reads in the same main-pane
  /// tab system as a chat or a file. Previously the sidebar rows did nothing.
  void _openDiffTab(
    DaemonClient client,
    String url,
    String sessionId,
    GitFile f,
  ) {
    final pane = _focusedPane;
    final group = _activeGroupKeyFor(pane);
    if (group == null) return;
    // Staged-only files show the index diff; anything else shows the worktree
    // diff — the same rule the full Git screen uses.
    final staged = f.staged && !f.unstaged;
    final name = lastPathSegment(f.path, ifEmpty: f.path);
    final existing = _tabs.indexWhere((t) =>
        t.isDiff &&
        t.instanceUrl == url &&
        t.diffPath == f.path &&
        t.diffStaged == staged);
    setState(() {
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

  // Full-screen on phones (QR scan); a compact natural-height dialog on
  // desktop (paste; Esc dismisses, Enter submits).
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
    setState(() {
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
    setState(() => _instances = items);
    _selectInstance(inst);
    _refreshHealth();
  }

  Future<void> _removeInstance(Instance inst) async {
    final items = [..._instances]..removeWhere((e) => e.url == inst.url);
    await _store.save(items);
    if (!mounted) return;
    setState(() {
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

  Widget _sidebar({VoidCallback? onAfterPick, bool topInset = true}) =>
      ShellSidebarHost(
        effectiveSection: _effectiveSection,
        shells: _shells.shells,
        focusShellId: _shells.focusId,
        activeWorkspaceFolder: _activeWorkspaceFolder(),
        client: _client,
        activeInstance: _active,
        activeTab: _activeTab,
        sidebarGit: _sidebarGit,
        onCloseGit: () => setState(() => _sidebarGit = false),
        onNewTerminal: _newGlobalShell,
        onOpenTerminal: (idx) {
          final s = _shells.shells;
          if (idx >= 0 && idx < s.length) _focusGlobalShell(s[idx].id);
        },
        onCloseTerminal: _closeGlobalShell,
        onOpenRightAgent: _openRightAgent,
        onOpenSession: (id, title, profile) => _openSession(id, title, profile),
        onOpenDiff: (f) {
          final c = _client;
          if (c != null) {
            _openDiffTab(c, _active?.url ?? '', _activeTab?.sessionId ?? '', f);
          }
        },
        onOpenFile: (path, name) {
          final c = _client;
          if (c != null) {
            _openFileTab(c, _active?.url ?? '', path, name);
          }
        },
        topInset: topInset,
        onAfterPick: onAfterPick,
        instances: _instances,
        selectedSessionId: _sessionId,
        sessions: _sessions,
        sessionsLoading: _sessionsLoading,
        sessionsError: _sessionsError,
        onRefreshSessions: _loadSessions,
        onSessionAction: _dispatchSessionAction,
        onNewSession: _newSessionFlow,
        onSelectInstance: _selectInstance,
        onOpenMissionControl: _openMissionControlTab,
        onAddInstance: _addInstanceFlow,
        onRenameInstance: _renameInstance,
        onRemoveInstance: _removeInstance,
        onSessionDeleted: _onSessionDeleted,
        health: _health,
        onRefreshHealth: _refreshHealth,
        mobileHome: _mobileHome,
        onMobileHome: (h) => setState(() {
          _mobileHome = h;
          _mobileSettingsSection = null;
          _mobileAgent = null;
          _pushMobileRoute(_MobileRoute(home: h));
        }),
        mobileSettingsSection: _mobileSettingsSection,
        onSettingsSection: (s) {
          if (s == null) {
            _handleMobileBack();
          } else {
            setState(() {
              _mobileSettingsSection = s;
              _pushMobileRoute(_MobileRoute(
                  home: _MobileHome.settings, settingsSection: s));
            });
          }
        },
        mobileAgent: _mobileAgent,
        onMobileAgent: (a) {
          if (a == null) {
            _handleMobileBack();
          } else {
            setState(() {
              _mobileAgent = a;
              _pushMobileRoute(
                  _MobileRoute(home: _MobileHome.agents, agent: a));
            });
          }
        },
        onSettingsClose: () {
          _handleMobileBack();
        },
      );

  void _onSessionDeleted(String id) {
    if (isDedicatedMcSession(id)) return;
    final i = _tabs.indexWhere((t) => t.sessionId == id);
    if (i >= 0) _closeTab(i);
    _loadSessions();
  }

  void _dispatchSessionAction(String action, [String? extra]) {
    final key = _activeTab?.key;
    if (key == null) return;
    _macSessionControls[key]?.performAction(action, extra);
    if (_drawerOpen) _scaffoldKey.currentState?.closeDrawer();
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

  final _topMachineKey = GlobalKey();

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

  bool get _canNavigateBack => _activeIndex > 0;
  bool get _canNavigateForward =>
      _activeIndex >= 0 && _activeIndex < _tabs.length - 1;

  void _navigateBack() {
    if (_canNavigateBack) _activateTab(_activeIndex - 1);
  }

  void _navigateForward() {
    if (_canNavigateForward) _activateTab(_activeIndex + 1);
  }

  /// Activate a MAIN workspace tab by identity.
  ///
  /// Identity, not index: the window bar lists `_mainTabs`, so the chip's
  /// position there is not its position in `_tabs`.
  void _activateTabAt(_ShellTab t) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _activateTab(i);
  }

  /// The main workspace tab strip: the chips plus the new-session button.
  ///
  /// Hosted by the window bar on macOS, and by a row above the panes on a plain
  /// desktop that has no window bar of its own — so both show the same strip
  /// instead of one silently lacking tabs.
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


  void _showMobileChats() {
    if (!kMobile) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_handleMobileBack()) {
      setState(() {
        _mobileChatsOpen = true;
      });
    }
  }

  Widget _mobileShell() {
    final tab = _activeTab;
    return MobileShell(
      activeTabBody: tab != null ? _tabBody(tab, primary: true) : null,
      sidebar: _sidebar(
        topInset: false,
        onAfterPick: () {
          if (_tabs.isNotEmpty) {
            setState(() {
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
        setState(() {
          _mobileHome = home;
          _mobileSettingsSection = null;
          _mobileAgent = null;
          _pushMobileRoute(_MobileRoute(home: home));
        });
      },
      onCloseChats: () {
        if (_tabs.isNotEmpty) {
          setState(() {
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg3))),
      );
    }
    if (kMobile) return _mobileShell();
    return LayoutBuilder(builder: (context, c) {
      // Narrow window → keep the native shell but collapse the sidebar to a drawer.
      if (c.maxWidth < kShellCompact) {
        // Full-width drawer on phones; a capped one on a shrunk desktop window.
        final drawerW =
            kMobile ? c.maxWidth : (c.maxWidth * 0.86).clamp(280.0, 360.0);
        // Back from an open session: reveal the sessions drawer FIRST, then a
        // second back exits. (Only intercept when a session is open and the drawer
        // is closed; from the open drawer or the home placeholder, back exits.)
        return PopScope(
          canPop: _drawerOpen || _sessionId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _scaffoldKey.currentState?.openDrawer();
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            onDrawerChanged: (open) => setState(() => _drawerOpen = open),
            // Keep drawer gestures confined to the physical edge. A wide edge
            // target competes with fast, slightly angled transcript scrolling.
            drawerEdgeDragWidth: kMobile ? 20 : 24,
            drawer: Drawer(
              width: drawerW,
              backgroundColor: AppColors.windowBg,
              shape: const RoundedRectangleBorder(),
              child: SafeArea(
                  child: _sidebar(
                      topInset: !kMacOS,
                      onAfterPick: () =>
                          _scaffoldKey.currentState?.closeDrawer())),
            ),
            // Narrow: the toolbar's sidebar-toggle is at the far left under the
            // traffic lights, so inset the whole pane below them.
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: kMacOS ? kMacTitlebar : 0),
                child: _mainPane(
                    onMenu: () => _scaffoldKey.currentState?.openDrawer()),
              ),
            ),
          ),
        );
      }
      // Wide macOS uses a persistent sidebar column beside the content column.
      // The tab strip belongs only to the content pane, so the sidebar can use
      // the full height below the native title bar without an empty header gap.
      if (kMacOS) {
        return Scaffold(
          // The window paints the chrome surface; the reading pane inside it is
          // the darker canvas.
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(children: [
              _macWindowBar(),
              // The navigation band is a shell-level row: full window width,
              // directly between the title bar and the body.
              ShellRail(
                section: _effectiveSection,
                onSelect: (s) => setState(() => _section = s),
                tools: _railTools(),
                hidden: _hiddenSections,
              ),
              _bodyRow(topInset: false),
            ]),
          ),
        );
      }

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(children: [
            // The navigation band is a shell-level row: full window width,
            // directly above the body.
            ShellRail(
              section: _effectiveSection,
              onSelect: (s) => setState(() => _section = s),
              tools: _railTools(),
              hidden: _hiddenSections,
            ),
            _bodyRow(topInset: true),
          ]),
        ),
      );
    });
  }


  /// Body for one tab.
  ///
  /// Shared by the main pane and the secondary pane so a tab kind cannot render
  /// in one and silently not the other. [primary] gates the extras that only
  /// the focused pane should own — file drops and inbound shares — since two
  /// mounted copies would both ingest the same drop.
  Widget _tabBody(_ShellTab t, {required bool primary}) {
    if (t.isTerminal) {
      // A GLOBAL shell (no session key) renders from the controller, which owns
      // its own socket — that is what makes it survive switching sessions.
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
      // A SESSION shell: the session owns the pty and the view wiring; this tab
      // is only a placement. Rendering goes through its host so the terminal
      // cannot be captured twice.
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
          : () => setState(() => t.inboundShare = null),
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
      // Desktop only: Scheduled opens as a right-pane readout. The shell owns
      // the panes, so the session routes through here; on a phone the callback
      // is null and the session falls back to its own drawer.
      onOpenScheduled:
          !kMobile ? () => _toggleRightPanel(_RightPanel.recurring) : null,
    );
  }

  /// Sidebar + main pane + optional secondary pane.
  ///
  /// A single drop target wraps the row: dropping a dragged tab (including one
  /// dragged onto the right-hand side, which is where the second pane appears)
  /// moves it into the secondary pane. Shared by the macOS and plain layouts so
  /// the two cannot diverge.
  /// Whether a tab is auxiliary (pane-docked content) rather than a workspace.
  ///
  /// Used ONLY to decide what the window bar lists. A pane's own strip shows
  /// every tab docked in it, of any kind — including the session itself.
  bool _isAuxiliary(_ShellTab t) => t.isTerminal || t.isFile || t.isDiff;

  /// Main workspace tabs, in strip order. Rendered in the window bar.
  List<_ShellTab> get _mainTabs => [
        for (final t in _tabs)
          if (!_isAuxiliary(t)) t,
      ];

  /// Root-session identity for the inner tab group displayed by [p].
  /// Every group is anchored by one always-open conversation; files, diffs and
  /// terminals are merely sibling content tabs in that group.
  ///
  /// The stored assignment stops counting once it no longer names a tab living
  /// in THIS pane — the normal state after a session is dragged to the other
  /// pane, since the key it left behind names a session this pane no longer
  /// holds. Falling through to the active tab (which `_activeTab` guarantees is
  /// non-auxiliary) supplies the anchor it should then have, and a pane with
  /// neither is rootless, which `_tabsIn` handles by showing content only.
  String? _groupRootFor(_Pane p) {
    final stored = _groupRootKey[p];
    if (stored != null && _tabs.any((t) => t.key == stored && t.pane == p)) {
      return stored;
    }
    final active = _activeTab;
    return active != null && active.pane == p ? active.key : null;
  }

  /// Items in one nested tab group. The root is deliberately first and locked;
  /// the rest are user-opened files, diffs and terminals for that conversation.
  ///
  /// A pane with NO root still lists whatever is docked in it, but ONLY its
  /// auxiliary content. Both halves of that rule earn their keep:
  ///
  ///  - A file or terminal dragged into the secondary pane must still render.
  ///    It keeps the `groupSessionKey` of the conversation it came from, which
  ///    lives in the LEFT pane — so `_groupRootFor(right)` is null, and a strip
  ///    that required a root returned nothing. The tab vanished and `showRight`
  ///    then collapsed the very pane it had just been dropped into.
  ///  - But a pane whose SESSION was dragged out keeps no root either. Admitting
  ///    every docked tab there made it re-render a workspace tab the window bar
  ///    already owns, filling the pane with a duplicate of a top-level tab.
  ///
  /// Rootless therefore means content-only; see [paneTabBelongsInGroup].
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

  /// The pane holding the focused tab. Drives drops, inbound shares, and keyboard
  /// actions like closing tabs.
  _Pane get _focusedPane {
    if (_rightCollapsed) return _Pane.left;
    if (_activePane == _Pane.right) {
      final rightHasContent = _tabsIn(_Pane.right).isNotEmpty ||
          _rightTabs.any((r) => r.pane == _Pane.right);
      if (rightHasContent) return _Pane.right;
    }
    return _activeTab?.pane ?? _Pane.left;
  }

  /// Make a tab its pane's active tab, and the shell's focused tab.
  void _activateIn(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activePane = p;
      _activeKey[p] = tab.key;
      // Selecting a nested item also selects its one locked session root. The
      // inner strip therefore never turns into a rootless bag of files.
      final root =
          _isAuxiliary(tab) ? tab.groupSessionKey ?? _groupRootFor(p) : tab.key;
      if (root != null) _groupRootKey[p] = root;
      // `_activeIndex` tracks the MAIN workspace tab — the window bar's
      // selection. Choosing an auxiliary tab in a pane is per-pane and must not
      // move the window bar's highlight.
      if (!_isAuxiliary(tab)) _activeIndex = i;
    });
    _persistTabs();
    _syncPage();
  }

  /// Move a tab into a pane — what a drop on that pane does.
  ///
  /// Refuses to empty a pane: dragging a pane's last tab to the pane it is
  /// already in is a no-op, not a way to blank a container.
  void _moveTo(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    if (tab.pane == p) return;
    // Read the destination's group BEFORE mutating. After the move this tab can
    // itself become the fallback root (`_groupRootFor` falls back to the active
    // tab), which would make the lookup self-referential.
    final targetRoot = _groupRootFor(p);
    setState(() {
      _activePane = p;
      tab.pane = p;
      // Moving an AUXILIARY tab is a pane concern; it must not drag the window
      // bar's selection with it.
      if (!_isAuxiliary(tab)) _activeIndex = i;

      // RE-PARENT into the destination pane's group.
      //
      // A tab carries the `groupSessionKey` of the pane it came FROM. That key
      // matches no root in the destination, and `_tabsIn(p)` keeps a tab only
      // when it IS the root or shares its group — so the moved tab was filtered
      // out of the strip entirely and appeared to vanish behind the tabs already
      // docked there.
      //
      // A moved SESSION becomes the pane's root (it is a root by definition); a
      // moved auxiliary tab adopts the destination's root so it renders as a
      // sibling of that conversation.
      if (_isAuxiliary(tab)) {
        if (targetRoot != null) {
          tab.groupSessionKey = targetRoot;
          _groupRootKey[p] = targetRoot;
        } else {
          // Destination has no root: keep the tab's own group so it still
          // belongs to its conversation rather than becoming an orphan.
          _groupRootKey[p] = tab.groupSessionKey ?? tab.key;
        }
      } else {
        _groupRootKey[p] = tab.key;
        tab.groupSessionKey = null;
      }

      // Docking reveals the pane: a drop into a collapsed pane would otherwise
      // land somewhere invisible.
      _dockAux(p, tab.key);
    });
    _persistTabs();
  }

  /// Select an auxiliary tab in a pane, revealing that pane.
  ///
  /// Opening a terminal, preview or diff into a COLLAPSED pane would otherwise
  /// place it somewhere invisible: the content exists, but nothing shows it and
  /// the new tab looks like it did nothing. Docking always reveals.
  void _dockAux(_Pane p, String key) {
    _activePane = p;
    _activeKey[p] = key;
    if (p == _Pane.right) {
      // Reveal the pane. Docked `_ShellTab`s take precedence over readouts in
      // `_paneView` (it renders `_tabsIn(p)` whenever it is non-empty), so the
      // readout list is left intact and reappears if the docked tabs close.
      _rightCollapsed = false;
    }
  }

  /// Close a tab by identity, from either pane's strip.
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
        setState(() => _activeKey[pane] = key);
      }
    }
  }

  /// Close a tab by IDENTITY. Identity, not index: the window bar lists
  /// `_mainTabs`, so a chip's position there is not its position in `_tabs`.
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
        onPaneResize: (delta) => setState(() {
          final max = MediaQuery.sizeOf(context).width * 0.72;
          _paneWidth = (_paneWidth - delta).clamp(kPaneMinWidth, max);
        }),
        onExpandPane: (p) => setState(() {
          if (p == _Pane.left) {
            _leftCollapsed = false;
          } else {
            _rightCollapsed = false;
          }
        }),
        onMoveTab: _moveTo,
        onMoveReadout: _moveReadout,
        onActivateTab: _activateIn,
        onActivateReadout: (p, r) => setState(() => _activeKey[p] = r.key),
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
    setState(() {
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

  /// The sidebar is the only shell creator. Its controller listener adds the
  /// acknowledged shell to the active inner group exactly once.
  void _newGlobalShell() {
    final root = _activeTab;
    if (root == null) return;
    final s = _shells.create();
    setState(() {
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

  /// Bring a global shell forward. Its owning session becomes the selected
  /// inner group, but its daemon pty is never recreated or killed.
  void _focusGlobalShell(String id) {
    _shells.focus(id);
    for (final t in _tabs) {
      if (t.isTerminal && t.termSessionKey == null && t.termId == id) {
        final root = _tabs.firstWhere(
          (candidate) => candidate.key == t.groupSessionKey,
          orElse: () => t,
        );
        final i = _tabs.indexOf(root);
        setState(() {
          if (!_isAuxiliary(root) && i >= 0) _activeIndex = i;
          // Re-opening a shell the user had dismissed from a pane un-hides it,
          // so picking it in the Terminals panel always brings it back.
          _hiddenTabs.remove(t.key);
          _groupRootKey[t.pane] = root.key;
          _activeKey[t.pane] = t.key;
        });
        _syncPage();
        return;
      }
    }
  }

  /// Destroy a global shell. Sidebar-only, matching the rule that a shell is
  /// created and destroyed here and never from a pane.
  void _closeGlobalShell(String id) {
    _shells.close(id);
    _syncGlobalShellTabs();
  }

  /// Mirror daemon shells into their existing session-owned tab. Shells adopted
  /// after a reconnect are attached to the active session once; a duplicate
  /// legacy tab for the same pty is discarded, never rendered twice.
  void _syncGlobalShellTabs() {
    if (!mounted) return;
    final live = {for (final s in _shells.shells) s.id: s};
    var changed = false;
    setState(() {
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

  /// Hide ONE terminal view without touching the pane that holds it.
  ///
  /// The pty stays alive in the daemon and the shell stays listed in the
  /// Terminals panel, so opening it again re-docks the same view instantly.
  /// Re-opening from the sidebar clears the flag through [_focusGlobalShell].
  void _hideTabView(_Pane p, _ShellTab t) {
    setState(() {
      _hiddenTabs.add(t.key);
      // If the hidden view was the pane's selection, fall back to another tab
      // in that pane (or the pane's default surface) rather than a blank slot.
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
          setState(() => _activeIndex = i);
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


  /// Settings, opened from the shell's status line. The sidebar has its own
  /// opener for the machine popover; this one exists so the status bar does not
  /// have to reach into a child's state.
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

  /// The second line of a desktop tab. File tabs show their folder; the
  /// Mission Control pin reads as orchestration; sessions show the workspace.
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
}

typedef _MachineList = MachineList;
typedef _SettingsPanel = SettingsPanel;
typedef _SettingsPage = SettingsPage;

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
