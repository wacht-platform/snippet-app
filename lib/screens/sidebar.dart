import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../api.dart';
import '../drafts.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agents_sidebar_panel.dart';
import 'list_search_field.dart';
import 'mission_control.dart';
import 'mission_control_card.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'settings_panel.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_nav.dart';
import 'sidebar_mobile.dart';
import 'tasks/tasks_panel.dart';
import '../pull_refresh.dart';
import '../motion.dart';
export 'sidebar_mobile.dart';

class Sidebar extends StatefulWidget {
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

  /// Phone home destination + its setter. Owned by the shell so that back can
  /// return to Chats; passed down because the phone home IS this widget.
  final MobileHome mobileHome;
  final ValueChanged<MobileHome> onMobileHome;

  /// Phone drill-down state + setters. Also shell-owned, for the same reason:
  /// the back handler and the bar's visibility both live up there.
  final SettingsPage? settingsSection;
  final ValueChanged<SettingsPage?> onSettingsSection;
  final CoordinationAgent? agent;
  final ValueChanged<CoordinationAgent?> onAgent;
  final VoidCallback? onSettingsClose;

  const Sidebar({
    super.key,
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
    required this.mobileHome,
    required this.onMobileHome,
    required this.settingsSection,
    required this.onSettingsSection,
    required this.agent,
    required this.onAgent,
    this.onSettingsClose,
  });
  @override
  State<Sidebar> createState() => SidebarState();
}

class SidebarState extends State<Sidebar> {
  DateTime? _chatsShownAt;
  // The session list now lives in the shell (passed via widget.sessions); the
  // sidebar is presentational, so opening the drawer doesn't refetch.
  String _filterQuery = '';
  String _agentFilterQuery = '';
  final _machineKey = GlobalKey(); // anchors the desktop machine popover
  final GlobalKey<TasksPanelState> _tasksPanelKey =
      GlobalKey<TasksPanelState>();
  final GlobalKey<SettingsPanelState> _mobileSettingsKey =
      GlobalKey<SettingsPanelState>();
  SettingsPage? _pendingSettingsCreate;
  final GlobalKey<AgentsSidebarPanelState> _agentsPanelKey =
      GlobalKey<AgentsSidebarPanelState>();
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Phone search: a filter field at the top of each tab.
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _agentSearchCtl = TextEditingController();
  final FocusNode _agentSearchFocus = FocusNode();

  /// Desktop search in section headers.
  bool _desktopChatsSearchOpen = false;
  final TextEditingController _desktopChatsSearchCtl = TextEditingController();
  final FocusNode _desktopChatsSearchFocus = FocusNode();

  /// True while a nested phone screen is open, in which case the bar hides.
  ///
  /// Read from the widget rather than re-deriving it here: the state is
  /// shell-owned (the back handler needs it too), and the bar is rendered from
  /// THIS state, so this is the only place both are in scope.
  bool get _mobileDrilledDown =>
      widget.settingsSection != null || widget.agent != null;

  MobileHome _lastMainHome = MobileHome.chats;
  late final PageController _pageController;
  int? _targetPage;

