import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

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
import 'models.dart';
import 'processes.dart';
import 'usage.dart';
import 'vault.dart';
import 'recurring.dart';
import 'agents_sidebar_panel.dart';
import 'terminals_sidebar_panel.dart';
import 'mission_control/coordination_activity_screen.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'git_diff_sidebar_panel.dart';
import 'file_tree_sidebar_panel.dart';
import 'session.dart';
import 'session_panels.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';
import 'mission_control.dart';

/// Desktop two-pane shell: a persistent left sidebar (instances + sessions) and
/// a main pane showing the selected session. Tools (git/files/editor/models)
/// open as floating panels/drawers from within the session, or the sidebar.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

/// Which pane a tab lives in. Both panes are tab containers, so this is a
/// property OF a tab, not of the shell — dragging a tab across the divider is
/// what moves it.
enum _Pane { left, right }

/// One open tab in the shell — a live chat session, an opened file, a single git
/// change, or a terminal, on a given instance.
///
/// Terminals are tabs like anything else, because the nested space is a tab
/// container: opening a second terminal gives you a second tab, not a second
/// app-wide pane.
class _ShellTab {
  final DaemonClient client;
  final String instanceUrl;
  final String? sessionId;
  final String? filePath;
  String title;
  String? profile;
  SharedInbound? inboundShare;

  /// Which pane this tab is shown in. Mutable: this is what a drag changes.
  _Pane pane;

  /// The locked conversation root of the inner tab group this item belongs to.
  /// A group shows exactly one session root; its files, diffs and terminals sit
  /// alongside it in the full-width strip. Null is only valid for a session
  /// root itself, or for a legacy item that will be adopted by the active root.
  String? groupSessionKey;

  /// Set only for a diff tab: the changed file plus the view it should show.
  /// A staged-only file reads the index diff; an untracked one shows as an add.
  final String? diffPath;
  final bool diffStaged;
  final bool diffUntracked;

  /// Set only for a terminal tab.
  ///
  /// [termSessionKey] is the shell key of the session that owns the pty when the
  /// shell is SESSION-scoped. It is NULL for a daemon-wide shell, which belongs
  /// to the machine rather than a conversation — those render from
  /// `ShellsController` over `/shells`.
  final String? termId;
  final String? termSessionKey;

  _ShellTab.session({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.title,
    this.profile,
    this.inboundShare,
    this.pane = _Pane.left,
    this.groupSessionKey,
  })  : filePath = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false,
        termId = null,
        termSessionKey = null;
  _ShellTab.file({
    required this.client,
    required this.instanceUrl,
    required this.filePath,
    required this.title,
    this.pane = _Pane.left,
    this.groupSessionKey,
  })  : sessionId = null,
        profile = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false,
        termId = null,
        termSessionKey = null;
  _ShellTab.diff({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.diffPath,
    required this.title,
    required this.diffStaged,
    required this.diffUntracked,
    this.pane = _Pane.left,
    this.groupSessionKey,
  })  : filePath = null,
        profile = null,
        termId = null,
        termSessionKey = null;
  _ShellTab.terminal({
    required this.client,
    required this.instanceUrl,
    required this.termId,
    required this.title,
    this.termSessionKey,
    this.pane = _Pane.left,
    this.groupSessionKey,
  })  : sessionId = null,
        filePath = null,
        profile = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false;

  bool get isFile => filePath != null;
  bool get isDiff => diffPath != null;
  bool get isTerminal => termId != null;
  bool get isMissionControl =>
      !isFile &&
      !isDiff &&
      !isTerminal &&
      isMissionControlTab(sessionId: sessionId, title: title);
  String get key => isTerminal
      ? '$instanceUrl|term|${termSessionKey ?? 'global'}|$termId'
      : isDiff
          ? '$instanceUrl|diff|$diffPath|$diffStaged'
          : isFile
              ? '$instanceUrl|file|$filePath'
              : isMissionControl
                  ? '$instanceUrl|mission-control'
                  : '$instanceUrl|$sessionId';
}

/// Icon for a tab, by kind. One helper so the four call sites that render a
/// tab (top bar, desktop strip, split header, tab menu) cannot drift.
String _tabIconKind(_ShellTab t) => t.isMissionControl
    ? 'layers'
    : t.isTerminal
        ? 'terminal'
        : t.isDiff
            ? 'git-branch'
            : t.isFile
                ? 'file'
                : 'chat-thread';

class _MacSessionStatus {
  final HarnessState? state;
  final bool running;
  const _MacSessionStatus(this.state, this.running);
}

class _MacSessionControls {
  final VoidCallback stop;
  final void Function(String action, [String? extra]) performAction;
  const _MacSessionControls(this.stop, this.performAction);
}

/// Session readouts that render in the secondary pane.
///
/// These were drawers. A drawer covers the transcript, but Lanes / Checkpoints /
/// Usage are exactly the things you check WHILE reading a session — so they
/// belong beside it, and tapping the same band button again closes the pane.
enum _RightPanel {
  none('', ''),
  lanes('Lanes', 'layers'),
  checkpoints('Checkpoints', 'history'),
  usage('Usage', 'activity');

