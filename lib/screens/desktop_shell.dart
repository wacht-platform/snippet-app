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
import '../store.dart';
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

/// One open tab in the shell — a live chat session, an opened file, or a single
/// git change, on a given instance.
class _ShellTab {
  final DaemonClient client;
  final String instanceUrl;
  final String? sessionId;
  final String? filePath;
  String title;
  String? profile;
  SharedInbound? inboundShare;

  /// Set only for a diff tab: the changed file plus the view it should show.
  /// A staged-only file reads the index diff; an untracked one shows as an add.
  final String? diffPath;
  final bool diffStaged;
  final bool diffUntracked;

  _ShellTab.session({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.title,
    this.profile,
    this.inboundShare,
  })  : filePath = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false;
  _ShellTab.file({
    required this.client,
    required this.instanceUrl,
    required this.filePath,
    required this.title,
  })  : sessionId = null,
        profile = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false;
  _ShellTab.diff({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.diffPath,
    required this.title,
    required this.diffStaged,
    required this.diffUntracked,
  })  : filePath = null,
        profile = null;

  bool get isFile => filePath != null;
  bool get isDiff => diffPath != null;
  bool get isMissionControl =>
      !isFile &&
      !isDiff &&
      isMissionControlTab(sessionId: sessionId, title: title);
  String get key => isDiff
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
  terminal('Terminal', 'terminal'),
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
  _ShellTab? get _activeTab =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
          ? _tabs[_activeIndex]
          : null;
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

  /// The user collapsed the terminal pane. Kept separate from the session's
  /// `_termOpen` so minimizing never destroys a shell — only the sidebar's
  /// terminal panel closes one.
  bool _termMinimized = false;

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

  /// Whether the pointer is over the 6px resize zone, so the rule only shows on
  /// hover (the reference draws no divider at rest).
  bool _paneHandleHover = false;

  /// Which contextual sidebar the rail is showing. Purely a shell concern: the
  /// conversation you're reading stays put while this changes.
  ShellSection _section = ShellSection.sessions;

  /// Detail shown in the right pane. Null = pane hidden, so the transcript gets
  /// the full width until something asks for detail — a pane that is always
  /// present would cost space even when nothing needs inspecting.
  CoordinationAgent? _rightAgent;

  /// A tab dragged out of the strip into the secondary pane. Null = a single
  /// pane, which is the default.
  ///
  /// There is deliberately no split *toggle*: splitting is a consequence of
  /// moving something there, not a mode you switch into. Dragging a tab out
  /// creates the second pane; closing the pane returns to one.
  _ShellTab? _splitTab;

  /// Session readouts that render in the secondary pane instead of a drawer.
  ///
  /// Lanes, Checkpoints and Usage are things you glance at WHILE reading the
  /// transcript, so a modal was the wrong shape for them — it covered the very
  /// context you were checking against.
  _RightPanel _rightPanel = _RightPanel.none;

  /// Is the secondary pane showing anything at all?
  bool get _rightPaneOpen {
    // The terminal pane can be MINIMIZED, which hides it without touching the
    // pty — the shell survives so reopening is instant and focus is preserved.
    // Only the sidebar's terminal panel destroys a shell.
    if (_rightPanel == _RightPanel.terminal) {
      final key = _activeTab?.key;
      final host = key == null ? null : _termHosts[key];
      if (host == null || host.terms.isEmpty) return false;
      if (_termMinimized) return false;
    }
    return _rightAgent != null ||
        _splitTab != null ||
        _rightPanel != _RightPanel.none;
  }

  /// Show a session panel in the pane, or close it if it is already showing.
  void _toggleRightPanel(_RightPanel p) {
    setState(() {
      _rightAgent = null;
      _splitTab = null;
      _rightPanel = _rightPanel == p ? _RightPanel.none : p;
    });
  }

  /// Move a tab into the secondary pane (called when it is dropped there).
  void _splitWith(_ShellTab tab) {
    if (tab.key == _activeTab?.key && _tabs.length == 1) return;
    setState(() {
      _rightAgent = null;
      _splitTab = tab;
    });
  }

