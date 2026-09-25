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

part 'desktop_shell_mobile.dart';
part 'desktop_shell_panes.dart';
part 'desktop_shell_tabs.dart';

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
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

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

  final List<_MobileRoute> _mobileRouteHistory = [
    const _MobileRoute(home: MobileHome.agents),
  ];

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


  Timer? _persistTabsDebounce;

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

  final _topMachineKey = GlobalKey();


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

}

typedef _MachineList = MachineList;
typedef _SettingsPanel = SettingsPanel;
typedef _SettingsPage = SettingsPage;