  const _RightPanel(this.label, this.icon);
  final String label;
  final String icon;
}

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
  bool _sidebarGit = false;

  /// Secondary-pane width, dragged by its handle. Width-driven rather than a
  /// flex ratio because a flex ratio cannot be dragged and has no natural size.
  double _paneWidth = kPaneDefaultWidth;

  /// Whether the pointer is over the 6px resize zone. The visible separator is
  /// always present as a 0.5px hairline and brightens on hover.
  bool _paneHandleHover = false;

  /// Which contextual sidebar the rail is showing. Purely a shell concern: the
  /// conversation you're reading stays put while this changes.
  ShellSection _section = ShellSection.sessions;

  /// Detail shown in the right pane. Null = pane hidden, so the transcript gets
  /// the full width until something asks for detail — a pane that is always
  /// present would cost space even when nothing needs inspecting.
  CoordinationAgent? _rightAgent;

  /// Session readouts that render in the secondary pane instead of a drawer.
  ///
  /// Lanes, Checkpoints and Usage are things you glance at WHILE reading the
  /// transcript, so a modal was the wrong shape for them — it covered the very
  /// context you were checking against. A readout is exclusive with a
  /// right-pane TAB: opening one yields the pane, and dropping a tab there
  /// dismisses the readout.
  _RightPanel _rightPanel = _RightPanel.none;

  /// The user collapsed a pane. Hiding a pane is always a view action and never
  /// destroys anything — a terminal tab lives on in the sidebar, and its pty
  /// stays alive, so re-opening is instant.
  bool _rightCollapsed = false;
  bool _leftCollapsed = false;

  /// Which tab each pane is showing, keyed by pane. Separate from `_activeIndex`
  /// so the two containers keep independent selections.
  final Map<_Pane, String> _activeKey = {};

  /// Root session selected for each inner tab group. A root is always present as
  /// that group's first, locked tab; its files, diffs and terminals reference it
  /// through `_ShellTab.groupSessionKey`.
  final Map<_Pane, String> _groupRootKey = {};

  /// Show a session panel in the pane, or close it if it is already showing.
  void _toggleRightPanel(_RightPanel p) {
    setState(() {
      _rightAgent = null;
      _rightCollapsed = false;
      _rightPanel = _rightPanel == p ? _RightPanel.none : p;
    });
  }

  /// Collapse the right pane without touching whatever is in it.
  ///
  /// Never destroys: a terminal tab lives on in the sidebar and its pty stays
  /// alive, so re-opening is instant and loses no scrollback.
  void _closeSplitPane() {
    setState(() {
      _rightCollapsed = true;
      _rightAgent = null;
      _rightPanel = _RightPanel.none;
    });
  }

  /// The button list at the far right of the navigation band.
  ///
  /// Same shape as the icon strip over the sidebar, per the steer. Carries the
  /// session-scoped actions the removed bottom strip held — but ONLY what the
  /// LHS panels do NOT provide: Git, Files and Terminals have panels of their
  /// own, so repeating them here would be two doors to one room.
  ///
  /// Approval is a TOGGLE: the button shows its state and flips it inline, since
  /// a popover to flip a boolean is pure friction. Goal opens an anchored
  /// popover for its text. Lanes, Checkpoints and Usage render in the pane.
  List<Widget> _railTools() {
    final tab = _activeTab;
    final mc = tab?.isMissionControl ?? false;
    final s = tab == null ? null : _macSessionStatuses[tab.key]?.state;
    final goalRunning = s?.goal?.ongoing ?? false;
    final lanes = s?.lanes.where((l) => l.running).length ?? 0;

    return [
      Builder(
        builder: (ctx) => _railTool('goal',
            tooltip: goalRunning ? 'Cancel goal' : 'Set goal',
            active: goalRunning,
            onTap: tab == null
                ? null
                : (goalRunning
                    ? () => _dispatchSessionAction('goal')
                    : () => _openGoalPopover(ctx))),
      ),
      _railTool('layers',
          tooltip: 'Lanes',
          active: _rightPanel == _RightPanel.lanes,
          badge: lanes > 0 ? '$lanes' : null,
          onTap:
              tab == null ? null : () => _toggleRightPanel(_RightPanel.lanes)),
      _railTool('history',
          tooltip: 'Checkpoints',
          active: _rightPanel == _RightPanel.checkpoints,
          onTap: tab == null
              ? null
              : () => _toggleRightPanel(_RightPanel.checkpoints)),
      _railTool('activity',
          tooltip: 'Usage',
          active: _rightPanel == _RightPanel.usage,
          onTap:
              tab == null ? null : () => _toggleRightPanel(_RightPanel.usage)),
      if (mc)
        Builder(
          builder: (ctx) => _railTool('more-horizontal',
              tooltip: 'Mission Control actions',
              onTap: () => _openShellMenu(ctx)),
        ),
    ];
  }

  /// One 24px button in the band, with an optional count badge.
  Widget _railTool(
    String icon, {
    required String tooltip,
    required VoidCallback? onTap,
    bool active = false,
    String? badge,
  }) {
    final button = IconBtn(icon,
        size: 28, iconSize: 15, active: active, tooltip: tooltip, onTap: onTap);
    if (badge == null) return button;
    return Stack(clipBehavior: Clip.none, children: [
      button,
      Positioned(
        right: 1,
        top: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(badge, style: mono(9, color: AppColors.fg2)),
        ),
      ),
    ]);
  }

  /// Anchored goal field, under its button in the band.
  Future<void> _openGoalPopover(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    const width = 320.0;
    final screen = MediaQuery.sizeOf(context).width;
    final left =
        (origin.dx + box.size.width - width).clamp(8.0, screen - width - 8);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'goal',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => Stack(children: [
        Positioned(
          left: left,
          top: origin.dy + box.size.height + 6,
          width: width,
          child: Material(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.md),
            elevation: 12,
            shadowColor: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _GoalPopover(
                onSet: (text) {
                  Navigator.pop(context);
                  _dispatchSessionAction('goal', text);
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openShellMenu(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final sel = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 4,
        // Right-align the menu under the button, with an 8px screen margin.
        (MediaQuery.sizeOf(context).width - origin.dx - box.size.width)
            .clamp(8.0, double.infinity),
        0,
      ),
      color: AppColors.surface3,
      items: _shellMenuItems(),
    );
    sel?.call();
  }

  /// Menu rows for everything the LHS panels do not cover.
  List<PopupMenuEntry<VoidCallback>> _shellMenuItems() {
    final tab = _activeTab;
    final mc = tab?.isMissionControl ?? false;
    final controls = tab == null ? null : _macSessionControls[tab.key];
    final s = tab == null ? null : _macSessionStatuses[tab.key]?.state;
    final manual = (s?.approvalMode ?? 'auto') == 'manual';

    PopupMenuItem<VoidCallback> item(String icon, String label, String action,
            {String? extra, String? value}) =>
        appMenuItem(
          value: () => controls?.performAction(action, extra),
          icon: icon,
          label: label,
          detail: value,
        );
    PopupMenuItem<VoidCallback> run(
            String icon, String label, VoidCallback fn) =>
        appMenuItem(value: fn, icon: icon, label: label);

    final items = <PopupMenuEntry<VoidCallback>>[];

    // ---- Session ----
    if (mc) {
      items.add(item('layers', 'Tasks', 'tasks'));
      items.add(item('users', 'Agents', 'agents'));
      items.add(item('coordination', 'Coordination board', 'coordination'));
      items.add(
          item('activity', 'Coordination activity', 'coordination_activity'));
    } else {
      items.add(item('edit', 'Rename session', 'rename'));
      items.add(item('shield', 'Approval: Auto', 'approval_auto',
          value: manual ? null : 'on'));
      items.add(item('shield', 'Approval: Ask', 'approval_ask',
          value: manual ? 'on' : null));
      final goal = s?.goal;
      if (goal?.ongoing ?? false) {
        items.add(goal!.paused
            ? item('play', 'Resume goal', 'resume_goal', value: 'paused')
            : item('zap', 'Cancel goal', 'goal', value: 'running'));
      } else {
        items.add(item('zap', 'Set goal', 'goal'));
      }
      if (s?.lanes.isNotEmpty ?? false) {
        items.add(item('layers', 'Lanes', 'lanes',
            value: '${s!.lanes.where((l) => l.running).length} running'));
      }
      items.add(item('scheduled', 'Scheduled', 'recurring'));
    }

    // ---- History ----
    items.add(const PopupMenuDivider());
    items.add(item('minimize', 'Compact history', 'compact'));
    if (!mc) items.add(item('history', 'Checkpoints', 'checkpoints'));
    items.add(item('activity', 'Usage', 'usage'));

    return items;
  }

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
    if (!kMobile)
      HardwareKeyboard.instance.removeHandler(_handleGlobalShortcuts);
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

  bool _mod(LogicalKeyboardKey left, LogicalKeyboardKey right) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(left) || keys.contains(right);
  }

  bool get _metaDown =>
      _mod(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight);
  bool get _ctrlDown =>
      _mod(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight);
  bool get _altDown =>
      _mod(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight);
  bool get _shiftDown =>
      _mod(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
  bool get _cmdOrCtrl => _metaDown || _ctrlDown;

  /// Tab / window chords must not depend on Focus staying on the shell.
  /// Clicking a tab, a message, or the composer steals focus and used to
  /// kill Ctrl+Tab and Cmd+W after the first use.
  bool _handleGlobalShortcuts(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!_cmdOrCtrl) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyW && !_shiftDown && !_altDown) {
      if (_activeIndex >= 0) _closeTab(_activeIndex);
      return true;
    }
    if (key == LogicalKeyboardKey.keyT && !_shiftDown && !_altDown) {
      _newSessionFlow();
      return true;
    }
    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.pageDown) &&
        _ctrlDown &&
        !_altDown &&
        !_metaDown) {
      _activateRelativeTab(_shiftDown ? -1 : 1);
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp &&
        _ctrlDown &&
        !_altDown &&
        !_metaDown) {
      _activateRelativeTab(-1);
      return true;
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        _altDown) {
      _activateRelativeTab(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && _shiftDown && !_altDown) {
      _openActiveFiles();
      return true;
    }
    if (key == LogicalKeyboardKey.keyG && _shiftDown && !_altDown) {
      _openMacGit();
      return true;
    }
    if (key == LogicalKeyboardKey.period && !_shiftDown && !_altDown) {
      _macSessionControls[_activeTab?.key]?.stop();
      return true;
    }
    if (key == LogicalKeyboardKey.slash && !_shiftDown && !_altDown) {
      _showDesktopShortcuts();
      return true;
    }
    for (var i = 0; i < 9; i++) {
      if (key.keyId == LogicalKeyboardKey.digit1.keyId + i &&
          !_shiftDown &&
          !_altDown) {
        _activateTab(i);
        return true;
      }
    }
    return false;
  }

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
          if (generation != _eventsGeneration || !identical(ch, _eventsChannel))
            return;
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

  String? _macBranchLabel() {
    final branch = _macGit?.branch.trim();
    return branch == null || branch.isEmpty ? null : branch;
  }

  String _macChangeLabel() {
    final git = _macGit;
    if (git == null || git.clean || git.files.isEmpty) return '';
    return '${git.files.length} change${git.files.length == 1 ? '' : 's'}';
  }

  // Bring the active tab's chip into view in the strip.
  void _scrollStripToActive() {
    final t = _activeTab;
    if (t == null) return;
    final ctx = _chipKeys[t.key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut);
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
      if (kMobile) setState(() => _mobileChatsOpen = false);
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(children: [
              AppIcon(t.isFile ? 'file' : 'terminal',
                  size: 15, color: AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.title.isEmpty ? '(untitled)' : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: AppColors.fg1)),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          if (!t.isMissionControl)
            _tabMenuItem(ctx, 'x', 'Close tab', () => _closeTab(i)),
          if (_tabs.any((tab) => !tab.isMissionControl))
            _tabMenuItem(
                ctx, 'copy', 'Close other tabs', () => _closeOthers(i)),
          if (_tabs.any((tab) => !tab.isMissionControl))
            _tabMenuItem(ctx, 'trash', 'Close all tabs', _closeAllTabs,
                danger: true),
        ]),
      ),
    );
  }

  Widget _tabMenuItem(
      BuildContext ctx, String icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? AppColors.danger : AppColors.fg1;
    return InkWell(
      onTap: () {
        Navigator.of(ctx).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          AppIcon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Text(label, style: sans(13.5, color: color)),
        ]),
      ),
    );
  }

  /// An inner tab group is session-rooted: only user-opened supporting content
  /// can be closed. The session root is permanent for the lifetime of its group.
  bool _canCloseTab(_ShellTab t) => _isAuxiliary(t) && !t.isTerminal;

  void _closeTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    if (!_canCloseTab(_tabs[i])) return;
    final key = _tabs[i].key;
    setState(() {
      _clearTabState(key);
      // A pane selection pointing at a tab that no longer exists would leave
      // that pane blank instead of falling back to its default content.
      _activeKey.removeWhere((_, k) => k == key);
      _tabs.removeAt(i);
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
      // The window bar switches the selected nested group, not merely the
      // highlight: the conversation becomes the locked first item in its own
      // full-width inner strip.
      _groupRootKey[tab.pane] = tab.key;
      _activeKey[tab.pane] = tab.key;
    });
    _persistTabs();
    _syncPage();
  }

  void _activateRelativeTab(int delta) {
    if (_tabs.length < 2 || _activeIndex < 0) return;
    final next = (_activeIndex + delta) % _tabs.length;
    _activateTab(next < 0 ? next + _tabs.length : next);
  }

  void _openActiveFiles() =>
      _macSessionControls[_activeTab?.key]?.performAction('files');

  void _showDesktopShortcuts() {
    showAppSheet(
      context,
      title: 'Keyboard shortcuts',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _shortcutRow('⌘/Ctrl T', 'New session'),
        _shortcutRow('⌘/Ctrl W', 'Close active tab'),
        _shortcutRow('⌘/Ctrl 1–9', 'Switch to tab'),
        _shortcutRow('⌘ ⌥ ← / → · Ctrl Tab · Ctrl PageUp/PageDown',
            'Previous / next tab'),
        _shortcutRow('⌘/Ctrl ⇧ F', 'Browse files'),
        _shortcutRow('⌘/Ctrl ⇧ G', 'Open Git'),
        _shortcutRow('⌘/Ctrl .', 'Stop active run'),
        _shortcutRow('⌘/Ctrl Enter', 'Send message'),
      ]),
    );
  }

  Widget _shortcutRow(String keys, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label, style: sans(13, color: AppColors.fg1))),
          Text(keys, style: mono(11.5, color: AppColors.fg3)),
        ]),
      );

  Widget _desktopShortcuts(Widget child) {
    // Chords are handled globally in _handleGlobalShortcuts so they keep
    // working after a tab click or composer focus steal.
    return child;
  }

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
      s.removeWhere((row) =>
          isMissionControlListRow(row) && !isDedicatedMcSession(row.id));
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

  // Start a chat by browsing to a folder in the file explorer and tapping
  // "New chat here" — the explorer doubles as the new-chat picker.
  Future<void> _newSessionFlow() async {
    final c = _client;
    final active = _active;
    if (c == null) return;
    await presentScreen(
      context,
      style: PanelStyle.drawer,
      maxWidth: 1060,
      maxHeight: 760,
      builder: (_, close) => FileExplorer(
        client: c,
        title: active?.label ?? 'Files',
        onClose: close,
        onOpenFile: (path, name) {
          close();
          if (active != null) {
            _openFileTab(c, active.url, path, name);
          }
        },
        onNewChat: (folder) async {
          try {
            final id = await c.openSession(folder, newConversation: true);
            _openSession(id, 'New session', null);
            _loadSessions();
          } catch (e) {
            if (mounted) toast(context, '$e', danger: true);
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
      if (kMobile) _mobileChatsOpen = false;
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
    final picked = await showAppSheet<String>(
      context,
      title: 'Send to',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in open)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon(_tabIconKind(t),
                  size: 18,
                  color: t.isMissionControl ? AppColors.accent : AppColors.fg3),
              title: Text(
                  t.isMissionControl
                      ? 'Mission Control'
                      : (t.title.trim().isEmpty ? '(untitled)' : t.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15,
                      weight: t.isMissionControl
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: AppColors.fg1)),
              subtitle: Text(
                  t.isMissionControl
                      ? (_active?.label ?? 'this machine')
                      : 'Open tab',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4)),
              onTap: () => Navigator.pop(context,
                  t.isMissionControl ? 'mission-control' : t.sessionId),
            ),
          if (open.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon('layers', size: 18, color: AppColors.accent),
              title: Text('Mission Control',
                  style: sans(15, weight: W.label, color: AppColors.fg1)),
              subtitle: Text(_active?.label ?? 'this machine',
                  style: sans(12, color: AppColors.fg4)),
              onTap: () => Navigator.pop(context, 'mission-control'),
            ),
          for (final s in rest)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon('terminal', size: 18, color: AppColors.fg3),
              title: Text(s.title.trim().isEmpty ? '(untitled)' : s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, color: AppColors.fg1)),
              subtitle: Text(s.folder.trim().isEmpty ? 'session' : s.folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4)),
              onTap: () => Navigator.pop(context, s.id),
            ),
        ],
      ),
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
    final i = _tabs.indexWhere((t) => t.key == key);
    if (i >= 0) _closeTab(i);
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

  Widget _sidebar({VoidCallback? onAfterPick, bool topInset = true}) {
    final tab = _activeTab;
    Widget panel;
    // The rail switches which panel occupies the sidebar. Git stays a mode of
    // the sessions panel — you inspect a session's diff, not the agent list.
    if (_section == ShellSection.terminal) {
      // DAEMON-WIDE shells, not the session's. A shell belongs to the machine, so
      // this panel is the same list whichever session is open — and it is the
      // only place a shell is created or destroyed.
      final shells = _shells.shells;
      panel = TerminalsSidebarPanel(
        workspacePath: _activeWorkspaceFolder() ?? '',
        terminals: [
          for (final s in shells)
            TerminalInfo(
              id: s.id,
              title: s.title,
              alive: s.alive,
              live: s.live,
            ),
        ],
        focus: shells.indexWhere((s) => s.id == _shells.focusId),
        onNewTerminal: _newGlobalShell,
        onOpenTerminal: (idx) {
          if (idx < 0 || idx >= shells.length) return;
          _focusGlobalShell(shells[idx].id);
        },
        onCloseTerminal: _closeGlobalShell,
      );
    } else if (_section == ShellSection.agents) {
      final client = _client;
      panel = client == null
          ? _sidebarUnavailable('Add a machine to see its agents.')
          : AgentsSidebarPanel(
              client: client,
              onOpenAgent: (a) => setState(() => _rightAgent = a),
            );
    } else if (_section == ShellSection.git) {
      final client = _client;
      panel = client == null
          ? _sidebarUnavailable('Add a machine to see Git diff.')
          : GitDiffSidebarPanel(
              client: client,
              workspacePath: _activeWorkspaceFolder() ?? '',
              sessionId: _activeTab?.sessionId,
              // Open the change as a tab in the main pane, so a diff reads in
              // the same tab system as a chat or a file.
              onOpenDiff: (f) => _openDiffTab(
                client,
                _active?.url ?? '',
                _activeTab?.sessionId ?? '',
                f,
              ),
            );
    } else if (_section == ShellSection.files) {
      final client = _client;
      panel = client == null
          ? _sidebarUnavailable('Add a machine to browse its files.')
          : FileTreeSidebarPanel(
              client: client,
              workspacePath: _activeWorkspaceFolder() ?? '',
              onOpenFile: (path, name) =>
                  _openFileTab(client, _active?.url ?? '', path, name),
            );
    } else if (_sidebarGit && tab != null && !tab.isFile) {
      final path = tab.filePath;
      final slash = path?.lastIndexOf('/') ?? -1;
      final folder =
          path != null && slash > 0 ? path.substring(0, slash) : null;
      panel = Container(
        color: AppColors.surface1,
        child: GitScreen(
          client: tab.client,
          sessionId: tab.sessionId ?? '',
          folder: folder,
          embedded: true,
          onClose: () => setState(() => _sidebarGit = false),
        ),
      );
    } else {
      panel = _Sidebar(
        topInset: topInset,
        instances: _instances,
        active: _active,
        client: _client,
        selectedSessionId: _sessionId,
        sessions: _sessions,
        sessionsLoading: _sessionsLoading,
        sessionsError: _sessionsError,
        onRefreshSessions: _loadSessions,
        onSessionAction: _dispatchSessionAction,
        onNewSession: () {
          _newSessionFlow();
          onAfterPick?.call();
        },
        onSelectInstance: _selectInstance,
        onOpenMissionControl: () {
          _openMissionControlTab();
          onAfterPick?.call();
        },
        onOpenSession: (id, title, profile) {
          _openSession(id, title, profile);
          onAfterPick?.call();
        },
        onAddInstance: _addInstanceFlow,
        onRenameInstance: _renameInstance,
        onRemoveInstance: _removeInstance,
        onSessionDeleted: _onSessionDeleted,
        health: _health,
        onRefreshHealth: _refreshHealth,
      );
    }

    return panel;
  }

  Widget _sidebarUnavailable(String message) => Container(
        color: AppColors.bg,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child:
            Text(message, style: sans(12.5, color: AppColors.fg4, height: 1.5)),
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

  Widget _macNavigationBar() {
    final tab = _activeTab;
    final controls = tab == null ? null : _macSessionControls[tab.key];
    final running = _macSessionStatuses[tab?.key]?.running ?? false;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(child: _tabList()),
        if (tab != null && tab.isFile) ...[
          IconBtn('download',
              size: 26,
              iconSize: 12,
              tooltip: 'Download',
              onTap: _downloadActiveFile),
          IconBtn('edit',
              size: 26, iconSize: 12, tooltip: 'Edit', onTap: _editActiveFile),
        ] else if (controls != null) ...[
          if (running)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconBtn('stop',
                  size: 26,
                  iconSize: 12,
                  tooltip: 'Stop running task',
                  onTap: controls.stop),
            ),
        ],
        IconBtn('plus',
            size: 26,
            iconSize: 13,
            tooltip: 'New session',
            onTap: _newSessionFlow),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _macWindowBar() {
    // `fullSizeContentView` does not expose the native titlebar inset through
    // MediaQuery, so that value is false even while traffic lights are visible.
    // Ask AppKit instead; reserve their full hit area until native fullscreen
    // confirms that macOS has removed them.
    return FutureBuilder<bool>(
      future: macOSIsFullscreen(),
      builder: (context, snapshot) =>
          _macWindowBarContent(hasWindowControls: snapshot.data != true),
    );
  }

  Widget _macWindowBarContent({required bool hasWindowControls}) {
    return SizedBox(
      // Taller than AppKit's own band. At 28px this crushed the tabs; the
      // reference runs a 40px bar with 32px tabs on its bottom edge, and the
      // native traffic lights are nudged down to stay centred.
      height: kTitleBarHeight,
      child: ColoredBox(
        // The window/title bar sits on the floor surface (#0D0D0D) while the
        // body below is the lighter chrome (#171717) — that step is what makes
        // the active tab read as connected to the strip.
        color: AppColors.floor,
        child: Padding(
          padding: EdgeInsets.only(
            left: hasWindowControls ? kTrafficLightReserve : 16,
            right: 20,
          ),
          child: Row(
            // Children fill the bar's full height: the tab strip then sits on
            // the bottom edge and merges into the band below it (the browser
            // silhouette), while the utility controls centre in the same band.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back/Forward navigation arrows
                    IconBtn(
                      'chevron-left',
                      size: 24,
                      iconSize: 16,
                      tooltip: 'Back',
                      onTap: _canNavigateBack ? _navigateBack : null,
                    ),
                    IconBtn(
                      'chevron-right',
                      size: 24,
                      iconSize: 16,
                      tooltip: 'Forward',
                      onTap: _canNavigateForward ? _navigateForward : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Main workspace tabs: the conversations and Mission Control.
              //
              // Auxiliary content — terminals, previewed files, diffs — is docked
              // in a PANE and listed by that pane's own strip, so the two strips
              // never show the same tab. Naming what you are working on is the
              // window bar's job.
              Expanded(
                child: Center(child: _mainTabsRow()),
              ),
              const SizedBox(width: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Right-side utilities: settings and the active machine
                    // avatar. Checkpoints remain in a session's Actions/History.
                    IconBtn(
                      'settings',
                      size: 24,
                      iconSize: 16,
                      tooltip: 'Settings',
                      onTap: _openShellSettings,
                    ),
                    const SizedBox(width: 6),
                    _topMachineSwitcher(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final _topMachineKey = GlobalKey();

  Widget _topMachineSwitcher() {
    final a = _active;
    final ok = a == null ? null : _health[a.url];
    final initial = a == null || a.label.trim().isEmpty
        ? '+'
        : a.label.trim().characters.first.toUpperCase();
    return Tooltip(
      message: a == null ? 'Add machine' : 'Switch machine',
      child: Material(
        key: _topMachineKey,
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: _instances.isEmpty ? _addInstanceFlow : _openTopMachines,
          customBorder: const CircleBorder(),
          child: SizedBox(
            // Fits inside the 28px title bar with margin to spare.
            width: 26,
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border2),
                    ),
                    child: Text(
                      initial,
                      style: sans(10.5, weight: W.title, color: AppColors.fg1),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: ok == true ? AppColors.ok : AppColors.fg4,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTopMachines() async {
    _refreshHealth();
    final content = _MachineList(
      instances: _instances,
      active: _active,
      health: _health,
      onSelect: _selectInstance,
      onAdd: _addInstanceFlow,
      onManage: _manageMachine,
    );
    final box = _topMachineKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'machines',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => Stack(children: [
        Positioned(
          right:
              (MediaQuery.of(context).size.width - origin.dx - box.size.width)
                  .clamp(10.0, 500.0),
          top: origin.dy + box.size.height + 4,
          width: 260,
          child: Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            elevation: 12,
            shadowColor: Colors.black87,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
              ),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }

  void _manageMachine(Instance i) {
    showAppSheet(
      context,
      title: i.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: AppIcon('edit', size: 16, color: AppColors.fg2),
            title: Text('Rename', style: sans(14, color: AppColors.fg1)),
            onTap: () async {
              Navigator.pop(context);
              final name = await promptText(context,
                  title: 'Rename machine',
                  initial: i.label,
                  hint: 'Machine name',
                  saveLabel: 'Rename');
              if (name != null && name.isNotEmpty) {
                _renameInstance(i, name);
              }
            },
          ),
          ListTile(
            leading: AppIcon('trash', size: 16, color: AppColors.danger),
            title: Text('Remove', style: sans(14, color: AppColors.danger)),
            onTap: () async {
              Navigator.pop(context);
              final ok = await confirmAction(
                context,
                title: 'Remove machine?',
                body:
                    '${i.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
                confirmLabel: 'Remove',
              );
              if (ok) _removeInstance(i);
            },
          ),
        ],
      ),
    );
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

  /// Top-level workspace tab chip in the window bar.
  /// The chip that follows the pointer while a tab is being dragged into the
  /// secondary pane.
  Widget _tabDragFeedback(_ShellTab t) => Material(
        color: Colors.transparent,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(_tabIconKind(t), size: 13, color: AppColors.accent),
            const SizedBox(width: 7),
            Text(t.title.isEmpty ? '(untitled)' : t.title,
                style: sans(12.5, color: AppColors.fg1)),
          ]),
        ),
      );

  /// Activate a MAIN workspace tab by identity.
  ///
  /// Identity, not index: the window bar lists `_mainTabs`, so the chip's
  /// position there is not its position in `_tabs`.
  void _activateTabAt(_ShellTab t) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _activateTab(i);
  }

  /// A MAIN workspace tab chip in the window bar.
  ///
  /// Separate from `_paneTabChip` on purpose: this strip lists the
  /// conversations and Mission Control — what the window bar names — while a
  /// pane strip lists the auxiliary content docked beside it. One chip is never
  /// rendered by both.
  Widget _topWorkspaceTab(_ShellTab t) {
    final isActive = t == _activeTab;
    final title = t.title.isEmpty ? '(untitled)' : t.title;
    // Same key map the narrow strip uses; the two strips are mutually
    // exclusive (the window bar is wide-macOS only), so they cannot collide.
    final key = _chipKeys.putIfAbsent(t.key, () => GlobalKey());

    return GestureDetector(
      onTap: () => _activateTabAt(t),
      child: Container(
        key: key,
        // Bottom-aligned in the taller bar: the active tab is filled with the
        // band colour below and shows only rounded top corners, so it merges
        // into the navigation band the way a browser tab merges into a page.
        height: kTitleTabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.bg : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.md)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(_tabIconKind(t),
                size: 18, color: isActive ? AppColors.fg2 : AppColors.fg4),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14,
                    weight: isActive ? W.label : W.body,
                    color: isActive ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (_canCloseTab(t)) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _closePaneTab(t),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AppIcon('x', size: 13, color: AppColors.fg4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The main workspace tab strip: the chips plus the new-session button.
  ///
  /// Hosted by the window bar on macOS, and by a row above the panes on a plain
  /// desktop that has no window bar of its own — so both show the same strip
  /// instead of one silently lacking tabs.
  Widget _mainTabsRow() => ListView(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        // Horizontal padding only; the host bar owns the vertical alignment.
        padding: const EdgeInsets.only(right: 4),
        children: [
          for (final t in _mainTabs) ...[
            _topWorkspaceTab(t),
            const SizedBox(width: 4),
          ],
          Center(
            child: IconBtn('plus',
                size: 24,
                iconSize: 16,
                tooltip: 'New session',
                onTap: _newSessionFlow),
          ),
        ],
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

  void _openMacGit() {
    setState(() => _sidebarGit = !_sidebarGit);
  }

  void _showMobileChats() {
    if (!kMobile) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _mobileChatsOpen = true);
  }

  Widget _mobileShell() {
    final tab = _activeTab;
    // Chats is ALSO the visible surface whenever no session is active. Without
    // the `tab == null` arm, closing the last tab (or deleting the open session
    // from elsewhere) would leave the panel parked off-screen with no session
    // behind it: a blank screen with nothing owning back.
    final chatsVisible = _mobileChatsOpen || tab == null;
    final shell = Scaffold(
      backgroundColor: chatsVisible ? AppColors.bg : readingBg,
      body: Stack(children: [
        // The session sits UNDERNEATH and stays fully drawn. The Chats panel
        // slides over it and reveals it again on the way out, so there is no
        // fade-through or blank frame during the transition.
        if (tab != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: chatsVisible,
              child: SafeArea(
                bottom: false,
                child: _tabBody(tab, primary: true),
              ),
            ),
          ),
        // Full-screen panel that slides in from the left edge, covering the
        // whole width — Discord's channel-panel behaviour. `Offset(-1, 0)` parks
        // it entirely off-screen when closed, so it never half-covers the
        // session; `Positioned.fill` makes it span the full width rather than
        // shrink-wrapping its content.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !chatsVisible,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: chatsVisible ? Offset.zero : const Offset(-1, 0),
              child: Material(
                color: AppColors.bg,
                child: SafeArea(
                  child: _sidebar(
                    topInset: false,
                    onAfterPick: () => setState(() => _mobileChatsOpen = false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );

    // Back has exactly ONE owner per state. Every PopScope on a route receives
    // the callback, so registering two would run both on a single press — one
    // would close the terminal and the other would jump to Chats.
    //
    // Session open → the SESSION owns back (see SessionScreen): its ladder
    // closes the actions drawer, then the terminal overlay, then returns here.
    // It passes `mobileActive` so its guard is absent whenever Chats is showing.
    if (!chatsVisible) return shell;

    // Chats on screen → the shell IS the app root. Background the app so a
    // running watcher service keeps working, rather than finishing the activity.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await watcherServiceRunning()) {
          minimizeApp();
        } else {
          SystemNavigator.pop();
        }
      },
      child: shell,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_loading) {
      return Scaffold(
        backgroundColor: readingBg,
        body: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg3))),
      );
    }
    if (kMobile) return _mobileShell();
    return _desktopShortcuts(LayoutBuilder(builder: (context, c) {
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
            backgroundColor: readingBg,
            onDrawerChanged: (open) => setState(() => _drawerOpen = open),
            // Keep drawer gestures confined to the physical edge. A wide edge
            // target competes with fast, slightly angled transcript scrolling.
            drawerEdgeDragWidth: kMobile ? 20 : 24,
            drawer: Drawer(
              width: drawerW,
              backgroundColor: AppColors.bg,
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
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Column(children: [
              _macWindowBar(),
              // The navigation band is a shell-level row: full window width,
              // directly between the title bar and the body.
              ShellRail(
                section: _section,
                onSelect: (s) => setState(() => _section = s),
                tools: _railTools(),
              ),
              _bodyRow(topInset: false),
            ]),
          ),
        );
      }

      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(children: [
            // The navigation band is a shell-level row: full window width,
            // directly above the body.
            ShellRail(
              section: _section,
              onSelect: (s) => setState(() => _section = s),
              tools: _railTools(),
            ),
            _bodyRow(topInset: true),
          ]),
        ),
      );
    }));
  }

  /// Both desktop panes share the same canvas. Their separation is a foreground
  /// hairline: the left pane owns the sidebar/content boundary for its full
  /// height, while [_paneResizeHandle] owns the continuous split divider.
  ///
  /// Only the OUTER top corners take a radius — the left pane's top-left and the
  /// right pane's top-right. The inner corners stay square so the two panes meet
  /// flush at the divider instead of showing two rounded notches, and
  /// [roundRight] is false for the left pane whenever a right pane is open.
  Widget _paneSurface(
    _Pane pane, {
    required Widget child,
    bool roundRight = false,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.only(
            topLeft: pane == _Pane.left
                ? const Radius.circular(R.sheetTop)
                : Radius.zero,
            topRight:
                roundRight ? const Radius.circular(R.sheetTop) : Radius.zero,
          ),
        ),
        // Requires the decoration above: Flutter asserts on a non-default
        // clipBehavior without one.
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          child,
          if (pane == _Pane.left)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: kPaneHairline,
                  color: kPaneSeamColor,
                ),
              ),
            ),
        ]),
      );

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
  String? _groupRootFor(_Pane p) {
    final root = _groupRootKey[p];
    if (root != null && _tabs.any((t) => t.key == root && t.pane == p)) {
      return root;
    }
    final active = _activeTab;
    return active?.pane == p ? active?.key : null;
  }

  /// Items in one nested tab group. The root is deliberately first and locked;
  /// the rest are user-opened files, diffs and terminals for that conversation.
  List<_ShellTab> _tabsIn(_Pane p) {
    final root = _groupRootFor(p);
    if (root == null) return const <_ShellTab>[];
    return [
      for (final t in _tabs)
        if (t.pane == p && (t.key == root || t.groupSessionKey == root)) t,
    ];
  }

  /// The tab a pane is showing, or null when its selected group has no content.
  _ShellTab? _activeIn(_Pane p) {
    final list = _tabsIn(p);
    final key = _activeKey[p];
    if (key != null) {
      for (final t in list) {
        if (t.key == key) return t;
      }
    }
    return list.isEmpty ? null : list.first;
  }

  String? _activeGroupKeyFor(_Pane p) =>
      _groupRootFor(p) ?? (_activeTab?.pane == p ? _activeTab?.key : null);

  /// The pane holding the focused tab. Drives drops and inbound shares, so a
  /// dropped file lands in one composer rather than both.
  _Pane get _focusedPane {
    final i = _activeIndex;
    if (i >= 0 && i < _tabs.length) return _tabs[i].pane;
    return _Pane.left;
  }

  /// Make a tab its pane's active tab, and the shell's focused tab.
  void _activateIn(_Pane p, _ShellTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
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
    setState(() {
      tab.pane = p;
      // Moving an AUXILIARY tab is a pane concern; it must not drag the window
      // bar's selection with it.
      if (!_isAuxiliary(tab)) _activeIndex = i;
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
    _activeKey[p] = key;
    if (p == _Pane.right) {
      _rightCollapsed = false;
      _rightPanel = _RightPanel.none;
      _rightAgent = null;
    }
  }

  /// Close a tab by identity, from either pane's strip.
  void _closePaneTab(_ShellTab t) {
    final i = _tabs.indexOf(t);
    if (i >= 0) _closeTab(i);
  }

  /// Sidebar + the two pane containers. Both are tab containers; which tabs they
  /// hold is a property of each tab (`_ShellTab.pane`), so a drop is all it
  /// takes to move one across.
  Widget _bodyRow({required bool topInset}) {
    final rightTabs = _tabsIn(_Pane.right);
    final leftTabs = _tabsIn(_Pane.left);
    // An explicit collapse wins over content, or the collapse control would
    // appear to do nothing while a terminal is docked.
    final showRight = !_rightCollapsed &&
        (rightTabs.isNotEmpty ||
            _rightPanel != _RightPanel.none ||
            _rightAgent != null);
    // Collapsing the LEFT pane is only meaningful while it holds aux content —
    // it is also the conversation surface, which there must always be a way
    // back to.
    final showLeft = !(_leftCollapsed && leftTabs.isNotEmpty);
    return Expanded(
      child: Row(children: [
        SizedBox(
          width: kSidebarWidth,
          child: _sidebar(topInset: topInset),
        ),
        if (showLeft)
          Expanded(
            child: _dropOn(
              _Pane.left,
              // The left pane's top-RIGHT is only an outer corner when no right
              // pane is open; otherwise it meets the divider flush and square.
              _paneView(_Pane.left, roundRight: !showRight),
            ),
          )
        else
          Expanded(child: _collapsedPaneStub(_Pane.left)),
        if (showRight) ...[
          _paneResizeHandle(joinBaseline: showLeft),
          SizedBox(
            width: _paneWidth.clamp(kPaneMinWidth, double.infinity),
            child:
                _dropOn(_Pane.right, _paneView(_Pane.right, roundRight: true)),
          ),
        ],
      ]),
    );
  }

  /// A collapsed pane leaves a thin re-open affordance rather than vanishing —
  /// otherwise there is no way back to the terminals docked inside it.
  Widget _collapsedPaneStub(_Pane p) => Center(
        child: IconBtn('chevron-right',
            size: 28,
            iconSize: 14,
            tooltip: 'Show pane',
            onTap: () => setState(() {
                  if (p == _Pane.left) {
                    _leftCollapsed = false;
                  } else {
                    _rightCollapsed = false;
                  }
                })),
      );

  /// A pane is a drop target for a tab dragged out of any strip.
  Widget _dropOn(_Pane p, Widget child) => DragTarget<_ShellTab>(
        onWillAcceptWithDetails: (d) => d.data.pane != p,
        onAcceptWithDetails: (d) => _moveTo(p, d.data),
        builder: (_, __, ___) => child,
      );

  /// One pane.
  ///
  /// Its strip lists ONLY auxiliary tabs (terminals, previewed files, diffs) —
  /// the main workspace tabs live in the window bar. When no aux tab is selected
  /// the pane falls back to [fallback]: the conversation in the left pane, the
  /// readout in the right.
  /// One pane: its own tab strip, then its content.
  ///
  /// Content STACKS every tab docked here with only the active one laid out.
  /// That is a correctness requirement, not an optimisation: a `SessionScreen`
  /// owns its ptys, so unmounting one on a tab switch would kill its terminals.
  /// The same applies to a terminal tab, whose `TerminalHost` lives in the
  /// session that owns it.
  Widget _paneView(_Pane p, {bool roundRight = false}) {
    final list = _tabsIn(p);
    final active = _activeIn(p);

    Widget content;
    if (list.isEmpty) {
      // Nothing docked: the pane's own default surface.
      content = _paneFallback(p);
    } else {
      content = Stack(children: [
        for (final t in list)
          Offstage(
            offstage: t != active,
            child: _tabBody(
              t,
              // `primary` gates file drops and inbound shares. Several sessions
              // can be mounted at once, so exactly one may claim them: the
              // active tab, in the focused pane.
              primary: t == active && _focusedPane == p,
            ),
          ),
      ]);
    }

    return _paneSurface(
      p,
      roundRight: roundRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The strip renders whenever this pane hosts tabs, so there is always
          // a way to switch between them and to re-open a collapsed one.
          if (list.isNotEmpty) _paneStrip(p, list),
          Expanded(child: content),
        ],
      ),
    );
  }

  /// What a pane shows when nothing is docked in it.
  Widget _paneFallback(_Pane p) {
    if (p == _Pane.right) {
      if (_rightPanel != _RightPanel.none) return _rightPanelView();
      if (_rightAgent != null) {
        return CoordinationAgentDetail(
          agent: _rightAgent!,
          embedded: true,
          onClose: _closeSplitPane,
        );
      }
      return _emptyPaneHint();
    }
    return _client == null ? _welcome() : _recentPlaceholder();
  }

  /// Joined pane-tab construction: tabs meet directly on one shared
  /// near-background baseline, with the active tab marked by a solid white top
  /// edge. A session root stays a capped, locked first tab; supporting tabs are
  /// larger bounded frames with their close action inside the tab itself.
  Widget _paneStrip(_Pane p, List<_ShellTab> list) {
    final active = _activeIn(p);
    return Container(
      height: kPaneHeaderHeight,
      color: AppColors.canvas,
      child: Stack(fit: StackFit.expand, children: [
        LayoutBuilder(builder: (context, c) {
          final w = kPaneTabWidth(c.maxWidth, list.length);
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox.shrink(),
            itemBuilder: (_, i) =>
                _paneTabChip(p, list[i], list[i] == active, w),
          );
        }),
        // Foreground baseline: the ListView paints over the container's own
        // decoration, so the strip rule must be laid on top of the tabs.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(height: kPaneHairline, color: kPaneSeamColor),
          ),
        ),
      ]),
    );
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

  /// Hide a pane. Never destroys: a terminal tab lives on in the sidebar and its
  /// pty stays alive, so re-opening is instant.
  void _collapsePane(_Pane p) {
    setState(() {
      if (p == _Pane.right) {
        _rightCollapsed = true;
      } else {
        _leftCollapsed = true;
      }
    });
  }

  Widget _paneTabChip(_Pane p, _ShellTab t, bool active, double width) {
    final canDismiss = _canCloseTab(t) || t.isTerminal;
    void dismiss() {
      // Closing a terminal tab only hides this pane view. Its pty remains alive
      // and traceable from the Terminals panel; file/diff tabs close normally.
      if (t.isTerminal) {
        _collapsePane(p);
      } else {
        _closePaneTab(t);
      }
    }

    final chip = GestureDetector(
      onTap: () => _activateIn(p, t),
      child: SizedBox(
        width: width,
        child: Container(
          height: kPaneTabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Every tab carries the SAME hairline top border, so selection cannot
          // move anything. The active tab's heavier stroke is a
          // `foregroundDecoration`: it paints above the child and takes no part
          // in layout. A thicker `Border` would inset only the active tab and
          // jog its label by the width difference on every tab switch.
          decoration: BoxDecoration(
            color: AppColors.canvas,
            border: Border(
              right: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
              top: BorderSide(color: kPaneSeamColor, width: kPaneHairline),
            ),
          ),
          foregroundDecoration: !active
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppColors.fg1, width: kPaneActiveStroke),
                  ),
                ),
          child: Row(children: [
            AppIcon(_tabIconKind(t),
                size: 14, color: active ? AppColors.fg2 : AppColors.fg4),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.title.isEmpty ? '(untitled)' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kPaneTabText,
                    weight: active ? W.label : W.body,
                    color: active ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (canDismiss) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: dismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AppIcon('x', size: 11, color: AppColors.fg4),
                ),
              ),
            ],
          ]),
        ),
      ),
    );

    // Dragging a chip to the other pane moves the tab. Long-press because the
    // strip scrolls horizontally and a plain drag would fight that gesture.
    return LongPressDraggable<_ShellTab>(
      data: t,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _tabDragFeedback(t),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: chip,
    );
  }

  Widget _emptyPaneHint() => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Drag a tab here, or open a terminal from the sidebar.',
            style: sans(12.5, color: AppColors.fg4)),
      );

  /// The single shared divider between the two panes. It is one line, not a
  /// per-pane edge, which is what keeps the boundary continuous when both panes
  /// are open — and the wider hit zone makes that same line the resize target.
  /// When [joinBaseline] is set, a horizontal segment also crosses the handle at
  /// the pane strips' baseline height. Without it the left and right strips each
  /// end at their own edge and the boundary reads as two separate borders.
  Widget _paneResizeHandle({bool joinBaseline = false}) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _paneHandleHover = true),
        onExit: (_) => setState(() => _paneHandleHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            setState(() {
              // Dragging left GROWS the right pane, hence the negation.
              final max = MediaQuery.sizeOf(context).width * 0.72;
              _paneWidth = (_paneWidth - d.delta.dx).clamp(kPaneMinWidth, max);
            });
          },
          child: SizedBox(
            width: kPaneSplitHandleWidth,
            child: Stack(children: [
              Center(
                child: SizedBox(
                  width: kPaneHairline,
                  height: double.infinity,
                  child: ColoredBox(
                    color:
                        _paneHandleHover ? kPaneSeamHoverColor : kPaneSeamColor,
                  ),
                ),
              ),
              // Carry the strips' baseline across the handle, so the two pane
              // tab rows read as one boundary rather than two separate edges.
              if (joinBaseline)
                Positioned(
                  left: 0,
                  right: 0,
                  top: kPaneHeaderHeight - kPaneHairline,
                  child: IgnorePointer(
                    child: Container(
                      height: kPaneHairline,
                      color: kPaneSeamColor,
                    ),
                  ),
                ),
              // …and carry the strips' top edge across too: without this the two
              // panes are each bounded on top but leave a gap between them.
              if (joinBaseline)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: kPaneHairline,
                      color: kPaneSeamColor,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );

  /// A session readout in the pane: Lanes, Checkpoints or Usage.
  ///
  /// Content comes from the shared panel widgets so the pane and the session's
  /// drawer can never show a different view of the same thing.
  Widget _rightPanelView() {
    final tab = _activeTab;
    final controls = tab == null ? null : _macSessionControls[tab.key];
    final s = tab == null ? null : _macSessionStatuses[tab.key]?.state;

    Widget body;
    switch (_rightPanel) {
      case _RightPanel.lanes:
        body = SessionLanesPanel(lanes: s?.lanes ?? const []);
        break;
      case _RightPanel.checkpoints:
        body = SessionCheckpointsPanel(
          checkpoints: s?.checkpoints.reversed.toList() ?? const [],
          // Route the action back through the session, so rewinding from the
          // pane behaves exactly as rewinding from the session's own drawer.
          onRewind: (c) => controls?.performAction('rewind', c.id),
          onFork: (c) => controls?.performAction('fork', c.id),
        );
        break;
      case _RightPanel.usage:
        body =
            s == null ? const SizedBox.shrink() : SessionUsagePanel(state: s);
        break;
      case _RightPanel.none:
        body = const SizedBox.shrink();
    }

    return Container(
      color: AppColors.canvas,
      child: Column(children: [
        PaneTabStrip(
          tabs: [
            PaneTab(
              label: _rightPanel.label,
              icon: _rightPanel.icon,
              onClose: _closeSplitPane,
            ),
          ],
          activeIndex: 0,
        ),
        Expanded(child: body),
      ]),
    );
  }

  Widget _mainPane({VoidCallback? onMenu}) {
    final client = _client;
    if (client == null) {
      return _withMenu(onMenu, _welcome());
    }
    if (_tabs.isEmpty) {
      return _withMenu(onMenu, _recentPlaceholder());
    }
    return Column(children: [
      // Narrow desktop keeps its local strip because the sidebar is a drawer.
      if (!kMacOS) _tabStrip(onMenu),
      Expanded(
        // Pane-scoped MediaQuery so window-width sizing (chat bubbles) fits the pane.
        child: LayoutBuilder(builder: (ctx, c) {
          final mq = MediaQuery.of(ctx);
          return MediaQuery(
            data: mq.copyWith(size: Size(c.maxWidth, c.maxHeight)),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Disconnect the old session's TextField as soon as a horizontal
                // page swipe starts. Waiting for onPageChanged leaves the old
                // field as the platform text-input client during the gesture.
                if (notification is ScrollStartNotification &&
                    notification.metrics.axis == Axis.horizontal) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                physics: kMobile ? null : const NeverScrollableScrollPhysics(),
                itemCount: _tabs.length,
                onPageChanged: (i) {
                  // PageView keeps each session mounted. Remove focus from the
                  // old composer before changing the active page so the platform
                  // text-input client cannot remain attached to the previous
                  // session after a swipe.
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() => _activeIndex = i);
                  _persistTabs();
                  _scrollStripToActive();
                  _refreshMacGit();
                },
                itemBuilder: (_, i) {
                  final t = _tabs[i];
                  return _KeepAlive(
                    key: ValueKey(t.key),
                    keep: t.isMissionControl || i == _activeIndex,
                    // Same body builder as the split panes, so a terminal
                    // or a diff renders identically whether it is in a pane or
                    // the narrow single-column layout.
                    child: _tabBody(t, primary: i == _activeIndex),
                  );
                },
              ),
            ),
          );
        }),
      ),
    ]);
  }

  /// Open the active session's terminal from the terminal sidebar panel.
  void _openActiveShell() {
    final key = _activeTab?.key;
    if (key == null) return;
    _macSessionControls[key]?.performAction('shell');
  }

  /// Settings, opened from the shell's status line. The sidebar has its own
  /// opener for the machine popover; this one exists so the status bar does not
  /// have to reach into a child's state.
  void _openShellSettings() {
    final c = _client;
    if (c == null) return;
    final inst = _active;
    presentScreen(context,
        maxWidth: 640,
        maxHeight: 620,
        builder: (_, close) => _SettingsPanel(
              client: c,
              instances: _instances,
              active: inst,
              onRemove: _removeInstance,
              onClose: close,
            ));
  }

  /// The tab strip:
  /// - Individual rounded tab cards (220px wide) that scroll horizontally
  /// - Plus button immediately after the tabs
  /// - On the far right: Split pane toggle [|] and Close pane [✕]
  Widget _tabList() {
    return SingleChildScrollView(
      controller: _stripController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _tabs.length; i++) _tabChip(i),
          const SizedBox(width: 4),
          IconBtn(
            'plus',
            size: 28,
            iconSize: 14,
            tooltip: 'New tab',
            onTap: _newSessionFlow,
          ),
        ],
      ),
    );
  }

  Widget _tabStrip(VoidCallback? onMenu) {
    final compact = kMobile ? M.tabStripHeight : 42.0;
    return Container(
      // No bottom border: the band's surface (#171717) against the darker panes
      // below is the separation, as everywhere else in this design language.
      height: compact,
      color: AppColors.bg,
      child: Row(children: [
        if (onMenu != null)
          IconBtn('sidebar',
              size: kMobile ? M.tabActionSize : 36,
              iconSize: kMobile ? M.tabIconSize : 16,
              tooltip: 'Sidebar',
              onTap: onMenu),
        Expanded(child: _tabList()),
        if (!kMobile && _activeTab?.isFile == true) ...[
          IconBtn('download',
              size: 32,
              iconSize: 14,
              tooltip: 'Download',
              onTap: _downloadActiveFile),
          IconBtn('edit',
              size: 32, iconSize: 14, tooltip: 'Edit', onTap: _editActiveFile),
        ],
        // No split toggle: the secondary pane appears when a tab is dragged
        // out of the strip, not from a mode button.
      ]),
    );
  }

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

  /// One tab. Sized as an individual rounded card:
  /// - Bounded width (180–240px, never stretched across the whole screen)
  /// - Dark card background `#1C1C22` when active, with subtle `#2E2E36` border
  /// - Two lines of text: bold title on top, muted subtitle/category below
  /// - Close ✕ button on right
  Widget _tabChip(int i) {
    final t = _tabs[i];
    final active = i == _activeIndex;
    final desktop = !kMobile;
    final title = t.title.isEmpty ? '(untitled)' : t.title;
    final key = _chipKeys.putIfAbsent(t.key, () => GlobalKey());

    if (!desktop) {
      return GestureDetector(
        onTap: () => _activateTab(i),
        onLongPress: () => _tabMenu(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          key: key,
          margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: active ? AppColors.border : Colors.transparent,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(
              _tabIconKind(t),
              size: 12,
              color: active ? AppColors.accent : AppColors.fg4,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    sans(12.5, color: active ? AppColors.fg1 : AppColors.fg3),
              ),
            ),
            if (_canCloseTab(t)) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _closeTab(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon('x', size: 10, color: AppColors.fg4),
                ),
              ),
            ],
          ]),
        ),
      );
    }

    // Desktop card tab: bounded width, distinct card surface, 2-line label
    return GestureDetector(
      onTap: () => _activateTab(i),
      onLongPress: () => _tabMenu(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        key: key,
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: active ? AppColors.border2 : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            AppIcon(
              _tabIconKind(t),
              size: 14,
              color: active ? AppColors.accent : AppColors.fg4,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(
                      11.5,
                      weight: active ? W.label : W.body,
                      color: active ? AppColors.fg1 : AppColors.fg3,
                    ),
                  ),
                  Text(
                    _tabSubtitle(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(10, color: AppColors.fg4),
                  ),
                ],
              ),
            ),
            if (_canCloseTab(t)) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _closeTab(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.xs),
                  ),
                  child: AppIcon('x',
                      size: 10, color: active ? AppColors.fg3 : AppColors.fg4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // No session selected → recent sessions + a New chat button (instead of a bare
  // "nothing selected" message).
  Widget _recentPlaceholder() {
    final sessions = (_sessions ?? const <SessionInfo>[]).take(8).toList();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          // Clamp the block so recent sessions stay a bounded, centered preview
          // with breathing room top/bottom instead of filling a small viewport;
          // the list scrolls within when there are more than fit.
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              Text('Recent sessions', style: display(24)),
              const SizedBox(height: 6),
              Text(
                  'Pick up where you left off, or start a new chat from Browse.',
                  style: sans(12.5, height: 1.4, color: AppColors.fg3)),
              const SizedBox(height: 18),
              if (_sessionsLoading && _sessions == null)
                Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.fg3))))
              else if (sessions.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No sessions yet.',
                        style: sans(12.5, color: AppColors.fg4)))
              else
                ...sessions.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () => _openSession(s.id, s.title, s.profile),
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.title.isEmpty ? '(untitled)' : s.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sans(13.5, color: AppColors.fg1)),
                                  const SizedBox(height: 3),
                                  Text(
                                      lastPathSegment(s.folder,
                                          ifEmpty: s.folder),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mono(10.5, color: AppColors.fg4)),
                                ]),
                          ),
                          const SizedBox(width: 8),
                          Text(relativeTime(s.lastActive),
                              style: mono(10, color: AppColors.fg4)),
                        ]),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  // When collapsed, overlay a sidebar-toggle on the welcome/empty states.
  Widget _withMenu(VoidCallback? onMenu, Widget child) {
    if (onMenu == null) return child;
    return Stack(children: [
      child,
      Positioned(
          top: 6,
          left: 6,
          child: IconBtn('sidebar',
              size: kMobile ? 44 : 38,
              iconSize: kMobile ? 25 : 19,
              tooltip: 'Sidebar',
              onTap: onMenu)),
    ]);
  }

  Widget _welcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(R.card),
                        border: Border.all(color: AppColors.border)),
                    child: AppIcon('cpu', size: 24, color: AppColors.fg3),
                  ),
                ),
                const SizedBox(height: 18),
                Text('No instance connected',
                    textAlign: TextAlign.center,
                    style: sans(15.5, color: AppColors.fg1)),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                      style: sans(12.5, height: 1.5, color: AppColors.fg3),
                      children: [
                        const TextSpan(text: 'Run '),
                        TextSpan(
                            text: 'snippet serve',
                            style: mono(12, color: AppColors.fg2)),
                        const TextSpan(
                            text:
                                ' on a machine, then paste the connection string it prints.'),
                      ]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                Center(
                    child: PillBtn('Add machine',
                        icon: 'plus', onTap: _addInstanceFlow)),
              ]),
        ),
      ),
    );
  }
}