  void _goToPage(int index) {
    if (_pageController.hasClients) {
      _targetPage = index;
      _pageController
          .animateToPage(
        index,
        duration: Motion.base,
        curve: Motion.enter,
      )
          .then((_) {
        if (mounted && _targetPage == index) {
          setState(() => _targetPage = null);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    Drafts.instance.addListener(_onDrafts);
    _pageController = PageController(initialPage: widget.mobileHome.index);
    if (widget.mobileHome != MobileHome.settings) {
      _lastMainHome = widget.mobileHome;
    }
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mobileHome != widget.mobileHome) {
      if (oldWidget.mobileHome != MobileHome.settings) {
        _lastMainHome = oldWidget.mobileHome;
      }
      if (_targetPage != widget.mobileHome.index &&
          _pageController.hasClients) {
        final current =
            _pageController.page?.round() ?? _pageController.initialPage;
        if (current != widget.mobileHome.index) {
          _goToPage(widget.mobileHome.index);
        }
      }
    }
  }

  String? _renamingId;
  String? _hoveredId;
  final TextEditingController _renameCtl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  void _onDrafts() {
    if (mounted) setState(() {});
  }

  /// Whether a chat you are not looking at has unsent text waiting.
  bool _hasDraft(SessionInfo s) {
    final c = widget.client;
    return c != null &&
        s.id != widget.selectedSessionId &&
        Drafts.instance.has(Drafts.keyFor(c.baseUrl, s.id));
  }

  @override
  void dispose() {
    Drafts.instance.removeListener(_onDrafts);
    _pageController.dispose();
    _renameCtl.dispose();
    _renameFocus.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _agentSearchCtl.dispose();
    _agentSearchFocus.dispose();
    _desktopChatsSearchCtl.dispose();
    _desktopChatsSearchFocus.dispose();
    super.dispose();
  }

  final Set<String> _deleting = {};

  List<SessionInfo>? get _sessions => _deleting.isEmpty
      ? widget.sessions
      : widget.sessions?.where((s) => !_deleting.contains(s.id)).toList();
  bool get _loading => widget.sessionsLoading;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final hasClient = widget.client != null;
    return Container(
      color: !kMobile ? Colors.transparent : AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.topInset && kMacOS) SizedBox(height: kMacTitlebar + 6),
        if (kMobile) ...[
          // The bar is a SIBLING of the content, not an overlay: the content
          // gets the remaining height, so nothing hides behind the bar and no
          // scroll-padding hack is needed. It still reads as floating (inset,
          // rounded, raised).
          // PageView gives smooth swiping left and right across sessions,
          // settings, and agents, with slide transitions when navigating.
          Expanded(
            child: Stack(children: [
              PageView(
                controller: _pageController,
                physics: _mobileDrilledDown
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                onPageChanged: (index) {
                  if (_targetPage != null && _targetPage != index) {
                    return;
                  }
                  _targetPage = null;
                  final dest = MobileHome.values[index];
                  if (widget.mobileHome != dest) {
                    widget.onMobileHome(dest);
                  }
                },
                children: [
                  for (final h in MobileHome.values)
                    SidebarKeepAlivePage(
                      key: ValueKey('mobile-${h.name}'),
                      child: _mobileHomeBody(hasClient, h),
                    ),
                ],
              ),
            ]),
          ),
          // The bar names the app's TOP LEVEL, so it hides inside a nested
          // screen, where it would be a second exit that skips the level you
          // are in. It also steps aside while the keyboard is up, so a search
          // keeps the whole screen for its results.
          if (!_mobileDrilledDown && !_keyboardUp)
            SidebarMobileBar(
              activeHome: widget.mobileHome,
              newLabel: _newLabel,
              onNew: _showNewButton(hasClient) ? _handleMobileNew : null,
              onMobileHome: (h) {
                if (widget.mobileHome != h) {
                  _goToPage(h.index);
                  widget.onMobileHome(h);
                }
              },
            ),
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s8, S.s4),
              child: _selectionBar(mobile: false),
            ),
          // Sectioned, collapsible sidebar — the reference's left column.
          Expanded(child: _sectionedSidebar()),
        ],
      ]),
    );
  }

  /// Full-surface placeholder for a phone destination with no machine.
  ///
  /// Local to the sidebar rather than reusing the shell's `_sidebarUnavailable`:
  /// that one is a `_DesktopShellState` method and is not in scope here.
  Widget _mobileUnavailable(String message) => EmptyState(
        icon: 'server',
        title: 'No machine yet',
        body: message,
        action: Btn('Add machine',
            icon: 'plus', small: true, onTap: widget.onAddInstance),
      );

  /// The phone home body for the destination the bar currently selects.
  ///
  /// Each destination gets the whole surface below the bar. Chats keeps a head
  /// for its title and context controls; Agents and Settings own their own
  /// headers, so they render directly.
  Widget _mobileHomeBody(bool hasClient, [MobileHome? home]) {
    final destination = home ?? widget.mobileHome;
    switch (destination) {
      case MobileHome.chats:
        // The header STAYS while searching. It names the machine whose chats are
        // being filtered — hiding it exactly when you are narrowing a machine's
        // chats took away the context you were filtering against.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mobileChatsHeader(hasClient),
            if (hasClient && !_selecting)
              _mobileSearch(_searchCtl, 'Search chats',
                  (v) => setState(() => _filterQuery = v)),
            Expanded(
              child: !hasClient
                  ? _mobileUnavailable('Add a machine to begin.')
                  : _sessionList(),
            ),
            if (_selecting) _mobileSelectionActions(),
          ],
        );

      case MobileHome.tasks:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its tasks.');
        }
        return TasksPanel(
          key: _tasksPanelKey,
          client: client,
          trailing: const [],
        );

      case MobileHome.agents:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its agents.');
        }
        // Drilled into one agent: same shared header as every other nested
        // phone screen, with smooth slide-and-fade screen transition.
        final agent = widget.agent;
        return AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, anim) {
            final isDetail = child.key == const ValueKey('agent-detail');
            final dx = isDetail ? 0.08 : -0.08;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: agent != null
              ? CoordinationAgentDetail(
                  key: const ValueKey('agent-detail'),
                  agent: agent,
                  client: client,
                  embedded: false,
                  onClose: () => widget.onAgent(null),
                )
              : Column(
                  key: const ValueKey('agents-list'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _mobileAgentsHeader(hasClient),
                    _mobileSearch(_agentSearchCtl, 'Search agents',
                        (v) => setState(() => _agentFilterQuery = v)),
                    Expanded(
                      child: AgentsSidebarPanel(
                        key: _agentsPanelKey,
                        client: client,
                        searchQuery: _agentFilterQuery,
                        onSearchChanged: (v) => setState(() {
                          _agentFilterQuery = v;
                          if (_agentSearchCtl.text != v) {
                            _agentSearchCtl.text = v;
                          }
                        }),
                        onOpenAgent: (a) => widget.onAgent(a),
                        onOpenMissionControl: widget.onOpenMissionControl,
                      ),
                    ),
                  ],
                ),
        );

      case MobileHome.settings:
        final client = widget.client;
        if (client == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _mobileSettingsHeader(),
              Expanded(
                child: _mobileUnavailable('Add a machine to configure it.'),
              ),
            ],
          );
        }
        final section = widget.settingsSection;
        return AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, anim) {
            final isDetail = child.key == const ValueKey('settings-detail');
            final dx = isDetail ? 0.08 : -0.08;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: section != null
              ? SettingsPanel(
                  key: const ValueKey('settings-detail'),
                  client: client,
                  instances: widget.instances,
                  active: widget.active,
                  onRemove: widget.onRemoveInstance,
                  section: section,
                  onSection: widget.onSettingsSection,
                  onClose: () => widget.onSettingsSection(null),
                  embedded: true,
                  createOnOpen:
                      _pendingSettingsCreate == section ? section : null,
                  onCreateHandled: () =>
                      setState(() => _pendingSettingsCreate = null),
                )
              : Column(
                  key: const ValueKey('settings-root'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _mobileSettingsHeader(),
                    Expanded(
                      child: SettingsPanel(
                        key: _mobileSettingsKey,
                        client: client,
                        instances: widget.instances,
                        active: widget.active,
                        onRemove: widget.onRemoveInstance,
                        section: widget.settingsSection,
                        onSection: widget.onSettingsSection,
                        onClose: () {
                          if (widget.onSettingsClose != null) {
                            widget.onSettingsClose!();
                          } else {
                            widget.onMobileHome(_lastMainHome);
                          }
                        },
                        embedded: true,
                      ),
                    ),
                  ],
                ),
        );
    }
  }

  Future<void> _openCreateAgent([BuildContext? anchorCtx]) async {
    final client = widget.client;
    if (client == null) return;
    if (_agentsPanelKey.currentState != null) {
      await _agentsPanelKey.currentState!.openCreateAgent(anchorCtx);
    } else {
      await showCreateAgentDialog(context, client, anchorContext: anchorCtx);
    }
  }

  /// The Chats header: the destination name on the left, icon buttons on
  /// the right for search, new chat, Mission Control and machine avatar.
  Widget _mobileChatsHeader(bool hasClient) {
    if (_selecting) {
      final n = _selected.length;
      // Same footprint as the title row, so entering selection doesn't jump
      // the list; Delete lives in the bottom bar.
      return Padding(
        padding: const EdgeInsets.fromLTRB(S.s4, 16, M.gutter, 6),
        child: SizedBox(
          height: M.minTarget,
          child: Row(children: [
            IconBtn('x',
                size: M.minTarget,
                iconSize: 20,
                tooltip: 'Cancel',
                onTap: _exitSelect),
            const SizedBox(width: S.s4),
            Expanded(
              child: Text(n == 0 ? 'Select chats' : '$n selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? M.sectionTitle : 15,
                      weight: W.label, color: AppColors.fg1)),
            ),
            _selectAllToggle(),
          ]),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Chats', style: TS.pageTitle()),
        const Spacer(),
        ..._headerTrailing(hasClient),
      ]),
    );
  }

  Widget _mobileAgentsHeader(bool hasClient) {
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Agents', style: TS.pageTitle()),
        const Spacer(),
        ..._headerTrailing(hasClient),
      ]),
    );
  }

  /// The control at the right of every phone page header: the machine
  /// switcher.
  List<Widget> _headerTrailing(bool hasClient) => [_machineAvatarButton()];

  /// The filter field under a phone page header.
  Widget _mobileSearch(TextEditingController controller, String hint,
          ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 6),
        child: ListSearchField(
            controller: controller, hint: hint, onChanged: onChanged),
      );

  Widget _mobileSettingsHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Settings', style: TS.pageTitle()),
        const Spacer(),
        _machineAvatarButton(),
      ]),
    );
  }

  /// Machine switcher, as a small round button: the machine's initial plus a
  /// reachability dot, matching the desktop window bar's avatar so the two read
  /// as the same control.
  Widget _machineAvatarButton() {
    final a = widget.active;
    final ok = a == null ? null : widget.health[a.url];
    final initial = a == null || a.label.trim().isEmpty
        ? '+'
        : a.label.trim().characters.first.toUpperCase();
    return Tooltip(
      message: a == null ? 'Add machine' : 'Switch machine',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap:
              widget.instances.isEmpty ? widget.onAddInstance : _openMachines,
          child: SizedBox(
            width: M.minTarget,
            height: M.minTarget,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Text(initial,
                        style: sans(13, weight: W.title, color: AppColors.fg1)),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 9,
                      height: 9,
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
      ),
    );
  }

  bool get _keyboardUp => MediaQuery.viewInsetsOf(context).bottom > 0;

  /// The bar's New button: at the top level, out of the way while selecting
  /// chats. Settings can always add a machine, so it needs no connection.
  bool _showNewButton(bool hasClient) =>
      (hasClient || widget.mobileHome == MobileHome.settings) &&
      !_mobileDrilledDown &&
      !_selecting;

  String get _newLabel => switch (widget.mobileHome) {
        MobileHome.chats => 'New chat',
        MobileHome.tasks => 'New task',
        MobileHome.agents => 'New agent',
        MobileHome.settings => 'Create',
      };

  void _handleMobileNew() {
    switch (widget.mobileHome) {
      case MobileHome.chats:
        widget.onNewSession();
      case MobileHome.tasks:
        _tasksPanelKey.currentState?.create();
      case MobileHome.agents:
        _openCreateAgent();
      case MobileHome.settings:
        _openSettingsCreate();
    }
  }

  Future<void> _openSettingsCreate() async {
    if (widget.client == null) {
      widget.onAddInstance();
      return;
    }
    const items = [
      (
        SettingsPage.general,
        'server',
        'Machine',
        'Connect another computer running snippet'
      ),
      (
        SettingsPage.models,
        'ai-chip',
        'Inference profile',
        'A model and provider chats can run on'
      ),
      (
        SettingsPage.vault,
        'lock-key',
        'Vault secret',
        'A key or token your agents can use'
      ),
      (
        SettingsPage.scheduled,
        'repeat',
        'Scheduled job',
        'A prompt that runs on a schedule'
      ),
    ];
    final picked = await showAppSheet<SettingsPage>(
      context,
      title: 'Create',
      child: Builder(
        builder: (sheetContext) => ListGroup(children: [
          for (final (page, icon, title, subtitle) in items)
            ListRow(
              leading: IconTile(icon),
              title: title,
              subtitle: subtitle,
              trailing:
                  AppIcon('chevron-right', size: 14, color: AppColors.fg4),
              onTap: () => Navigator.of(sheetContext).pop(page),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _pendingSettingsCreate = picked);
    widget.onSettingsSection(picked);
  }

  bool _matchesQuery(SessionInfo s) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.title.toLowerCase().contains(q) ||
        s.projectFolder.toLowerCase().contains(q) ||
        (s.branch?.toLowerCase().contains(q) ?? false);
  }

  List<SessionInfo> _sortSessionsByRecency(Iterable<SessionInfo> sessions) {
    final sorted = sessions.toList();
    sorted.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return sorted;
  }

  Widget _sessionList() {
    if (_loading && _sessions == null) {
      return Center(child: DelayedSpinner(size: 20));
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
                        textAlign: TextAlign.center, style: TS.meta()),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: widget.onRefreshSessions,
                        child: Text('Retry',
                            style: sans(12, color: AppColors.accent))),
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
                    textAlign: TextAlign.center, style: TS.meta())),
          ]);
    }
    final mc = all.where((s) => isDedicatedMcSession(s.id)).toList();
    final list = _sortSessionsByRecency(all.where((s) =>
        !isDedicatedMcSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s)));
    // Phone chats are one flat, chronological surface.
    if (kMobile) {
      final allSorted = _sortSessionsByRecency(list);
      final mobileChildren = <Widget>[];
      final client = widget.client;
      if (client != null &&
          mc.isNotEmpty &&
          !_selecting &&
          _filterQuery.trim().isEmpty) {
        mobileChildren.add(MissionControlCard(
          client: client,
          session: mc.first,
          waitingChats:
              allSorted.where((s) => s.status == 'waiting_for_input').length,
          onOpen: widget.onOpenMissionControl,
        ));
      }
      String? section;
      for (var i = 0; i < allSorted.length; i++) {
        final session = allSorted[i];
        final label = _daySection(session.lastActive);
        if (label != section) {
          section = label;
          mobileChildren.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 10 : 22, bottom: 4),
            child: Text(label,
                style: sans(12, weight: W.strong, color: AppColors.fg4)),
          ));
        }
        final next = i + 1 < allSorted.length ? allSorted[i + 1] : null;
        final lastInSection =
            next == null || _daySection(next.lastActive) != label;
        _chatsShownAt ??= DateTime.now();
        mobileChildren.add(Appear(
          key: ValueKey('chat-${session.id}'),
          index: i,
          since: _chatsShownAt,
          child: _sessionCard(session, divider: !lastInSection),
        ));
      }
      if (mobileChildren.isEmpty) {
        mobileChildren.add(Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
              _filterQuery.trim().isNotEmpty
                  ? 'No chats match the search.'
                  : 'No chats yet.',
              textAlign: TextAlign.center,
              style: TS.meta()),
        ));
      }
      return PullToRefresh(
        onRefresh: () async => widget.onRefreshSessions(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 16),
          children: mobileChildren,
        ),
      );
    }
    final children = <Widget>[];
    if (mc.isNotEmpty) {
      children.add(_missionControlPin(mc.first));
    }
    // Purely based on recency.
    list.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    for (var i = 0; i < list.length; i++) {
      if (kMobile) {
        children.add(Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _sessionCard(list[i])));
      } else {
        children.add(_desktopTreeRow(list[i], last: i == list.length - 1));
      }
    }
    if (list.isEmpty && mc.isEmpty) {
      children.add(Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Nothing here.',
              textAlign: TextAlign.center, style: TS.meta())));
    }
    final listView = ListView(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 14, 2, kMobile ? M.gutter : 14, 32),
        children: children);
    // Phones: the natural refresh gesture. Desktop keeps the header button.
    if (!kMobile) return listView;
    return PullToRefresh(
      onRefresh: () async => widget.onRefreshSessions(),
      child: listView,
    );
  }

  /// Desktop sidebar as a single recency-ordered chat stream. Workspace is
  /// metadata on each row, never a grouping or sort key.
  Widget _sectionedSidebar() {
    final hasClient = widget.client != null;
    final all = _sessions ?? const <SessionInfo>[];
    final list = _sortSessionsByRecency(all.where((s) =>
        !isDedicatedMcSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s)));

    final mc = all.where((s) => isDedicatedMcSession(s.id)).toList();
    final client = widget.client;
    final rows = <Widget>[];
    String? day;
    for (final s in list) {
      final label = _daySection(s.lastActive);
      if (label != day) {
        day = label;
        rows.add(Padding(
          padding: EdgeInsets.fromLTRB(10, rows.isEmpty ? 4 : 14, 10, 4),
          child: Text(label, style: sans(12, color: AppColors.fg4)),
        ));
      }
      _chatsShownAt ??= DateTime.now();
      rows.add(Appear(
        key: ValueKey('chat-${s.id}'),
        index: rows.length,
        since: _chatsShownAt,
        child: _desktopChatRow(s),
      ));
    }
    return PullToRefresh(
      onRefresh: () async => widget.onRefreshSessions(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2, bottom: 16),
        children: [
          ShellSectionHeader(
            label: 'Chats',
            actions: [
              ShellSectionAction(
                icon: 'search',
                tooltip: 'Search chats',
                onTap: () {
                  setState(() {
                    _desktopChatsSearchOpen = !_desktopChatsSearchOpen;
                    if (!_desktopChatsSearchOpen) {
                      _desktopChatsSearchCtl.clear();
                      _filterQuery = '';
                    }
                  });
                  if (_desktopChatsSearchOpen) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _desktopChatsSearchFocus.requestFocus();
                    });
                  }
                },
              ),
              ShellSectionAction(
                icon: 'plus',
                tooltip: 'New chat',
                onTap: hasClient ? widget.onNewSession : null,
              ),
            ],
          ),
          if (_desktopChatsSearchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Row(
                  children: [
                    AppIcon('search', size: 14, color: AppColors.fg3),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _desktopChatsSearchCtl,
                        focusNode: _desktopChatsSearchFocus,
                        onChanged: (v) => setState(() => _filterQuery = v),
                        style: sans(13, color: AppColors.fg1),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Search chats…',
                          hintStyle: TS.meta(AppColors.fg4),
                        ),
                      ),
                    ),
                    if (_desktopChatsSearchCtl.text.isNotEmpty)
                      IconBtn('x', size: 20, iconSize: 10, tooltip: 'Clear',
                          onTap: () {
                        _desktopChatsSearchCtl.clear();
                        setState(() => _filterQuery = '');
                      }),
                  ],
                ),
              ),
            ),
          if (!hasClient)
            const SidebarEmpty('Add a machine to begin.')
          else if (list.isEmpty)
            // Distinguish "no conversations" from "none match the search": saying
            // "No chats yet" over a searched list reads as data loss.
            SidebarEmpty(_filterQuery.trim().isNotEmpty
                ? 'No chats match the search.'
                : 'No chats yet.')
          else ...[
            if (client != null &&
                mc.isNotEmpty &&
                !_selecting &&
                _filterQuery.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                child: MissionControlCard(
                  client: client,
                  session: mc.first,
                  waitingChats:
                      list.where((s) => s.status == 'waiting_for_input').length,
                  onOpen: widget.onOpenMissionControl,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _desktopChatRow(SessionInfo s) {
    final selected = s.id == widget.selectedSessionId;
    if (_renamingId == s.id) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: _inlineRenameField(s, compact: true),
      );
    }
    final checked = _selected.contains(s.id);
    final folderName = s.projectFolder.trim().isEmpty
        ? ''
        : lastPathSegment(s.projectFolder, ifEmpty: s.projectFolder);
    final draft = _hasDraft(s);
    final on = _selecting ? checked : selected;
    return Material(
      color: on ? AppColors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _selecting
            ? () => _toggleSelected(s.id)
            : () => widget.onOpenSession(s.id, s.title, s.profile),
        onSecondaryTapDown: _selecting
            ? null
            : (d) => _sessionActions(s, position: d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(children: [
            if (_selecting) ...[
              SelectCheck(checked, size: 14),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          s.title.trim().isEmpty ? '(untitled)' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14,
                              height: 19 / 14,
                              color: selected ? AppColors.fg1 : AppColors.fg2)),
                    ),
                    if (draft) ...[
                      const SizedBox(width: 8),
                      Text('Draft', style: sans(12, color: AppColors.accent)),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 12),
                    child: _sessionStatusLine(s, folderName, compact: true),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _desktopTreeRow(SessionInfo s, {required bool last}) {
    return _sessionRow(s);
  }

  Widget _missionControlPin(SessionInfo s) {
    final selected = !kMobile && s.id == widget.selectedSessionId;
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
                    style: sans(kMobile ? M.rowTitle : 13,
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
        // Surface step, matching the mobile branch above AND every other
        // selection in the shell. This one used `accentBg`, so the same pinned
        // row changed colour with the window width and read as an alert on
        // desktop — accent is reserved for state (running / needs-attention).
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: open,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              AppIcon('layers',
                  size: 16, color: selected ? AppColors.fg1 : AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mission Control',
                    style: sans(13,
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
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final hovered = !kMobile && _hoveredId == s.id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredId = s.id),
      onExit: (_) {
        if (_hoveredId == s.id) setState(() => _hoveredId = null);
      },
      child: Material(
        color: _selecting && checked
            ? AppColors.accentBg
            : (selected ? AppColors.surface2 : Colors.transparent),
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
          // Right-click is the desktop way to reach a session's actions;
          // phones use long-press (select) and the row's menu.
          onSecondaryTapDown: (renaming || kMobile)
              ? null
              : (details) =>
                  _sessionActions(s, position: details.globalPosition),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              if (_selecting) ...[
                SelectCheck(checked, size: 16),
                const SizedBox(width: S.s8),
              ] else ...[
                // Always present, so titles share one left edge; the colour is
                // what carries state.
                SessionStateIcon(status: s.status, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: renaming
                      ? _inlineRenameField(s, compact: true)
                      : Text(s.title.isEmpty ? '(untitled)' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
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
                ] else if (_hasDraft(s)) ...[
                  const SizedBox(width: 8),
                  Text('draft', style: mono(10, color: AppColors.accent)),
                ] else ...[
                  const SizedBox(width: 8),
                  Text(relativeTime(s.lastActive),
                      // A timestamp is content, not a placeholder.
                      style: mono(10,
                          color: waiting ? AppColors.accent : AppColors.fg3)),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
  }

  String _daySection(int lastActive) {
    final when = DateTime.fromMillisecondsSinceEpoch(lastActive * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Earlier this week';
    return 'Older';
  }

  Widget _sessionStatusLine(SessionInfo s, String folderName,
      {bool compact = false}) {
    final running = sessionIsActive(s.status);
    final waiting = s.status == 'waiting_for_input';
    final color =
        waiting ? AppColors.accent : (running ? AppColors.fg3 : AppColors.fg3);
    final label = waiting
        ? 'Waiting for your answer'
        : running
            ? (folderName.isEmpty ? 'Working' : 'Working · $folderName')
            : folderName;
    return Row(children: [
      if (running || waiting) ...[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: running ? AppColors.run : Colors.transparent,
            border: waiting
                ? Border.all(color: AppColors.accent, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 6),
      ],
      if (!running && !waiting && s.inWorktree) ...[
        AppIcon('git-branch', size: 12, color: AppColors.fg4),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
            label.isEmpty && compact ? relativeTime(s.lastActive) : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(compact ? 12 : 13,
                height: compact ? 16 / 12 : 18 / 13,
                color: compact && !waiting ? AppColors.fg4 : color)),
      ),
      if (s.displayAgentId != null && s.displayAgentId!.trim().isNotEmpty) ...[
        const SizedBox(width: 8),
        AgentBadge(agentId: s.displayAgentId!, working: running),
      ],
    ]);
  }

  Widget _sessionCard(SessionInfo s, {bool divider = false}) {
    if (kMobile) return _mobileSessionRow(s, divider: divider);
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final selected = !kMobile && s.id == widget.selectedSessionId;
    // The project, not the generated worktree directory.
    final folderName = s.projectFolder.trim().isEmpty
        ? ''
        : lastPathSegment(s.projectFolder, ifEmpty: s.projectFolder);
    final trailingText =
        folderName.isNotEmpty ? folderName : relativeTime(s.lastActive);
    final card = Material(
      color: _selecting && checked
          ? AppColors.accentBg
          : (selected ? AppColors.surface2 : Colors.transparent),
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
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
          child: AnimatedPadding(
            duration: Motion.quick,
            // While selecting, the tint is a surface: keep the check and the
            // trailing text off its edges.
            padding:
                EdgeInsets.symmetric(horizontal: _selecting ? M.rowPadH : 0),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (_selecting) ...[
                SelectCheck(checked, size: 20),
                const SizedBox(width: S.s12),
              ] else ...[
                // The conversation glyph, tinted by run state (and pulsing while
                // working).
                SessionStateIcon(status: s.status, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: renaming
                    ? _inlineRenameField(s, compact: false)
                    : Text(
                        s.title.isEmpty ? '(untitled)' : s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? M.rowTitle : 13,
                            color: selected ? AppColors.fg1 : AppColors.fg2),
                      ),
              ),
              // No per-row overflow button. At this row height it crowded the
              // title, and its glyph rendered as a dark blob rather than a
              // control. The same actions live on long-press.
              //
              // Who is working in this session, inline. Rendered only when an
              // agent is actually dispatched here, so an ordinary chat keeps the
              // row's original spacing. Tinted by run state, like the desktop
              // sidebar, so an agent merely assigned reads differently from one
              // mid-turn.
              if (s.displayAgentId != null &&
                  s.displayAgentId!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                AgentBadge(
                  agentId: s.displayAgentId!,
                  working: sessionIsActive(s.status),
                ),
              ],
              // The gap is REQUIRED, not cosmetic: the title is `Expanded`, so a
              // long one fills the full width and butts straight against the
              // folder — the two run together with no separation.
              if (!renaming && _hasDraft(s)) ...[
                const SizedBox(width: 10),
                Text('Draft',
                    style:
                        sans(M.meta, weight: W.label, color: AppColors.accent)),
              ] else if (!renaming && trailingText.isNotEmpty) ...[
                const SizedBox(width: 10),
                if (s.inWorktree) ...[
                  Tooltip(
                    message: 'Worktree · ${s.branch ?? s.folder}',
                    child:
                        AppIcon('git-branch', size: 12, color: AppColors.fg3),
                  ),
                  const SizedBox(width: 4),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(trailingText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(M.meta, color: AppColors.fg3)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    // A hairline gap while selecting, so adjacent checked rows read as
    // separate chats rather than one block.
    return AnimatedPadding(
      duration: Motion.quick,
      padding: EdgeInsets.only(bottom: _selecting ? 2 : 0),
      child: card,
    );
  }

  Widget _mobileSessionRow(SessionInfo s, {required bool divider}) {
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final folderName = s.projectFolder.trim().isEmpty
        ? ''
        : lastPathSegment(s.projectFolder, ifEmpty: s.projectFolder);
    final draft = !renaming && _hasDraft(s);
    return Material(
      color: _selecting && checked ? AppColors.accentBg : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
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
                  _sessionActions(s);
                }
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: M.rowHeight + 10),
          padding: EdgeInsets.symmetric(
              horizontal: _selecting ? M.rowPadH : 0, vertical: 12),
          decoration: BoxDecoration(
            border: divider && !_selecting
                ? Border(bottom: BorderSide(color: AppColors.border))
                : null,
          ),
          child: Row(children: [
            if (_selecting) ...[
              SelectCheck(checked, size: 20),
              const SizedBox(width: S.s12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: renaming
                              ? _inlineRenameField(s, compact: false)
                              : Text(s.title.isEmpty ? '(untitled)' : s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TS.rowTitle()),
                        ),
                        const SizedBox(width: 12),
                        Text(draft ? 'Draft' : relativeTime(s.lastActive),
                            style: sans(12,
                                weight: draft ? W.label : W.body,
                                color: draft ? AppColors.accent : AppColors.fg4,
                                tabular: true)),
                      ]),
                  const SizedBox(height: 3),
                  _sessionStatusLine(s, folderName),
                ],
              ),
            ),
          ]),
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
      final selected = await showAppMenu<String>(
        context,
        point: point,
        items: [
          appMenuItem(value: 'rename', icon: 'edit', label: 'Rename'),
          appMenuItem(value: 'select', icon: 'check', label: 'Select'),
          const PopupMenuDivider(height: 9),
          appMenuItem(
              value: 'delete', icon: 'trash', label: 'Delete', danger: true),
        ],
      );
      if (selected == 'select') {
        _enterSelect(seed: s.id);
      } else if (selected == 'rename') {
        _beginRename(s);
      } else if (selected == 'delete') {
        await _confirmDeleteSessions([s]);
      }
      return;
    }
    showAppSheet(context,
        title: s.title.isEmpty ? '(untitled)' : s.title,
        child: SheetActions([
          SheetAction('check', 'Select', () {
            Navigator.pop(context);
            _enterSelect(seed: s.id);
          }),
          SheetAction('edit', 'Rename', () {
            Navigator.pop(context);
            _beginRename(s);
          }),
          SheetAction('trash', 'Delete', () {
            Navigator.pop(context);
            _confirmDeleteSessions([s]);
          }, danger: true),
        ]));
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
              !isInboxSessionRow(s) &&
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
    return TextAction(all ? 'Clear' : 'Select all',
        onTap: _toggleSelectAllVisible);
  }

  Widget _selectionBar({required bool mobile}) {
    final n = _selected.length;
    return Row(children: [
      IconBtn('x',
          size: mobile ? M.minTarget : 28,
          iconSize: mobile ? 18 : 15,
          tooltip: 'Cancel',
          onTap: _exitSelect),
      const SizedBox(width: S.s4),
      Text(n == 0 ? 'Select chats' : '$n selected',
          style: mobile ? TS.sectionTitle() : TS.label(AppColors.fg1)),
      const Spacer(),
      _selectAllToggle(),
      const SizedBox(width: S.s4),
      Btn(n == 0 ? 'Delete' : 'Delete $n',
          small: true,
          icon: 'trash',
          variant: BtnVariant.danger,
          disabled: n == 0,
          onTap: _confirmDeleteSelected),
    ]);
  }

  /// Phone selection's action bar, pinned under the list where the thumb is.
  Widget _mobileSelectionActions() {
    final n = _selected.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(M.gutter, S.s12, M.gutter, S.s12),
      child: Btn(n == 0 ? 'Delete' : 'Delete $n',
          full: true,
          icon: 'trash',
          variant: BtnVariant.danger,
          disabled: n == 0,
          onTap: _confirmDeleteSelected),
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
    return InlineEditField(
      controller: _renameCtl,
      focusNode: _renameFocus,
      dense: compact,
      hint: 'Chat title',
      onSubmit: () => _commitRename(s),
      onCancel: () => setState(() => _renamingId = null),
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
    if (!ok || !mounted) return;
    final ids = [for (final s in sessions) s.id];
    setState(() => _deleting.addAll(ids));
    _exitSelect();
    final failed = <String>[];
    Object? lastError;
    await Future.wait(ids.map((id) => c.deleteSession(id).then(
          (_) => widget.onSessionDeleted(id),
          onError: (Object e) {
            failed.add(id);
            lastError = e;
          },
        )));
    if (!mounted) return;
    setState(() => _deleting.removeAll(failed));
    if (failed.isNotEmpty) {
      toast(context,
          "Couldn't delete ${failed.length == 1 ? 'a session' : '${failed.length} sessions'}: $lastError",
          danger: true);
    }
    widget.onRefreshSessions();
  }

  // ---- machines ----

  /// Machine list: bottom sheet on phones, a popover anchored to the block on
  /// desktop. Same rows + "Add machine" footer either way.
  Future<void> _openMachines() => showSidebarMachinesPicker(
        context,
        anchorKey: _machineKey,
        instances: widget.instances,
        active: widget.active,
        health: widget.health,
        onSelect: widget.onSelectInstance,
        onAdd: widget.onAddInstance,
        onManage: _machineActions,
        onRefreshHealth: widget.onRefreshHealth,
      );

  void _machineActions(Instance i) => showManageMachineSheet(
        context: context,
        instance: i,
        onRename: (inst, name) => widget.onRenameInstance(inst, name),
        onRemove: (inst) => widget.onRemoveInstance(inst),
      );
}
