import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agents_sidebar_panel.dart';
import 'mission_control.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'settings_panel.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_nav.dart';

class SidebarEmpty extends StatelessWidget {
  const SidebarEmpty(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Text(message,
            textAlign: TextAlign.center,
            style: sans(12, color: AppColors.fg3, height: 1.45)),
      );
}

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
  // The session list now lives in the shell (passed via widget.sessions); the
  // sidebar is presentational, so opening the drawer doesn't refetch.
  String _filterQuery = '';
  String _agentFilterQuery = '';
  final _machineKey = GlobalKey(); // anchors the desktop machine popover
  final GlobalKey<SettingsPanelState> _mobileSettingsKey =
      GlobalKey<SettingsPanelState>();
  final GlobalKey<AgentsSidebarPanelState> _agentsPanelKey =
      GlobalKey<AgentsSidebarPanelState>();
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Phone search. The bar's search action flips this and the pill expands into a
  /// full-width field, so searching never costs permanent vertical space.
  bool _mobileSearchOpen = false;
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

  MobileHome _lastMainHome = MobileHome.agents;
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
      if (_targetPage != widget.mobileHome.index && _pageController.hasClients) {
        final current =
            _pageController.page?.round() ?? _pageController.initialPage;
        if (current != widget.mobileHome.index) {
          _goToPage(widget.mobileHome.index);
        }
      }
    }
  }



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



  List<SessionInfo>? get _sessions => widget.sessions;
  bool get _loading => widget.sessionsLoading;




  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final hasClient = widget.client != null;
    return Container(
      color: AppColors.bg, // shell surface — darker than the chat canvas
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
            child: PageView(
              controller: _pageController,
              physics: (_mobileDrilledDown || _mobileSearchOpen)
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
                  _KeepAlivePage(
                    key: ValueKey('mobile-${h.name}'),
                    child: _mobileHomeBody(hasClient, h),
                  ),
              ],
            ),
          ),
          // The bar names the app's TOP LEVEL, so it hides inside a nested
          // screen. Leaving it up would give that screen a second exit that
          // skips the level you are in — and make the bar look like part of the
          // sub-screen rather than the shell.
          if (!_mobileDrilledDown && widget.mobileHome != MobileHome.settings)
            _mobileBar(hasClient),
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
              child: Row(children: [
                Text('${_selected.length} selected',
                    style: sans(11, color: AppColors.fg3)),
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


  /// Full-surface placeholder for a phone destination with no machine.
  ///
  /// Local to the sidebar rather than reusing the shell's `_sidebarUnavailable`:
  /// that one is a `_DesktopShellState` method and is not in scope here.
  Widget _mobileUnavailable(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: sans(12, color: AppColors.fg3, height: 1.5)),
        ),
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
            Expanded(
              child: !hasClient
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Add a machine to begin.',
                              textAlign: TextAlign.center,
                              style: sans(12, color: AppColors.fg3))))
                  : _sessionList(),
            ),
          ],
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
                        onOpenSession: (id, title) =>
                            widget.onOpenSession(id, title, null),
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
      return Padding(
        padding: EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 8),
        child: Row(children: [
          Text('${_selected.length} selected',
              style:
                  sans(M.sectionTitle, weight: W.label, color: AppColors.fg1)),
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
        ]),
      );
    }
    final mc = (_sessions ?? const <SessionInfo>[])
        .where((s) => isDedicatedMcSession(s.id))
        .toList();
    final mcActive = mc.isNotEmpty && mc.first.id == widget.selectedSessionId;
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Chats',
            style: sans(M.pageTitle, weight: W.label, color: AppColors.fg1)),
        const Spacer(),
        if (hasClient && mc.isNotEmpty)
          IconBtn('layers',
              size: M.minTarget,
              iconSize: 19,
              active: mcActive,
              tooltip: 'Mission Control',
              onTap: widget.onOpenMissionControl),
        _machineAvatarButton(),
      ]),
    );
  }

  Widget _mobileAgentsHeader(bool hasClient) {
    final mc = (_sessions ?? const <SessionInfo>[])
        .where((s) => isDedicatedMcSession(s.id))
        .toList();
    final mcActive = mc.isNotEmpty && mc.first.id == widget.selectedSessionId;
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Agents',
            style: sans(M.pageTitle, weight: W.label, color: AppColors.fg1)),
        const Spacer(),
        if (hasClient && mc.isNotEmpty)
          IconBtn('layers',
              size: M.minTarget,
              iconSize: 19,
              active: mcActive,
              tooltip: 'Mission Control',
              onTap: widget.onOpenMissionControl),
        _machineAvatarButton(),
      ]),
    );
  }

  Widget _mobileSettingsHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Settings',
            style: sans(M.pageTitle, weight: W.label, color: AppColors.fg1)),
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
                      border: Border.all(color: AppColors.border2),
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

  /// The floating action bar: destinations left, quick actions right.
  ///
  /// Destinations are the phone's translation of the desktop sidebar rail — on
  /// a phone those five panels had NO entry point at all, which is the real
  /// reason this exists (the reclaimed vertical space is a side effect).
  ///
  /// Rendered as a sibling of the body by the caller, never an overlay, so it
  /// cannot hide the last row of a list.
  /// The floating action bar.
  ///
  /// Deliberately COMPACT: icon-only destinations in a pill that hugs its
  /// content and centres, rather than a full-width strip. The bar is an
  /// affordance you reach occasionally, so it should not reserve a third of the
  /// screen's width for three glyphs.
  ///
  /// Tapping search expands the SAME pill into a full-width field — the control
  /// grows in place instead of a second search surface appearing.
  ///
  /// Rendered as a sibling of the body by the caller, never an overlay, so it
  /// cannot hide the last row of a list.
  Widget _mobileBar(bool hasClient) {
    final radius = BorderRadius.circular(kMobileBarRadius);
    final searching = _mobileSearchOpen && hasClient;
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 6, M.gutter, 8),
      child: AnimatedSwitcher(
        duration: Motion.fast,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        child: searching
            ? _mobileBarPill(radius, key: 'search', child: _mobileSearchRow())
            : _mobileBarPill(radius,
                key: 'bar', child: _mobileBarRow(hasClient)),
      ),
    );
  }

  Widget _mobileBarPill(BorderRadius radius,
      {required String key, required Widget child}) {
    return Container(
      key: ValueKey(key),
      height: kMobileBarHeight,
      // Shadow on the OUTER container; fill, border and rounded clip on the
      // inner Material. An InkWell paints its ripple onto the nearest Material
      // ancestor — with none local it splashes onto the Scaffold and bleeds
      // outside the pill's corners.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppColors.border2),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _mobileBarRow(bool hasClient) {
    return Row(
      children: [
        const SizedBox(width: 4),
        for (final h in MobileHome.values)
          Expanded(
            child: _mobileBarDest(h, widget.mobileHome == h, true),
          ),
        const SizedBox(width: 2),
        // Divider separates "where you are" from "what you can do".
        Container(width: 1, height: 20, color: AppColors.border),
        const SizedBox(width: 2),
        Expanded(
          child: _mobileBarAction('search', 'Search',
              onTap: hasClient ? _toggleMobileSearch : null),
        ),
        Expanded(
          child: _mobileBarAction('plus', 'New',
              onTap: hasClient ? _handleMobileNew : null),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _handleMobileNew() {
    if (widget.mobileHome == MobileHome.agents) {
      _openCreateAgent();
    } else if (widget.mobileHome == MobileHome.chats) {
      widget.onNewSession();
    } else {
      widget.onMobileHome(MobileHome.chats);
      widget.onNewSession();
    }
  }

  /// The expanded search field. Occupies the whole pill, so the destinations and
  /// the create action yield to it rather than competing with it.
  Widget _mobileSearchRow() {
    final isAgents = widget.mobileHome == MobileHome.agents;
    final ctl = isAgents ? _agentSearchCtl : _searchCtl;
    final focus = isAgents ? _agentSearchFocus : _searchFocus;
    final query = isAgents ? _agentFilterQuery : _filterQuery;
    final hint = isAgents ? 'Search agents' : 'Search chats';

    return Row(children: [
      const SizedBox(width: 12),
      AppIcon('search', size: 16, color: AppColors.fg3),
      const SizedBox(width: 9),
      Expanded(
        child: TextField(
          controller: ctl,
          focusNode: focus,
          autofocus: true,
          cursorColor: AppColors.accent,
          textInputAction: TextInputAction.search,
          onChanged: (v) {
            setState(() {
              if (isAgents) {
                _agentFilterQuery = v;
              } else {
                _filterQuery = v;
              }
            });
          },
          style: sans(15, color: AppColors.fg1),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: sans(15, color: AppColors.fg4),
          ),
        ),
      ),
      if (query.isNotEmpty)
        IconBtn('x', size: 32, iconSize: 14, tooltip: 'Clear', onTap: () {
          ctl.clear();
          setState(() {
            if (isAgents) {
              _agentFilterQuery = '';
            } else {
              _filterQuery = '';
            }
          });
        }),
      IconBtn('arrow-down',
          size: 36,
          iconSize: 16,
          tooltip: 'Close search',
          onTap: _toggleMobileSearch),
      const SizedBox(width: 4),
    ]);
  }

  void _toggleMobileSearch() {
    final open = !_mobileSearchOpen;
    FocusManager.instance.primaryFocus?.unfocus();
    if (open && widget.mobileHome == MobileHome.settings) {
      widget.onMobileHome(MobileHome.chats);
    }
    setState(() {
      _mobileSearchOpen = open;
      if (!open) {
        _searchCtl.clear();
        _filterQuery = '';
        _agentSearchCtl.clear();
        _agentFilterQuery = '';
      }
    });
    if (open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.mobileHome == MobileHome.agents) {
          _agentSearchFocus.requestFocus();
        } else {
          _searchFocus.requestFocus();
        }
      });
    }
  }

  Widget _mobileBarDest(MobileHome h, bool active, bool enabled) {
    return Tooltip(
      message: h.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobileBarRadius - 4),
          onTap: enabled
              ? () {
                  if (widget.mobileHome != h) {
                    _goToPage(h.index);
                    widget.onMobileHome(h);
                  }
                }
              : null,
          child: SizedBox(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(h.icon,
                      size: 23, color: active ? AppColors.fg1 : AppColors.fg3),
                  const SizedBox(height: 2),
                  Text(h.label,
                      style: caps(10,
                          color: active ? AppColors.fg1 : AppColors.fg3,
                          spacing: 0.35)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileBarAction(String icon, String tooltip, {VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobileBarRadius - 4),
          onTap: onTap,
          child: SizedBox(
            height: kMobileBarHeight,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(icon,
                      size: 23,
                      color: onTap == null ? AppColors.fg4 : AppColors.fg2),
                  const SizedBox(height: 2),
                  Text(tooltip,
                      style: caps(10,
                          color: onTap == null ? AppColors.fg4 : AppColors.fg2,
                          spacing: 0.35)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
                        style: sans(12, color: AppColors.fg3)),
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
                    textAlign: TextAlign.center,
                    style: sans(12, color: AppColors.fg3))),
          ]);
    }
    final mc = all.where((s) => isDedicatedMcSession(s.id)).toList();
    final list = all
        .where((s) =>
            !isDedicatedMcSession(s.id) &&
            !isInboxSessionRow(s) &&
            _matchesQuery(s))
        .toList();
    // Phone chats are one flat, chronological surface. Folder nesting is a
    // desktop density aid; on a touch screen it obscures the one thing people
    // came here to do: open the recent conversation.
    if (kMobile) {
      final cutoff =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 12 * 60 * 60;
      final recent = list.where((s) => s.lastActive >= cutoff).toList()
        ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
      final recentIds = recent.take(10).map((s) => s.id).toSet();
      final mobileChildren = <Widget>[];
      if (recentIds.isNotEmpty) {
        mobileChildren
            .add(_mobileListHeader('Recent', first: true));
        mobileChildren.addAll(recent
            .where((s) => recentIds.contains(s.id))
            .map(_sessionCard));
      }
      if (list.isNotEmpty) {
        final grouped = <String, List<SessionInfo>>{};
        final order = <String>[];
        final allSorted = [...list]
          ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
        for (final session in allSorted) {
          grouped.putIfAbsent(session.folder, () {
            order.add(session.folder);
            return <SessionInfo>[];
          }).add(session);
        }
        if (recentIds.isNotEmpty) {
          mobileChildren.add(const SizedBox(height: 8));
        }
        for (final folder in order) {
          final sessions = grouped[folder]!;
          mobileChildren.add(_folderHeader(folder,
              first: mobileChildren.isEmpty, count: sessions.length));
          final showSessions =
              _filterQuery.trim().isNotEmpty || !_collapsed.contains(folder);
          if (showSessions) {
            mobileChildren.addAll(sessions.map(_sessionCard));
          }
        }
      }
      if (mobileChildren.isEmpty) {
        mobileChildren.add(Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
              _filterQuery.trim().isNotEmpty
                  ? 'No chats match the search.'
                  : 'No chats yet.',
              textAlign: TextAlign.center,
              style: sans(12, color: AppColors.fg3)),
        ));
      }
      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: () async => widget.onRefreshSessions(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 28),
          children: mobileChildren,
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
    if (list.isEmpty && mc.isEmpty) {
      children.add(Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Nothing here.',
              textAlign: TextAlign.center,
              style: sans(12, color: AppColors.fg3))));
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
            !isInboxSessionRow(s) &&
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
          onToggle: () => setState(() => _toggleCollapsed(_chatsKey)),
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
        if (chatsOpen && _desktopChatsSearchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.xs),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  AppIcon('search', size: 13, color: AppColors.fg3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _desktopChatsSearchCtl,
                      focusNode: _desktopChatsSearchFocus,
                      onChanged: (v) => setState(() => _filterQuery = v),
                      style: sans(12, color: AppColors.fg1),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search chats…',
                        hintStyle: sans(12, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  if (_desktopChatsSearchCtl.text.isNotEmpty)
                    IconBtn('x', size: 20, iconSize: 10, tooltip: 'Clear', onTap: () {
                      _desktopChatsSearchCtl.clear();
                      setState(() => _filterQuery = '');
                    }),
                ],
              ),
            ),
          ),
        if (!chatsOpen)
          const SizedBox.shrink()
        else if (!hasClient)
          const SidebarEmpty('Add a machine to begin.')
        else if (list.isEmpty)
          // Distinguish "no conversations" from "none match the search": saying
          // "No chats yet" over a searched list reads as data loss.
          SidebarEmpty(_filterQuery.trim().isNotEmpty
              ? 'No chats match the search.'
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
    return ShellNavRow(
      id: s.id,
      label: s.title.trim().isEmpty ? '(untitled)' : s.title,
      icon: 'chat-thread',
      tone: ShellTone.chat,
      selected: selected,
      onTap: () => widget.onOpenSession(s.id, s.title, s.profile),
      // The icon now carries run state, so the trailing dot would be a second
      // indicator for one fact. Colour is the state channel — see
      // `sessionStateColor`: amber busy, accent needs-you, neutral idle.
      leading: SessionStateIcon(status: s.status, size: kNavIcon),
      // Who is working here, inline. Same treatment as the phone card: an agent
      // working in this chat is shown on the row itself, so "which session is an
      // agent working in" is answerable from the list without opening anything.
      // `working` tints it by run state, so a chat an agent merely owns reads
      // differently from one it is mid-turn in.
      trailing: s.displayAgentId == null || s.displayAgentId!.trim().isEmpty
          ? null
          : AgentBadge(
              agentId: s.displayAgentId!,
              working: sessionIsActive(s.status),
            ),
    );
  }


  Widget _mobileListHeader(String label, {int? count, bool first = false}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(0, first ? 6 : 18, 0, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: display(M.sectionTitle, color: AppColors.fg1)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text('$count', style: mono(M.meta, color: AppColors.fg3)),
            ],
          ],
        ),
      );

  Widget _folderHeader(String folder, {required bool first, int count = 0}) {
    final name =
        folder.isEmpty ? 'No folder' : lastPathSegment(folder, ifEmpty: folder);
    final isSearching = _filterQuery.trim().isNotEmpty;
    final collapsed = isSearching ? false : _collapsed.contains(folder);
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
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(top: first ? 2 : 16),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    flex: 7,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        AppIcon(chevron, size: 14, color: AppColors.fg4),
                        const SizedBox(width: 4),
                        AppIcon('folder', size: 16, color: AppColors.fg4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12, weight: W.label, color: AppColors.fg3)),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(height: 1, color: AppColors.border),
                        ),
                        if (collapsed && count > 0) ...[
                          const SizedBox(width: 8),
                          Text('$count', style: sans(11, tabular: true, color: AppColors.fg3)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
                  style: sans(11, weight: W.title, color: AppColors.fg3)),
            ),
            if (collapsed && count > 0)
              Text('$count', style: sans(10, tabular: true, color: AppColors.fg3)),
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
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              AppIcon('layers',
                  size: 14,
                  color: selected ? AppColors.fg1 : AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mission Control',
                    style: sans(12,
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
              ] else ...[
                // Always present, so titles share one left edge; the colour is
                // what carries state.
                SessionStateIcon(status: s.status, size: 14),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: renaming
                      ? _inlineRenameField(s, compact: true)
                      : Text(s.title.isEmpty ? '(untitled)' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12,
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


  Widget _sessionCard(SessionInfo s) {
    final checked = _selected.contains(s.id);
    final renaming = _renamingId == s.id;
    final selected = !kMobile && s.id == widget.selectedSessionId;
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
            padding: const EdgeInsets.only(left: 18, right: 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (_selecting) ...[
                AppIcon(checked ? 'check' : 'plus',
                    size: 16,
                    color: checked ? AppColors.accent : AppColors.fg4),
                const SizedBox(width: 8),
              ] else ...[
                // The conversation glyph, tinted by run state (and pulsing while
                // working). Always present so every row's title aligns with the folder above.
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
                        style: sans(M.rowTitle,
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
              // time — the two run together with no separation.
              if (!renaming) ...[
                const SizedBox(width: 10),
                Text(relativeTime(s.lastActive),
                    style: sans(M.meta, tabular: true, color: AppColors.fg3)),
              ],
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
      final selected = await showAppMenu<String>(
        context,
        point: point,
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
    return Pressable(
      child: Material(
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
              Text(label, style: sans(13, color: color)),
            ]),
          ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(R.sm),
      onTap: _toggleSelectAllVisible,
      child: SizedBox(
        height: kMobile ? M.minTarget : 26,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(all ? 'Unselect all' : 'Select all',
                style: sans(kMobile ? M.rowTitle : 11,
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
      style: sans(compact ? 12 : 16, color: AppColors.fg1),
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

  /// Machine list: bottom sheet on phones, a popover anchored to the block on
  /// desktop. Same rows + "Add machine" footer either way.
  Future<void> _openMachines() async {
    widget.onRefreshHealth();
    final content = MachineList(
      instances: widget.instances,
      active: widget.active,
      health: widget.health,
      onSelect: widget.onSelectInstance,
      onAdd: widget.onAddInstance,
      onManage: _machineActions,
    );
    if (kMobile) {
      await showAppSheet(
        context,
        title: 'Machines',
        child: content,
      );
      return;
    }
    final box = _machineKey.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true, // click-away and Esc dismiss
      barrierLabel: 'machines',
      barrierColor: Colors.transparent,
      transitionDuration: Motion.press,
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
            CurvedAnimation(parent: anim, curve: Motion.enter);
        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 5.0 * curved.value, sigmaY: 5.0 * curved.value),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  // Overflow / long-press on a machine row → rename or remove (existing flows).
  void _machineActions(Instance i) => showManageMachineSheet(
        context: context,
        instance: i,
        onRename: (inst, name) => widget.onRenameInstance(inst, name),
        onRemove: (inst) => widget.onRemoveInstance(inst),
      );
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({super.key, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