class _GoalPopover extends StatefulWidget {
  final void Function(String text) onSet;
  const _GoalPopover({required this.onSet});

  @override
  State<_GoalPopover> createState() => _GoalPopoverState();
}

class _GoalPopoverState extends State<_GoalPopover> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    widget.onSet(t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Set goal',
            style: sans(12.5, weight: W.label, color: AppColors.fg1)),
        const SizedBox(height: 8),
        AppField(
          controller: _ctl,
          hint: 'What should the agent work toward?',
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Spacer(),
          Btn('Cancel',
              variant: BtnVariant.ghost,
              small: true,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 6),
          Btn('Set goal', small: true, onTap: _submit),
        ]),
      ],
    );
  }
}

/// Filter control for the CHATS list: a free-text query over titles and folders,
/// plus the status shortcuts with live counts.
///
/// Shared by the desktop popover and the mobile sheet so the two can never
/// drift apart. Follows the shell's language: 8px radii, a 28px row, one
/// surface step between the panel and its inset field, and weight (not colour)
/// marking the active row except for a single accent tick.
class _ChatFilterPanel extends StatefulWidget {
  const _ChatFilterPanel({
    required this.query,
    required this.status,
    required this.counts,
    required this.onQuery,
    required this.onStatus,
  });

  final String query;
  final String status;
  final Map<String, int> counts;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onStatus;