  void _closeSplitPane() {
    setState(() {
      _splitTab = null;
      _rightAgent = null;
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
    final manual = (s?.approvalMode ?? 'auto') == 'manual';
    final goalRunning = s?.goal?.ongoing ?? false;
    final lanes = s?.lanes.where((l) => l.running).length ?? 0;

    return [
      _railTool('shield',
          tooltip: manual ? 'Approval: ask' : 'Approval: auto',
          active: manual,
          onTap: tab == null
              ? null
              : () => _dispatchSessionAction(
                  manual ? 'approval_auto' : 'approval_ask')),
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

    // A terminal created from the SIDEBAR must reveal the pane: creating is the
    // sidebar's job, showing the result is the shell's. Only auto-open on the
    // 0 -> n transition so a deliberate minimize is not undone by the next
    // publish (publishes also fire on alive/live transitions).
    if (prevTerms.isEmpty && hostTerms.isNotEmpty) {
      _termMinimized = false;
      _rightPanel = _RightPanel.terminal;
    }
    // An explicit open from the sidebar (false -> true) un-minimizes. Without
    // this, tapping a terminal in the sidebar would flip the session's open flag
    // but the shell would keep showing a minimized pane.
    if (open && !wasOpen && hostTerms.isNotEmpty) {
      _termMinimized = false;
      _rightPanel = _RightPanel.terminal;
    }
    // Every shell gone: the pane has nothing left to show.
    if (hostTerms.isEmpty && _rightPanel == _RightPanel.terminal) {
      _rightPanel = _RightPanel.none;
      _termMinimized = false;
    }
    if (changed && mounted) setState(() {});
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
      if (descriptor.isDiff) {
        restored.add(_ShellTab.diff(
          client: client,
          instanceUrl: inst.url,
          sessionId: descriptor.sessionId,
          diffPath: descriptor.diffPath!,
          title: descriptor.title,
          diffStaged: descriptor.diffStaged,
          diffUntracked: descriptor.diffUntracked,
        ));
      } else if (descriptor.isFile) {
        restored.add(_ShellTab.file(
          client: client,
          instanceUrl: inst.url,
          filePath: descriptor.filePath!,
          title: descriptor.title,
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
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      if (restored.isNotEmpty) {
        _tabs
          ..clear()
          ..addAll(restored);
        _activeIndex = saved.activeIndex.clamp(0, restored.length - 1);
        final active = _tabs[_activeIndex];
        _active = byUrl[active.instanceUrl];
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
    if (i >= 0) _activateTab(i);
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

  void _closeTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    if (_tabs[i].isMissionControl) return;
    final key = _tabs[i].key;
    setState(() {
      _clearTabState(key);
      // The pane holds a tab by reference; without this it would keep rendering
      // a tab that no longer exists in the strip.
      if (_splitTab?.key == key) _splitTab = null;
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        _activeIndex = -1;
      } else if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      } else if (i < _activeIndex) {
        _activeIndex--;
      }
    });
    _persistTabs();
    _syncPage();
  }

  void _activateTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    // PageView keeps each session mounted. Remove focus from the old composer
    // before changing pages so the platform text-input client cannot remain
    // attached to the previous session after a swipe or tab tap.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _activeIndex = i);
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
    final existing = _tabs.indexWhere(
        (t) => t.isFile && t.instanceUrl == url && t.filePath == path);
    setState(() {
      if (existing >= 0) {
        _activeIndex = existing;
      } else {
        _tabs.add(_ShellTab.file(
            client: client, instanceUrl: url, filePath: path, title: name));
        _activeIndex = _tabs.length - 1;
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
        _activeIndex = existing;
      } else {
        _tabs.add(_ShellTab.diff(
          client: client,
          instanceUrl: url,
          sessionId: sessionId,
          diffPath: f.path,
          title: name,
          diffStaged: staged,
          diffUntracked: f.untracked,
        ));
        _activeIndex = _tabs.length - 1;
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
      final key = _activeTab?.key;
      final host = key == null ? null : _termHosts[key];
      panel = TerminalsSidebarPanel(
        workspacePath: _activeWorkspaceFolder() ?? '',
        terminals: host?.terms ?? const <TerminalInfo>[],
        focus: host?.focus ?? -1,
        // Create and destroy happen HERE, in the sidebar: the pane can only
        // minimize. `shell_create` mints the id in the session; the shell then
        // reveals the pane so a new terminal is never invisible.
        onNewTerminal: () => _dispatchSessionAction('shell_create'),
        onOpenTerminal: (idx) => _dispatchSessionAction('shell_focus', '$idx'),
        onCloseTerminal: (id) => _dispatchSessionAction('shell_close', id),
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
              // Top Workspace / Session Tabs.
              //
              // Scrolls horizontally rather than overflowing: a long session
              // list slides, and the active chip is scrolled into view by
              // `_scrollStripToActive`. The strip is mutually exclusive with
              // the narrow-layout `_tabStrip`, so both may share this
              // controller.
              Expanded(
                child: SingleChildScrollView(
                  controller: _stripController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < _tabs.length; i++) ...[
                        _topWorkspaceTab(i),
                        const SizedBox(width: 4),
                      ],
                      const SizedBox(width: 4),
                      Center(
                        child: IconBtn(
                          'plus',
                          size: 24,
                          iconSize: 16,
                          tooltip: 'New session',
                          onTap: _newSessionFlow,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Right-side utilities: history, settings, and the active
                    // machine avatar. The avatar is also the machine switcher.
                    IconBtn(
                      'history',
                      size: 24,
                      iconSize: 16,
                      tooltip: 'History & Checkpoints',
                      onTap: _showCheckpointsDrawer,
                    ),
                    const SizedBox(width: 2),
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

  void _showCheckpointsDrawer() {
    final key = _activeTab?.key;
    if (key == null) return;
    _macSessionControls[key]?.performAction('checkpoints');
  }

  /// Top-level workspace tab chip in the window bar.
  Widget _topWorkspaceTab(int i) {
    final t = _tabs[i];
    final isActive = i == _activeIndex;
    final title = t.title.isEmpty ? '(untitled)' : t.title;
    final icon = _tabIconKind(t);

    final chip = GestureDetector(
      onTap: () => _activateTab(i),
      child: Container(
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
            AppIcon(
              icon,
              size: 18,
              color: isActive ? AppColors.fg2 : AppColors.fg4,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(
                  14,
                  weight: isActive ? W.label : W.body,
                  color: isActive ? AppColors.fg1 : AppColors.fg3,
                ),
              ),
            ),
            if (!t.isMissionControl) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _closeTab(i),
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

    // Dragging a tab out of the strip and dropping it on the body puts it in
    // the secondary pane. Long-press rather than an immediate drag: the strip
    // scrolls horizontally, and a plain Draggable would fight that gesture.
    return LongPressDraggable<_ShellTab>(
      data: t,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _tabDragFeedback(t),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: chip,
    );
  }

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

  /// The chat / content pane. Sits on the darkest canvas surface with a
  /// rounded top-left corner where it meets the chrome, matching the
  /// reference's `radius: 10 0 0 0` on the reading surface. No divider is
  /// drawn against the sidebar — the surface step is the separation.
  Widget _paneSurface({required Widget child, bool roundRight = false}) =>
      Container(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(R.sheetTop),
            topRight:
                roundRight ? const Radius.circular(R.sheetTop) : Radius.zero,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  /// Header for the secondary pane: the tab's icon + title, and a close.
  Widget _splitHeader(_ShellTab t) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          AppIcon(_tabIconKind(t), size: 13, color: AppColors.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              t.title.isEmpty ? '(untitled)' : t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12.5, weight: W.label, color: AppColors.fg1),
            ),
          ),
          IconBtn(
            'x',
            size: 24,
            iconSize: 12,
            tooltip: 'Close pane',
            onTap: _closeSplitPane,
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
      onTitle: (title) => _onSessionTitle(t.sessionId!, title),
      onMenu: null,
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
  Widget _bodyRow({required bool topInset}) {
    final multi = _rightPaneOpen;
    // Width-driven, not flex-driven: a fixed flex ratio cannot be dragged, and
    // the pane has a natural width (a terminal needs columns; a readout does
    // not stretch to 45% of a 4K window).
    final row = Row(children: [
      SizedBox(
        width: kSidebarWidth,
        child: _sidebar(topInset: topInset),
      ),
      // No divider: the sidebar (bg) and the chat canvas are different
      // surfaces, which is the separation.
      Expanded(
        child: _paneSurface(
          roundRight: !multi,
          child: _mainPane(),
        ),
      ),
      if (multi) ...[
        _paneResizeHandle(),
        SizedBox(
          width: _paneWidth.clamp(kPaneMinWidth, double.infinity),
          child: _rightPane(),
        ),
      ],
    ]);
    return Expanded(
      child: DragTarget<_ShellTab>(
        onWillAcceptWithDetails: (d) =>
            // A lone tab cannot be split from itself: there would be nothing
            // left in the primary pane.
            !(d.data.key == _activeTab?.key && _tabs.length == 1),
        onAcceptWithDetails: (d) => _splitWith(d.data),
        builder: (_, __, ___) => row,
      ),
    );
  }

  /// 6px grab zone between the panes. The reference has no drawn divider — the
  /// surface step separates them — so the rule only appears on hover.
  Widget _paneResizeHandle() => MouseRegion(
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
            width: 6,
            child: Center(
              child: Container(
                width: 1,
                color:
                    _paneHandleHover ? AppColors.border2 : Colors.transparent,
              ),
            ),
          ),
        ),
      );

  /// Contents of the secondary pane. The caller supplies the flex, so this
  /// returns content only.
  ///
  /// Default state is a SINGLE pane: nothing here unless something was
  /// deliberately moved across. There is no split toggle — dragging a tab out
  /// of the strip is what creates this pane (`_splitWith`).
  Widget _rightPane() {
    if (_rightAgent != null) {
      return CoordinationAgentDetail(
        agent: _rightAgent!,
        embedded: true,
        onClose: _closeSplitPane,
      );
    }
    if (_rightPanel != _RightPanel.none) return _rightPanelView();
    final t = _splitTab;
    if (t == null) return const SizedBox.shrink();
    return Container(
      // Floor surface, rounded on the TOP-RIGHT only. The reference leaves the
      // bottom-right square: the pane is flush to the window's bottom edge, so
      // a bottom curve would cut a notch out of the window frame.
      decoration: BoxDecoration(
        color: AppColors.floor,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(R.sheetTop),
        ),
      ),
      child: Column(children: [
        _splitHeader(t),
        Expanded(child: _tabBody(t, primary: false)),
      ]),
    );
  }

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
      case _RightPanel.terminal:
        final host = tab == null ? null : _termHosts[tab.key];
        body = host == null || host.terms.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No terminals. Create one from the sidebar.',
                    style: sans(12.5, color: AppColors.fg3)),
              )
            : host.buildView(host.activeId!, mobileKeys: false);
        break;
      case _RightPanel.none:
        body = const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.floor,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(R.sheetTop),
        ),
      ),
      child: Column(children: [
        PaneTabStrip(
          tabs: [PaneTab(label: _rightPanel.label, icon: _rightPanel.icon)],
          activeIndex: 0,
          actions: [
            // A terminal MINIMIZES; it is never destroyed here. Destroying is
            // the sidebar panel's job, so a collapsed view can never take a
            // running pty with it.
            if (_rightPanel == _RightPanel.terminal)
              IconBtn('minimize',
                  size: 24,
                  iconSize: 12,
                  tooltip: 'Minimize pane',
                  onTap: () => setState(() => _termMinimized = true))
            else
              IconBtn('x',
                  size: 24,
                  iconSize: 12,
                  tooltip: 'Close pane',
                  onTap: _closeSplitPane),
          ],
        ),
        Expanded(child: body),
      ]),
    );
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
                    child: t.isDiff
                        ? GitFileDiffView(
                            key: ValueKey(t.key),
                            client: t.client,
                            sessionId: t.sessionId ?? '',
                            file: t.diffPath!,
                            staged: t.diffStaged,
                            untracked: t.diffUntracked,
                            embedded: true,
                          )
                        : t.isFile
                            ? FileViewer(
                                key: ValueKey(t.key),
                                client: t.client,
                                path: t.filePath!,
                                name: t.title,
                                embedded: true,
                                onClose: () => _closeTabByKey(t.key),
                              )
                            : SessionScreen(
                                key: ValueKey(t.key),
                                client: t.client,
                                sessionId: t.sessionId!,
                                title: t.title,
                                profile: t.profile,
                                embedded: true,
                                inboundShare: t.inboundShare,
                                onShareConsumed: t.inboundShare == null
                                    ? null
                                    : () =>
                                        setState(() => t.inboundShare = null),
                                acceptDrops: i == _activeIndex,
                                onTitle: (title) =>
                                    _onSessionTitle(t.sessionId!, title),
                                onMenu: null,
                                onOpenFileTab: (path, name) => _openFileTab(
                                    t.client, t.instanceUrl, path, name),
                                onOpenSession: _openSession,
                                onMacStatus: (state, running) =>
                                    _setMacSessionStatus(t.key, state, running),
                                onMacControls: !kMobile
                                    ? (stop, performAction) =>
                                        _setMacSessionControls(
                                            t.key, stop, performAction)
                                    : null,
                                onTerminalHost: !kMobile
                                    ? (host, open) =>
                                        _setTerminalHost(t.key, host, open)
                                    : null,
                              ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    ]);
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
            if (!t.isMissionControl) ...[
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
            if (!t.isMissionControl) ...[
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
                  // Conversations section header with filter icon.
                  if (hasClient && (_sessions?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                      child: _selecting
                          ? Row(children: [
                              Text('${_selected.length} selected',
                                  style: sans(16,
                                      weight: W.label, color: AppColors.fg1)),
                              const Spacer(),
                              IconBtn('x',
                                  size: 32,
                                  iconSize: 18,
                                  tooltip: 'Cancel',
                                  onTap: _exitSelect),
                              IconBtn('trash',
                                  size: 32,
                                  iconSize: 16,
                                  tooltip: 'Delete selected',
                                  onTap: _selected.isEmpty
                                      ? null
                                      : _confirmDeleteSelected),
                            ])
                          : Row(children: [
                              Text('Conversations',
                                  style: sans(20,
                                      weight: W.label, color: AppColors.fg1)),
                              const Spacer(),
                              GestureDetector(
                                onTap: _showFilterSheet,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: AppIcon('sliders',
                                      size: 20,
                                      color: _filter != 'all'
                                          ? AppColors.accent
                                          : AppColors.fg3),
                                ),
                              ),
                            ]),
                    ),
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
          // Bottom actions row: search + folder + settings + machine avatar.
          _mobileBottomBar(),
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
              child: Row(children: [
                Text('${_selected.length} selected',
                    style: sans(11.5, color: AppColors.fg3)),
                const Spacer(),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: _missionControlPin(mc.first),
    );
  }

  /// Bottom bar on mobile: full-width search pill + settings + new-chat.
  Widget _mobileBottomBar() {
    final hasClient = widget.client != null;
    final a = widget.active;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          10 +
              MediaQuery.of(context)
                  .padding
                  .bottom), // safe-area-ish bottom padding
      // No hairline: the bar sits on its own surface step.
      decoration: BoxDecoration(color: AppColors.bg),
      child: Row(children: [
        // Search pill.
        Expanded(
          child: GestureDetector(
            onTap: hasClient ? _openSearch : null,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                AppIcon('search', size: 16, color: AppColors.fg4),
                const SizedBox(width: 8),
                Text('Search…', style: sans(13.5, color: AppColors.fg4)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconBtn('folder',
            size: 38,
            iconSize: 19,
            tooltip: 'Browse',
            onTap: hasClient ? widget.onNewSession : null),
        const SizedBox(width: 2),
        IconBtn('settings',
            size: 38,
            iconSize: 19,
            tooltip: 'Settings',
            onTap: hasClient ? _openSettings : null),
        const SizedBox(width: 2),
        // Small machine avatar — tap to switch machines.
        GestureDetector(
          onTap: hasClient
              ? (widget.instances.isEmpty
                  ? widget.onAddInstance
                  : _openMachines)
              : null,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 1),
            ),
            alignment: Alignment.center,
            child: a == null
                ? AppIcon('plus', size: 14, color: AppColors.fg2)
                : Text(
                    (a.label.isNotEmpty ? a.label[0] : '?').toUpperCase(),
                    style: sans(13, weight: W.label, color: AppColors.fg1),
                  ),
          ),
        ),
      ]),
    );
  }

  // Phone metrics come from the shared M table so the two densities cannot
  // drift; desktop values stay local because they are already tokenised.
  double get _navText => kMobile ? M.navText : 13;
  double get _navIcon => kMobile ? M.navIcon : 16;
  double get _navPadV => kMobile ? 13 : 8;
  double get _rowTitle => kMobile ? M.rowTitle : 12.5;
  double get _rowTime => kMobile ? M.rowTime : 10;

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
    final children = <Widget>[];
    if (!kMobile && mc.isNotEmpty) {
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
      return GestureDetector(
        onTap: open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentBg : AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: selected ? AppColors.accentLine : AppColors.border,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Text('Mission Control',
                  style: sans(15.5, weight: W.label, color: AppColors.fg1)),
            ),
            if (status != null) status,
          ]),
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
    return GestureDetector(
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: checked ? AppColors.accentBg : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (_selecting) ...[
            AppIcon(checked ? 'check' : 'plus',
                size: 16, color: checked ? AppColors.accent : AppColors.fg4),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: renaming
                ? _inlineRenameField(s, compact: false)
                : Text(
                    s.title.isEmpty ? '(untitled)' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15.5, color: AppColors.fg1),
                  ),
          ),
          if (!renaming) ...[
            const SizedBox(width: 10),
            Text(relativeTime(s.lastActive),
                style: sans(12, color: AppColors.fg4)),
          ],
          if (!_selecting && (running || waiting)) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: running ? AppColors.run : AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
          if (!_selecting && !renaming) ...[
            const SizedBox(width: 2),
            IconBtn('more-vertical',
                size: 32,
                iconSize: 16,
                tooltip: 'Options',
                onTap: () => _sessionActions(s)),
          ],
        ]),
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