  @override
  State<_ChatFilterPanel> createState() => _ChatFilterPanelState();
}

class _ChatFilterPanelState extends State<_ChatFilterPanel> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.query);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inset field: one step darker than the panel it sits on, so the
          // input reads as carved into the popover rather than drawn on it.
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(children: [
              AppIcon('search', size: 14, color: AppColors.fg4),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctl,
                  autofocus: true,
                  onChanged: (v) {
                    widget.onQuery(v);
                    setState(() {}); // reveal/hide the clear affordance
                  },
                  cursorColor: AppColors.fg1,
                  style: sans(13, color: AppColors.fg1),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Filter chats',
                    hintStyle: sans(13, color: AppColors.fg4),
                  ),
                ),
              ),
              if (_ctl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _ctl.clear();
                    widget.onQuery('');
                    setState(() {});
                  },
                  child: AppIcon('x', size: 12, color: AppColors.fg4),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          for (final (val, label) in const [
            ('all', 'All'),
            ('input', 'Needs input'),
            ('running', 'Running'),
            ('done', 'Done'),
          ])
            _statusRow(val, label),
        ],
      ),
    );
  }

  Widget _statusRow(String val, String label) {
    final selected = widget.status == val;
    return Material(
      color: selected ? AppColors.surface1 : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: () => widget.onStatus(val),
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: sans(13,
                      weight: selected ? W.label : W.body,
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
            Text('${widget.counts[val] ?? 0}',
                style: sans(12, color: AppColors.fg4)),
            if (selected) ...[
              const SizedBox(width: 6),
              AppIcon('check', size: 14, color: AppColors.accent),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Keeps a swiped-away tab mounted so its WebSocket attach and scroll position
/// survive switching between tabs.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  final bool keep;
  const _KeepAlive({super.key, required this.child, this.keep = true});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;
  @override
  void didUpdateWidget(covariant _KeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    super.build(context);
    return widget.child;
  }
}

/// Quiet empty state used inside the sectioned sidebar.
class _SidebarEmpty extends StatelessWidget {
  const _SidebarEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Text(message,
            textAlign: TextAlign.center,
            style: sans(12.5, color: AppColors.fg4, height: 1.45)),
      );
}

class _Sidebar extends StatefulWidget {
  final List<Instance> instances;
  final Instance? active;
  final DaemonClient? client;
  final String? selectedSessionId;
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final String? sessionsError;
  final VoidCallback onRefreshSessions;
  final VoidCallback onNewSession;
  final void Function(Instance) onSelectInstance;
  final VoidCallback onOpenMissionControl;
  final void Function(String id, String title, String? profile) onOpenSession;
  final VoidCallback onAddInstance;
  final void Function(Instance, String) onRenameInstance;
  final void Function(Instance) onRemoveInstance;
  final void Function(String id) onSessionDeleted;
  final Map<String, bool> health;
  final VoidCallback onRefreshHealth;
  final bool topInset;
  final void Function(String action)? onSessionAction;
  const _Sidebar({
    required this.instances,
    required this.active,
    required this.client,
    required this.selectedSessionId,
    required this.sessions,
    required this.sessionsLoading,
    this.sessionsError,
    required this.onRefreshSessions,
    required this.onNewSession,
    required this.onSelectInstance,
    required this.onOpenMissionControl,
    required this.onOpenSession,
    required this.onAddInstance,
    required this.onRenameInstance,
    required this.onRemoveInstance,
    required this.onSessionDeleted,
    required this.health,
    required this.onRefreshHealth,
    required this.topInset,
    this.onSessionAction,
  });
  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  // The session list now lives in the shell (passed via widget.sessions); the
  // sidebar is presentational, so opening the drawer doesn't refetch.
  String _filter = 'all'; // all | input | running | done
  /// Free-text filter over a session's title and folder, set from the CHATS
  /// header popover. Empty means "no text filter".
  String _filterQuery = '';
  final _filterKey = GlobalKey(); // anchors the desktop filter popover
  final _machineKey = GlobalKey(); // anchors the desktop machine popover
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Folder groups the user has collapsed. Keyed by folder path; a group is
  /// expanded by default, so a fresh session list is fully visible.
  final Set<String> _collapsed = {};

  /// Collapse key for the whole CHATS section — distinct from any folder path.
  static const String _chatsKey = '__chats__';
  String? _renamingId;
  String? _hoveredId;
  final TextEditingController _renameCtl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  @override
  void dispose() {
    _renameCtl.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _openMc() {
    if (widget.client == null) return;
    widget.onOpenMissionControl();
  }

  List<SessionInfo>? get _sessions => widget.sessions;
  bool get _loading => widget.sessionsLoading;

  /// Status counts for the filter panel, computed from the *unfiltered* list so
  /// the numbers stay meaningful while a query narrows the visible rows.
  Map<String, int> _filterCounts() {
    final all = widget.sessions ?? const <SessionInfo>[];
    int n(bool Function(SessionInfo) f) => all.where(f).length;
    return {
      'all': all.length,
      'input': n((s) => s.status == 'waiting_for_input'),
      'running': n((s) => s.status == 'running'),
      'done':
          n((s) => s.status != 'waiting_for_input' && s.status != 'running'),
    };
  }

  /// Desktop filter control: an anchored popover beneath the CHATS filter icon,
  /// so the list stays visible while the query is typed.
  Future<void> _openFilterPopover() async {
    final box = _filterKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    const width = 264.0;
    // Right-align to the icon, then keep the panel fully on screen.
    final maxLeft = (screen.width - width - 8).clamp(8.0, screen.width);
    final left = (origin.dx + box.size.width - width).clamp(8.0, maxLeft);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true, // click-away and Esc dismiss
      barrierLabel: 'filter',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => Stack(children: [
        Positioned(
          left: left,
          top: origin.dy + box.size.height + 6,
          width: width,
          child: Material(
            // Popover surface; separation comes from the surface step and the
            // shadow, not a drawn border.
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.md),
            elevation: 12,
            shadowColor: Colors.black87,
            child: _ChatFilterPanel(
              query: _filterQuery,
              status: _filter,
              counts: _filterCounts(),
              onQuery: (q) => setState(() => _filterQuery = q),
              onStatus: (s) => setState(() => _filter = s),
            ),
          ),
        ),
      ]),
    );
  }

  void _showFilterSheet() {
    showAppSheet(
      context,
      title: 'Filter conversations',
      child: _ChatFilterPanel(
        query: _filterQuery,
        status: _filter,
        counts: _filterCounts(),
        onQuery: (q) => setState(() => _filterQuery = q),
        onStatus: (s) => setState(() => _filter = s),
      ),
    );
  }

  void _openSearch() {
    showCommandPalette(
      context,
      sessions: _sessions ?? const [],
      onOpenChat: (s) => widget.onOpenSession(s.id, s.title, s.profile),
      commands: [
        PaletteCommand('layers', 'Mission Control', '', _openMc),
        PaletteCommand('edit', 'New chat', '', widget.onNewSession),
        PaletteCommand('folder', 'Open folder', '', widget.onNewSession),
        PaletteCommand('settings', 'Settings', '', _openSettings),
      ],
    );
  }

  void _openSettings() {
    final c = widget.client;
    if (c == null) return;
    presentScreen(context,
        maxWidth: 640,
        maxHeight: 620,
        builder: (_, close) => _SettingsPanel(
              client: c,
              instances: widget.instances,
              active: widget.active,
              onRemove: widget.onRemoveInstance,
              onClose: close,
            ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final hasClient = widget.client != null;
    return Container(
      color: AppColors.bg, // shell surface — darker than the chat canvas
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.topInset && kMacOS) SizedBox(height: kMacTitlebar + 6),
        if (kMobile) ...[
          // Mobile: full-height conversations list with the machine row at the bottom.
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A phone home needs one reading order: destination, machine
                  // context, search, then the chronological list. The earlier
                  // machine card + header + bottom toolbar gave every control
                  // equal priority and made the first action unclear.
                  _mobileHomeHeader(hasClient),
                  if (hasClient && !_selecting) _stickyMissionControl(),
                  Expanded(
                    child: !hasClient
                        ? Center(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text('Add a machine to begin.',
                                    textAlign: TextAlign.center,
                                    style: sans(12.5, color: AppColors.fg4))))
                        : _sessionList(),
                  ),
                ]),
          ),
          // The Chats header owns search, machine switching, creation, and
          // settings; another bottom toolbar would split those decisions across
          // both ends of the phone.
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
              child: Row(children: [
                Text('${_selected.length} selected',
                    style: sans(11.5, color: AppColors.fg3)),
                const Spacer(),
                _selectAllToggle(),
                IconBtn('x',
                    size: 28,
                    iconSize: 15,
                    tooltip: 'Cancel',
                    onTap: _exitSelect),
                IconBtn('trash',
                    size: 28,
                    iconSize: 14,
                    tooltip: 'Delete selected',
                    onTap: _selected.isEmpty ? null : _confirmDeleteSelected),
              ]),
            ),
          // Sectioned, collapsible sidebar — the reference's left column.
          Expanded(child: _sectionedSidebar()),
        ],
      ]),
    );
  }

  /// Grok-style "Browse" card at the top of the mobile drawer.
  Widget _browseCard() {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: widget.client != null ? widget.onNewSession : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: AppIcon('folder', size: 16, color: AppColors.fg2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Browse',
                        style: sans(14, weight: W.label, color: AppColors.fg1)),
                    const SizedBox(height: 1),
                    Text('files · new chat',
                        style: sans(11.5, color: AppColors.fg4)),
                  ]),
            ),
            AppIcon('chevron-right', size: 16, color: AppColors.fg4),
          ]),
        ),
      ),
    );
  }

  Widget _stickyMissionControl() {
    final mc = (_sessions ?? const <SessionInfo>[])
        .where((s) => isDedicatedMcSession(s.id))
        .toList();
    if (mc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 8),
      child: _missionControlPin(mc.first),
    );
  }

  /// The one phone-home hierarchy: destination, connection context, discovery,
  /// then the chat list. Keeping the actions together makes the next step
  /// obvious instead of splitting navigation across a top card and bottom bar.
  Widget _mobileHomeHeader(bool hasClient) {
    final machine = widget.active;
    final online = machine == null ? null : widget.health[machine.url];
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 12, M.gutter, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_selecting)
          Row(children: [
            Text('${_selected.length} selected',
                style: sans(M.sectionTitle,
                    weight: W.label, color: AppColors.fg1)),
            const Spacer(),
            _selectAllToggle(),
            IconBtn('x',
                size: M.minTarget,
                iconSize: 18,
                tooltip: 'Cancel',
                onTap: _exitSelect),
            IconBtn('trash',
                size: M.minTarget,
                iconSize: 17,
                tooltip: 'Delete selected',
                onTap: _selected.isEmpty ? null : _confirmDeleteSelected),
          ])
        else ...[
          Row(children: [
            Text('Chats',
                style:
                    sans(M.pageTitle, weight: W.label, color: AppColors.fg1)),
            const Spacer(),
            IconBtn('plus',
                size: M.minTarget,
                iconSize: 21,
                tooltip: 'New chat',
                onTap: hasClient ? widget.onNewSession : null),
            IconBtn('settings',
                size: M.minTarget,
                iconSize: 19,
                tooltip: 'Settings',
                onTap: hasClient ? _openSettings : null),
          ]),
          const SizedBox(height: 6),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(R.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: widget.instances.isEmpty
                  ? widget.onAddInstance
                  : _openMachines,
              child: SizedBox(
                height: 36,
                child: Row(children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: online == true ? AppColors.ok : AppColors.fg4,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      machine == null ? 'Add machine' : machine.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(M.rowTitle, color: AppColors.fg3),
                    ),
                  ),
                  Text(machine == null ? '' : hostOf(machine.url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(M.monoMeta, color: AppColors.fg4)),
                  const SizedBox(width: 6),
                  AppIcon('chevron-down', size: 14, color: AppColors.fg4),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.md),
              onTap: hasClient ? _openSearch : null,
              child: Container(
                height: M.minTarget,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  AppIcon('search', size: 18, color: AppColors.fg4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Search chats',
                        style: sans(13.5, color: AppColors.fg4)),
                  ),
                  IconBtn('sliders',
                      size: 36,
                      iconSize: 17,
                      tooltip: 'Filter chats',
                      onTap: _showFilterSheet),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  // Phone metrics come from the shared M table so the two densities cannot
  // drift; desktop values stay local because they are already tokenised.
  double get _navText => kMobile ? M.rowTitle : 13;
  double get _navIcon => kMobile ? 18 : 16;
  double get _navPadV => kMobile ? 12 : 8;
  double get _rowTitle => kMobile ? M.rowTitle : 12.5;
  double get _rowTime => kMobile ? M.meta : 10;

  Widget _navRow(String icon, String label,
      {String? sub, VoidCallback? onTap, bool active = false}) {
    // Desktop: flat rounded rows matching the thread list (no sub line).
    if (!kMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 1),
        child: Material(
          color: active ? AppColors.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? 0.45 : 1,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  AppIcon(icon, size: 15, color: AppColors.fg3),
                  const SizedBox(width: 10),
                  Text(label, style: sans(12.5, color: AppColors.fg1)),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: active ? AppColors.accentBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, _navPadV, 14, _navPadV),
            child: Row(children: [
              AppIcon(icon, size: _navIcon, color: AppColors.fg2),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: sans(_navText, color: AppColors.fg1)),
                      if (sub != null)
                        Text(sub, style: sans(12, color: AppColors.fg4)),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static bool _statusMatch(String filter, SessionInfo s) => switch (filter) {
        'input' => s.status == 'waiting_for_input',
        'running' => s.status == 'running',
        'done' => s.status != 'waiting_for_input' && s.status != 'running',
        _ => true,
      };

  /// Free-text match against a session's title and folder. An empty query
  /// matches everything, so the text filter is inert until the user types.
  bool _matchesQuery(SessionInfo s) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.title.toLowerCase().contains(q) ||
        s.folder.toLowerCase().contains(q);
  }

  Widget _sessionList() {
    if (_loading && _sessions == null) {
      return Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.fg3)));
    }
    final all = _sessions ?? const <SessionInfo>[];
    if (all.isEmpty) {
      // Offline ≠ empty: a failed fetch gets an explicit error + retry.
      if (widget.sessionsError != null) {
        return ListView(
            padding: EdgeInsets.fromLTRB(
                kMobile ? M.gutter : 8, 2, kMobile ? M.gutter : 8, 32),
            children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('wifi-off', size: 20, color: AppColors.fg4),
                    const SizedBox(height: 10),
                    Text(widget.sessionsError!,
                        textAlign: TextAlign.center,
                        style: sans(12.5, color: AppColors.fg3)),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: widget.onRefreshSessions,
                        child: Text('Retry',
                            style: sans(12.5, color: AppColors.accent))),
                  ])),
            ]);
      }
      return ListView(
          padding: EdgeInsets.fromLTRB(
              kMobile ? M.gutter : 8, 2, kMobile ? M.gutter : 8, 32),
          children: [
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No chats yet.',
                    textAlign: TextAlign.center,
                    style: sans(12.5, color: AppColors.fg4))),
          ]);
    }
    final mc = all.where((s) => isDedicatedMcSession(s.id)).toList();
    final list = all
        .where((s) =>
            !isDedicatedMcSession(s.id) &&
            _statusMatch(_filter, s) &&
            _matchesQuery(s))
        .toList();
    // Phone chats are one flat, chronological surface. Folder nesting is a
    // desktop density aid; on a touch screen it obscures the one thing people
    // came here to do: open the recent conversation.
    if (kMobile) {
      list.sort((a, b) => b.lastActive.compareTo(a.lastActive));
      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: () async => widget.onRefreshSessions(),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 28),
          itemCount: list.length,
          itemBuilder: (_, i) => _sessionCard(list[i]),
        ),
      );
    }
    final children = <Widget>[];
    if (mc.isNotEmpty) {
      children.add(_missionControlPin(mc.first));
    }
    final newest = <String, int>{};
    for (final s in list) {
      final t = newest[s.folder];
      if (t == null || s.lastActive > t) newest[s.folder] = s.lastActive;
    }
    list.sort((a, b) {
      final fa = newest[a.folder] ?? 0;
      final fb = newest[b.folder] ?? 0;
      if (fa != fb) return fb.compareTo(fa);
      final byFolder = a.folder.compareTo(b.folder);
      if (byFolder != 0) return byFolder;
      return b.lastActive.compareTo(a.lastActive);
    });
    final groups = <String, List<SessionInfo>>{};
    final order = <String>[];
    for (final s in list) {
      final bucket = groups.putIfAbsent(s.folder, () {
        order.add(s.folder);
        return <SessionInfo>[];
      });
      bucket.add(s);
    }
    var firstFolder = true;
    for (final key in order) {
      final sessions = groups[key]!;
      children.add(_folderHeader(key,
          first: firstFolder && mc.isEmpty, count: sessions.length));
      firstFolder = false;
      // A collapsed group keeps its header (with its count) but hides its rows.
      if (_collapsed.contains(key)) continue;
      for (var i = 0; i < sessions.length; i++) {
        if (kMobile) {
          children.add(Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _sessionCard(sessions[i])));
        } else {
          children.add(
              _desktopTreeRow(sessions[i], last: i == sessions.length - 1));
        }
      }
    }
    if (list.isEmpty && (mc.isEmpty || _filter != 'all')) {
      children.add(Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Nothing here.',
              textAlign: TextAlign.center,
              style: sans(12.5, color: AppColors.fg4))));
    }
    final listView = ListView(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 14, 2, kMobile ? M.gutter : 14, 32),
        children: children);
    // Phones: the natural refresh gesture. Desktop keeps the header button.
    if (!kMobile) return listView;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface2,
      onRefresh: () async => widget.onRefreshSessions(),
      child: listView,
    );
  }

  /// Desktop sidebar as stacked, collapsible sections — the reference's left
  /// column: an UPPERCASE section header with an action cluster, then nested
  /// collapsible folder groups, then compact rows.
  ///
  /// Separate from `_sessionList()` because mobile keeps its card list; only the
  /// wide layout uses this density.
  Widget _sectionedSidebar() {
    final hasClient = widget.client != null;
    final all = _sessions ?? const <SessionInfo>[];
    final list = all
        .where((s) =>
            !isDedicatedMcSession(s.id) &&
            _statusMatch(_filter, s) &&
            _matchesQuery(s))
        .toList();

    // Newest folder first, then newest session within it.
    final newest = <String, int>{};
    for (final s in list) {
      final t = newest[s.folder];
      if (t == null || s.lastActive > t) newest[s.folder] = s.lastActive;
    }
    list.sort((a, b) {
      final fa = newest[a.folder] ?? 0;
      final fb = newest[b.folder] ?? 0;
      if (fa != fb) return fb.compareTo(fa);
      final byFolder = a.folder.compareTo(b.folder);
      if (byFolder != 0) return byFolder;
      return b.lastActive.compareTo(a.lastActive);
    });

    final groups = <String, List<SessionInfo>>{};
    final order = <String>[];
    for (final s in list) {
      groups.putIfAbsent(s.folder, () {
        order.add(s.folder);
        return <SessionInfo>[];
      }).add(s);
    }

    final chatsOpen = !_collapsed.contains(_chatsKey);
    return ListView(
      // Top inset keeps the first section header clear of the navigation band,
      // matching the reference's 8px section padding.
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      children: [
        ShellSectionHeader(
          label: 'Chats',
          expanded: chatsOpen,
          onToggle: () => setState(() => _toggleCollapsed(_chatsKey)),
          actions: [
            ShellSectionAction(
              key: _filterKey,
              icon: 'sliders',
              tooltip: 'Filter chats',
              // Accented while a text filter is active, so a filtered list is
              // never mistaken for an empty one.
              active: _filterQuery.trim().isNotEmpty,
              onTap: hasClient ? _openFilterPopover : null,
            ),
            ShellSectionAction(
              icon: 'plus',
              tooltip: 'New chat',
              onTap: hasClient ? widget.onNewSession : null,
            ),
          ],
        ),
        if (!chatsOpen)
          const SizedBox.shrink()
        else if (!hasClient)
          const _SidebarEmpty('Add a machine to begin.')
        else if (list.isEmpty)
          // Distinguish "no conversations" from "none match the filter": saying
          // "No chats yet" over a filtered list reads as data loss.
          _SidebarEmpty(_filterQuery.trim().isNotEmpty || _filter != 'all'
              ? 'No chats match the filter.'
              : 'No chats yet.')
        else
          // Flat list of conversations directly under CHATS (no folder nesting)
          for (final s in list) _sidebarSessionRow(s),
      ],
    );
  }

  void _toggleCollapsed(String key) {
    if (_collapsed.contains(key)) {
      _collapsed.remove(key);
    } else {
      _collapsed.add(key);
    }
  }

  /// One chat row. The folder is already conveyed by its group header, so the
  /// row stays a single line; the trailing dot carries run/needs-input state.
  Widget _sidebarSessionRow(SessionInfo s) {
    final selected = s.id == widget.selectedSessionId;
    final running = s.status == 'running';
    final waiting = s.status == 'waiting_for_input';
    return ShellNavRow(
      id: s.id,
      label: s.title.trim().isEmpty ? '(untitled)' : s.title,
      icon: 'chat-thread',
      tone: ShellTone.chat,
      selected: selected,
      onTap: () => widget.onOpenSession(s.id, s.title, s.profile),
      trailing: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: waiting
              ? AppColors.accent
              : running
                  ? AppColors.run
                  : Colors.transparent,
        ),
      ),
    );
  }

  Widget _filterChips(List<SessionInfo> all) {
    const items = [
      ('all', 'All'),
      ('input', 'Needs input'),
      ('running', 'Running'),
      ('done', 'Done')
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        child: Row(children: [
          for (final (val, label) in items) ...[
            _chip(val, label, all.where((s) => _statusMatch(val, s)).length),
            const SizedBox(width: 7),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String val, String label, int n) {
    final sel = _filter == val;
    return Material(
      color: sel ? AppColors.fg1 : AppColors.surface2,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        hoverColor: sel
            ? Colors.transparent
            : null, // no raise on the light selected chip
        onTap: () => setState(() => _filter = val),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text('$label $n',
              style: sans(12.5,
                  weight: W.label, color: sel ? AppColors.bg : AppColors.fg3)),
        ),
      ),
    );
  }

  Widget _folderHeader(String folder, {required bool first, int count = 0}) {
    final name =
        folder.isEmpty ? 'No folder' : lastPathSegment(folder, ifEmpty: folder);
    final collapsed = _collapsed.contains(folder);
    // Collapsing is a local view preference, not state worth persisting — a
    // fresh session list should show everything.
    void toggle() => setState(() {
          if (collapsed) {
            _collapsed.remove(folder);
          } else {
            _collapsed.add(folder);
          }
        });
    final chevron = collapsed ? 'chevron-right' : 'chevron-down';
    if (kMobile) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: toggle,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, first ? 6 : 16, 4, 8),
            child: Row(children: [
              AppIcon(chevron, size: 14, color: AppColors.fg4),
              const SizedBox(width: 4),
              AppIcon('folder', size: 13, color: AppColors.fg4),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, weight: W.label, color: AppColors.fg3)),
              ),
              // A collapsed group still tells you how much is inside it.
              if (collapsed && count > 0)
                Text('$count', style: sans(11, color: AppColors.fg4)),
            ]),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: toggle,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, first ? 10 : 16, 6, 4),
          child: Row(children: [
            AppIcon(chevron, size: 13, color: AppColors.fg4),
            const SizedBox(width: 3),
            AppIcon('folder', size: 13, color: AppColors.fg4),
            const SizedBox(width: 7),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: sans(11.5, weight: W.title, color: AppColors.fg3)),
            ),
            if (collapsed && count > 0)
              Text('$count', style: sans(10.5, color: AppColors.fg4)),
          ]),
        ),
      ),
    );
  }

  Widget _desktopTreeRow(SessionInfo s, {required bool last}) {
    return _sessionRow(s);
  }

  Widget _missionControlPin(SessionInfo s) {
    final selected = s.id == widget.selectedSessionId;
    final waiting = s.status == 'waiting_for_input';
    final running = s.status == 'running';
    void open() => widget.onOpenSession(s.id, 'Mission Control', s.profile);
    final status = running || waiting
        ? Container(
            width: kMobile ? 8 : 6,
            height: kMobile ? 8 : 6,
            decoration: BoxDecoration(
              color: waiting ? AppColors.accent : AppColors.run,
              shape: BoxShape.circle,
            ),
          )
        : null;
    if (kMobile) {
      return Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: open,
          child: Container(
            height: M.rowHeight,
            padding: EdgeInsets.symmetric(horizontal: M.rowPadH),
            child: Row(children: [
              AppIcon('layers',
                  size: 16, color: selected ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Mission Control',
                    style: sans(M.rowTitle,
                        weight: W.label,
                        color: selected ? AppColors.fg1 : AppColors.fg2)),
              ),
              if (status != null) status,
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 6),
      child: Material(
        color: selected ? AppColors.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: open,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              AppIcon('layers', size: 14, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mission Control',
                    style: sans(12.5,
                        weight: W.label,
                        color: selected ? AppColors.fg1 : AppColors.fg2)),
              ),
              if (status != null) status,
            ]),
          ),
        ),
      ),
    );
  }

  // Desktop: flat native thread row — no card chrome, rounded hover, a status
  // dot only when it means something (needs input / running).
  Widget _sessionRow(SessionInfo s) {
    final selected = s.id == widget.selectedSessionId;
    final waiting = s.status == 'waiting_for_input';
    final running = s.status == 'running';
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final hovered = !kMobile && _hoveredId == s.id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredId = s.id),
      onExit: (_) {
        if (_hoveredId == s.id) setState(() => _hoveredId = null);
      },
      child: Material(
        color: selected || checked ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: renaming
              ? null
              : () {
                  if (_selecting) {
                    _toggleSelected(s.id);
                  } else {
                    widget.onOpenSession(s.id, s.title, s.profile);
                  }
                },
          onLongPress: renaming
              ? null
              : () {
                  if (_selecting) {
                    _toggleSelected(s.id);
                  } else {
                    _enterSelect(seed: s.id);
                  }
                },
          onSecondaryTapDown: (renaming || !kMobile)
              ? null
              : (details) =>
                  _sessionActions(s, position: details.globalPosition),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              if (_selecting) ...[
                AppIcon(checked ? 'check' : 'plus',
                    size: 13,
                    color: checked ? AppColors.accent : AppColors.fg4),
                const SizedBox(width: 6),
              ] else if (waiting || running) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: waiting ? AppColors.accent : AppColors.run,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                  child: renaming
                      ? _inlineRenameField(s, compact: true)
                      : Text(s.title.isEmpty ? '(untitled)' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12.5,
                              color:
                                  selected ? AppColors.fg1 : AppColors.fg2))),
              if (!renaming) ...[
                if (hovered && !_selecting && !isDedicatedMcSession(s.id)) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Rename',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.xs),
                      onTap: () => _beginRename(s),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: AppIcon('edit', size: 12, color: AppColors.fg3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Delete',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.xs),
                      onTap: () => _confirmDeleteSessions([s]),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child:
                            AppIcon('trash', size: 12, color: AppColors.danger),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Text(relativeTime(s.lastActive),
                      style: mono(10,
                          color: waiting ? AppColors.accent : AppColors.fg4)),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sessionCard(SessionInfo s) {
    final running = s.status == 'running';
    final waiting = s.status == 'waiting_for_input';
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final selected = s.id == widget.selectedSessionId;
    return Material(
      color: selected || checked ? AppColors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: renaming
            ? null
            : () {
                if (_selecting) {
                  _toggleSelected(s.id);
                } else {
                  widget.onOpenSession(s.id, s.title, s.profile);
                }
              },
        // Long-press opens this chat's actions rather than jumping straight into
        // selection: the common intent is to rename or delete ONE chat, and bulk
        // selection stays reachable from that same sheet.
        onLongPress: renaming
            ? null
            : () {
                if (_selecting) {
                  _toggleSelected(s.id);
                } else {
                  _sessionActions(s);
                }
              },
        child: SizedBox(
          height: M.rowHeight,
          child: Padding(
            padding: EdgeInsets.only(left: M.rowPadH, right: 6),
            child: Row(children: [
              if (_selecting) ...[
                AppIcon(checked ? 'check' : 'plus',
                    size: 16,
                    color: checked ? AppColors.accent : AppColors.fg4),
                const SizedBox(width: 10),
              ] else if (running || waiting) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: running ? AppColors.run : AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: renaming
                    ? _inlineRenameField(s, compact: false)
                    : Text(
                        s.title.isEmpty ? '(untitled)' : s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(M.rowTitle,
                            color: selected ? AppColors.fg1 : AppColors.fg2),
                      ),
              ),
              // No per-row overflow button. At this row height it crowded the
              // title, and its glyph rendered as a dark blob rather than a
              // control. The same actions live on long-press.
              if (!renaming)
                Text(relativeTime(s.lastActive),
                    style: sans(M.meta, color: AppColors.fg4)),
            ]),
          ),
        ),
      ),
    );
  }

  // Long-press / right-click a session → rename or delete.
  Future<void> _sessionActions(SessionInfo s, {Offset? position}) async {
    if (isDedicatedMcSession(s.id)) return;
    if (!kMobile) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final point = position ?? overlay.size.center(Offset.zero);
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromCircle(center: point, radius: 0),
          Offset.zero & overlay.size,
        ),
        color: AppColors.surface1,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: appMenuShape,
        items: [
          appMenuItem(value: 'rename', icon: 'edit', label: 'Rename'),
          appMenuItem(
              value: 'delete', icon: 'trash', label: 'Delete', danger: true),
        ],
      );
      if (selected == 'rename') {
        _beginRename(s);
      } else if (selected == 'delete') {
        await _confirmDeleteSessions([s]);
      }
      return;
    }
    showAppSheet(context,
        title: s.title.isEmpty ? '(untitled)' : s.title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sessionActionTile('check-check', 'Select', onTap: () {
              Navigator.pop(context);
              _enterSelect(seed: s.id);
            }),
            _sessionActionTile('edit', 'Rename', onTap: () {
              Navigator.pop(context);
              _beginRename(s);
            }),
            _sessionActionTile('trash', 'Delete', danger: true, onTap: () {
              Navigator.pop(context);
              _confirmDeleteSessions([s]);
            }),
          ],
        ));
  }

  Widget _sessionActionTile(String icon, String label,
      {required VoidCallback onTap, bool danger = false}) {
    final color = danger ? AppColors.danger : AppColors.fg1;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
          child: Row(children: [
            AppIcon(icon, size: 16, color: color),
            const SizedBox(width: 12),
            Text(label, style: sans(13.5, color: color)),
          ]),
        ),
      ),
    );
  }

  void _enterSelect({String? seed}) {
    if (seed != null && isDedicatedMcSession(seed)) return;
    setState(() {
      _selecting = true;
      _renamingId = null;
      if (seed != null) _selected.add(seed);
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    if (isDedicatedMcSession(id)) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  /// Rows the current filter is showing — the exact set "Select all" acts on.
  ///
  /// Mirrors [_sessionList]'s predicate deliberately: selecting rows the user
  /// cannot see (a filtered-out chat) would let a bulk delete remove something
  /// that was never on screen.
  List<SessionInfo> get _visibleSessions => [
        for (final s in _sessions ?? const <SessionInfo>[])
          if (!isDedicatedMcSession(s.id) &&
              _statusMatch(_filter, s) &&
              _matchesQuery(s))
            s,
      ];

  bool get _allVisibleSelected {
    final ids = _visibleSessions.map((s) => s.id).toList();
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void _toggleSelectAllVisible() {
    final ids = _visibleSessions.map((s) => s.id).toList();
    if (ids.isEmpty) return;
    setState(() {
      if (ids.every(_selected.contains)) {
        for (final id in ids) {
          _selected.remove(id);
        }
      } else {
        _selected.addAll(ids);
      }
      // An emptied selection must not leave the bar up reading "0 selected".
      if (_selected.isEmpty) _selecting = false;
    });
  }

  /// "Select all" / "Unselect all" as a text toggle, not an icon: nothing in the
  /// icon set means "all" unambiguously, and the label also states which way the
  /// next tap goes.
  Widget _selectAllToggle() {
    final all = _allVisibleSelected;
    return InkWell(
      borderRadius: BorderRadius.circular(R.sm),
      onTap: _toggleSelectAllVisible,
      child: SizedBox(
        height: kMobile ? M.minTarget : 26,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(all ? 'Unselect all' : 'Select all',
                style: sans(kMobile ? M.rowTitle : 11.5,
                    weight: W.label, color: AppColors.fg3)),
          ),
        ),
      ),
    );
  }

  void _beginRename(SessionInfo s) {
    if (isDedicatedMcSession(s.id)) return;
    _renameCtl.text = s.title;
    _renameCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _renameCtl.text.length);
    setState(() {
      _selecting = false;
      _selected.clear();
      _renamingId = s.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocus.requestFocus();
    });
  }

  Widget _inlineRenameField(SessionInfo s, {required bool compact}) {
    return TextField(
      controller: _renameCtl,
      focusNode: _renameFocus,
      autofocus: true,
      maxLines: 1,
      style: sans(compact ? 12.5 : 16, color: AppColors.fg1),
      cursorColor: AppColors.fg1,
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: 'Session title',
      ),
      onSubmitted: (_) => _commitRename(s),
      onTapOutside: (_) => _commitRename(s),
    );
  }

  Future<void> _commitRename(SessionInfo s) async {
    if (_renamingId != s.id) return;
    final c = widget.client;
    final title = _renameCtl.text.trim();
    setState(() => _renamingId = null);
    if (c == null || title.isEmpty || title == s.title) return;
    try {
      await c.renameSession(s.id, title);
      widget.onRefreshSessions();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final ids = _selected.toList();
    final sessions = (widget.sessions ?? const <SessionInfo>[])
        .where((s) => ids.contains(s.id))
        .toList();
    if (sessions.isEmpty) return;
    await _confirmDeleteSessions(sessions);
  }

  Future<void> _confirmDeleteSessions(List<SessionInfo> sessions) async {
    final c = widget.client;
    if (c == null || sessions.isEmpty) return;
    final n = sessions.length;
    final first = sessions.first.title.isEmpty
        ? '(untitled session)'
        : sessions.first.title;
    final body = n == 1
        ? '$first\n\nPermanently removes the conversation. The folder and its files are untouched.'
        : 'Delete $n conversations? Folders and files are untouched.';
    final ok = await confirmAction(
      context,
      title: n == 1 ? 'Delete session?' : 'Delete $n sessions?',
      body: body,
      confirmLabel: n == 1 ? 'Delete' : 'Delete $n',
    );
    if (!ok) return;
    try {
      for (final s in sessions) {
        await c.deleteSession(s.id);
        widget.onSessionDeleted(s.id);
      }
      if (mounted) _exitSelect();
      widget.onRefreshSessions();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  // ---- machines ----

  /// The sidebar header IS the machine switcher: active machine label in
  /// display type with a live dot + chevron, host underneath, refresh trailing.
  /// Edge-to-edge tap target; hover raise comes from the global theme.
  Widget _machineHeader() {
    final a = widget.active;
    final ok = a == null ? null : widget.health[a.url];
    final hasClient = widget.client != null;
    // Mobile: Grok-style profile row with avatar circle + name + host + chevron.
    if (kMobile) {
      return Material(
        key: _machineKey,
        color: Colors.transparent,
        child: InkWell(
          onTap:
              widget.instances.isEmpty ? widget.onAddInstance : _openMachines,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              // Avatar circle — first letter of the machine name.
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                alignment: Alignment.center,
                child: a == null
                    ? AppIcon('plus', size: 18, color: AppColors.fg2)
                    : Text(
                        (a.label.isNotEmpty ? a.label[0] : '?').toUpperCase(),
                        style: sans(17, weight: W.label, color: AppColors.fg1),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: a == null
                    ? Text('Add machine', style: sans(15, color: AppColors.fg1))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(15,
                                  weight: W.label, color: AppColors.fg1)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                    color: ok == true
                                        ? AppColors.ok
                                        : AppColors.fg4,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(hostOf(a.url),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(11, color: AppColors.fg4)),
                            ),
                          ]),
                        ],
                      ),
              ),
              AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      );
    }
    // Desktop: original compact header.
    return Material(
      key: _machineKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.instances.isEmpty ? widget.onAddInstance : _openMachines,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: a == null
                  ? Row(children: [
                      AppIcon('plus', size: 18, color: AppColors.fg1),
                      const SizedBox(width: 9),
                      Text('Add machine', style: display(17)),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                              child: Text(a.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: display(17))),
                          const SizedBox(width: 8),
                          Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color:
                                      ok == true ? AppColors.ok : AppColors.fg4,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          AppIcon('chevron-down',
                              size: 16, color: AppColors.fg3),
                        ]),
                        const SizedBox(height: 2),
                        Text(hostOf(a.url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(11, color: AppColors.fg4)),
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            IconBtn('refresh',
                size: 30,
                iconSize: 15,
                tooltip: 'Refresh',
                onTap:
                    hasClient && !_loading ? widget.onRefreshSessions : null),
            IconBtn('settings',
                size: 30,
                iconSize: 15,
                tooltip: 'Settings',
                onTap: hasClient ? _openSettings : null),
          ]),
        ),
      ),
    );
  }

  /// Machine list: bottom sheet on phones, a popover anchored to the block on
  /// desktop. Same rows + "Add machine" footer either way.
  Future<void> _openMachines() async {
    widget.onRefreshHealth();
    final content = _MachineList(
      instances: widget.instances,
      active: widget.active,
      health: widget.health,
      onSelect: widget.onSelectInstance,
      onAdd: widget.onAddInstance,
      onManage: _machineActions,
    );
    if (kMobile) {
      await showAppSheet(context, title: 'Machines', child: content);
      return;
    }
    final box = _machineKey.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true, // click-away and Esc dismiss
      barrierLabel: 'machines',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => Stack(children: [
        // Inset from the edge-to-edge header so it reads as a popover.
        Positioned(
          left: origin.dx + 10,
          top: origin.dy + box.size.height + 4,
          width: box.size.width - 20,
          child: Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            elevation: 12,
            shadowColor: Colors.black87,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border2),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(child: content),
              ),
            ),
          ),
        ),
      ]),
      transitionBuilder: (_, anim, __, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 5.0 * curved.value, sigmaY: 5.0 * curved.value),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  // Overflow / long-press on a machine row → rename or remove (existing flows).
  void _machineActions(Instance i) {
    showAppSheet(context,
        title: i.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sessionActionTile('edit', 'Rename', onTap: () {
              Navigator.pop(context);
              _renameMachine(i);
            }),
            _sessionActionTile('trash', 'Remove', danger: true, onTap: () {
              Navigator.pop(context);
              _confirmRemoveMachine(i);
            }),
          ],
        ));
  }

  Future<void> _renameMachine(Instance i) async {
    final name = await promptText(context,
        title: 'Rename machine',
        initial: i.label,
        hint: 'Machine name',
        saveLabel: 'Rename');
    if (name == null || name.isEmpty) return;
    widget.onRenameInstance(i, name);
  }

  Future<void> _confirmRemoveMachine(Instance i) async {
    final ok = await confirmAction(
      context,
      title: 'Remove machine?',
      body:
          '${i.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
      confirmLabel: 'Remove',
    );
    if (ok) widget.onRemoveInstance(i);
  }
}

/// Rows for the machine popover/sheet: live dot (re-pinged on open), label,
/// host, trailing overflow. Pops itself before invoking any callback.
class _MachineList extends StatefulWidget {
  final List<Instance> instances;
  final Instance? active;
  final Map<String, bool> health;
  final void Function(Instance) onSelect;
  final VoidCallback onAdd;
  final void Function(Instance) onManage;
  const _MachineList({
    required this.instances,
    required this.active,
    required this.health,
    required this.onSelect,
    required this.onAdd,
    required this.onManage,
  });
  @override
  State<_MachineList> createState() => _MachineListState();
}

class _MachineListState extends State<_MachineList> {
  late final Map<String, bool> _h = {...widget.health};

  @override
  void initState() {
    super.initState();
    for (final i in widget.instances) {
      DaemonClient(i.url, i.token).health().then((ok) {
        if (mounted && _h[i.url] != ok) setState(() => _h[i.url] = ok);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.instances.map(_row),
          Divider(height: 13, thickness: 1, color: AppColors.border),
          _addRow(),
        ]);
  }

  Widget _row(Instance i) {
    final selected = i.url == widget.active?.url;
    final ok = _h[i.url];
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        widget.onSelect(i);
      },
      onLongPress: () {
        Navigator.pop(context);
        widget.onManage(i);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, kMobile ? 9 : 6, 4, kMobile ? 9 : 6),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: ok == true ? AppColors.ok : AppColors.fg4,
                  shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14 : 12.5, color: AppColors.fg1)),
              const SizedBox(height: 1),
              Text(hostOf(i.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(kMobile ? 11 : 10, color: AppColors.fg4)),
            ]),
          ),
          if (selected) AppIcon('check', size: 14, color: AppColors.accent),
          IconBtn('more-vertical', size: 30, iconSize: 15, tooltip: 'Manage',
              onTap: () {
            Navigator.pop(context);
            widget.onManage(i);
          }),
        ]),
      ),
    );
  }

  Widget _addRow() {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        widget.onAdd();
      },
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(14, kMobile ? 11 : 8, 14, kMobile ? 11 : 8),
        child: Row(children: [
          AppIcon('plus', size: 15, color: AppColors.accent),
          const SizedBox(width: 10),
          Text('Add machine',
              style: sans(kMobile ? 14 : 12.5,
                  weight: W.label, color: AppColors.accent)),
        ]),
      ),
    );
  }
}

/// Settings dialog: Zed-style sidebar + content pane. Models / vault /
/// scheduled swap in-place so they never stack a second dialog.
class _SettingsPanel extends StatefulWidget {
  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final VoidCallback onClose;
  const _SettingsPanel({
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    required this.onClose,
  });
  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

enum _SettingsPage { general, models, usage, vault, scheduled }

class _SettingsPanelState extends State<_SettingsPanel> {
  late final List<Instance> _instances = [...widget.instances];
  bool _notif = false;
  bool _notifBusy = false;
  _SettingsPage _page = _SettingsPage.general;

  static const _nav = [
    (_SettingsPage.general, 'settings', 'General'),
    (_SettingsPage.models, 'cpu', 'Models'),
    (_SettingsPage.usage, 'activity', 'Usage'),
    (_SettingsPage.vault, 'key', 'Vault'),
    (_SettingsPage.scheduled, 'scheduled', 'Scheduled'),
  ];

  @override
  void initState() {
    super.initState();
    notificationsEnabled().then((v) {
      if (mounted) setState(() => _notif = v);
    });
  }

  Future<void> _toggleNotif(bool v) async {
    setState(() => _notifBusy = true);
    final err = await setNotificationsEnabled(v);
    if (!mounted) return;
    setState(() {
      _notifBusy = false;
      _notif = err == null ? v : _notif;
    });
    if (err != null) toast(context, err);
  }

  Future<void> _confirmRemove(Instance inst) async {
    final ok = await confirmAction(
      context,
      title: 'Remove instance?',
      body:
          '${inst.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    widget.onRemove(inst);
    setState(() => _instances.removeWhere((e) => e.url == inst.url));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Scaffold(
      backgroundColor: AppColors.surface1,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Settings',
                        style:
                            sans(14.5, weight: W.label, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Text('Configure this workspace and its models.',
                        style: sans(11.5, color: AppColors.fg3)),
                  ],
                ),
              ),
              IconBtn('x',
                  size: 26,
                  iconSize: 13,
                  tooltip: 'Close',
                  onTap: widget.onClose),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: Column(children: [
              SizedBox(height: 38, child: _navChips()),
              Divider(height: 1, color: AppColors.border),
              Expanded(child: _pageBody()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _navChips() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      children: [
        for (final (page, icon, label) in _nav)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: _page == page ? AppColors.accentBg : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
              child: InkWell(
                onTap: () => setState(() => _page = page),
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Row(children: [
                    AppIcon(icon,
                        size: 13,
                        color:
                            _page == page ? AppColors.accent : AppColors.fg3),
                    const SizedBox(width: 5),
                    Text(label,
                        style: sans(11.5,
                            weight: _page == page
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: _page == page
                                ? AppColors.accent
                                : AppColors.fg2)),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pageBody() {
    return switch (_page) {
      _SettingsPage.general => _generalPage(),
      _SettingsPage.models =>
        ModelsScreen(client: widget.client, embedded: true),
      _SettingsPage.usage => UsageScreen(client: widget.client, embedded: true),
      _SettingsPage.vault => VaultScreen(client: widget.client, embedded: true),
      _SettingsPage.scheduled =>
        RecurringScreen(client: widget.client, listOnly: true, embedded: true),
    };
  }

  Widget _generalPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        Text('General', style: sans(14, weight: W.label, color: AppColors.fg1)),
        const SizedBox(height: 3),
        Text('Manage the machine this app connects to and its alerts.',
            style: sans(11.5, color: AppColors.fg3)),
        const SizedBox(height: 14),
        Text('MACHINES',
            style:
                sans(10, weight: W.label, color: AppColors.fg4, spacing: 0.5)),
        const SizedBox(height: 6),
        if (_instances.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No saved connections.',
                style: sans(12, color: AppColors.fg3)),
          )
        else
          Column(
            children: [
              for (var i = 0; i < _instances.length; i++) ...[
                _instanceRow(_instances[i]),
                if (i < _instances.length - 1)
                  Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        if (kCanNotify) ...[
          const SizedBox(height: 16),
          Text('NOTIFICATIONS',
              style: sans(10,
                  weight: W.label, color: AppColors.fg4, spacing: 0.5)),
          const SizedBox(height: 6),
          _notifTile(),
        ],
      ],
    );
  }

  Widget _instanceRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(children: [
          AppIcon('cpu',
              size: 14, color: isActive ? AppColors.accent : AppColors.fg3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, weight: W.label, color: AppColors.fg1)),
                const SizedBox(height: 1),
                Text(hostOf(i.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(10.5, color: AppColors.fg4)),
              ],
            ),
          ),
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('active', style: sans(10, color: AppColors.accent)),
            ),
          IconBtn('trash',
              size: 26,
              iconSize: 13,
              tooltip: 'Remove',
              onTap: () => _confirmRemove(i)),
        ]),
      ),
    );
  }

  Widget _notifTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        AppIcon('zap', size: 14, color: AppColors.fg3),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Alerts',
                style: sans(12.5, weight: W.label, color: AppColors.fg1)),
            const SizedBox(height: 1),
            Text('Notify when a session needs input',
                style: sans(11, color: AppColors.fg4)),
          ]),
        ),
        _notifBusy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg3))
            : Transform.scale(
                scale: 0.72,
                child: Switch(
                  value: _notif,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeThumbColor: AppColors.accentFg,
                  activeTrackColor: AppColors.accent,
                  onChanged: _toggleNotif,
                ),
              ),
      ]),
    );
  }
}

/// Small green pulsing dot indicating a running session.
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl.drive(Tween(begin: 0.4, end: 1.0)),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF34D399), // emerald-400
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
