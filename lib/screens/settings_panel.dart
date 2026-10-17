import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart';
import 'inference_profiles.dart';
import 'recurring.dart';
import 'routing_screen.dart';
import 'shell_nav.dart';
import 'usage.dart';
import 'vault.dart';
import '../motion.dart';
import 'memory_screen.dart';

/// Rows for the machine popover/sheet: live dot (re-pinged on open), label,
/// host, trailing overflow. Pops itself before invoking any callback.
class MachineList extends StatefulWidget {
  final List<Instance> instances;
  final Instance? active;
  final Map<String, bool> health;
  final void Function(Instance) onSelect;
  final VoidCallback onAdd;
  final void Function(Instance) onManage;

  const MachineList({
    super.key,
    required this.instances,
    required this.active,
    required this.health,
    required this.onSelect,
    required this.onAdd,
    required this.onManage,
  });

  @override
  State<MachineList> createState() => _MachineListState();
}

class _MachineListState extends State<MachineList> {
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
    if (kMobile) {
      return ListGroup(children: [...widget.instances.map(_row), _addRow()]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.instances.map(_row),
        Divider(height: 13, thickness: 1, color: AppColors.border),
        _addRow(),
      ],
    );
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
        padding: EdgeInsets.fromLTRB(
            S.s12, kMobile ? S.s8 : S.s6, S.s2, kMobile ? S.s8 : S.s6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ok == true ? AppColors.ok : AppColors.fg4,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kMobile
                      ? TS.rowTitle(AppColors.fg1)
                      : TS.ui(AppColors.fg1)),
              const SizedBox(height: S.s2),
              Text(hostOf(i.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.codeSmall(AppColors.fg3)),
            ]),
          ),
          if (selected) AppIcon('check', size: 16, color: AppColors.accent),
          IconBtn('more-vertical', size: 32, iconSize: 16, tooltip: 'Manage',
              onTap: () {
            Navigator.pop(context);
            widget.onManage(i);
          }),
        ]),
      ),
    );
  }

  Widget _addRow() {
    return Pressable(
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          widget.onAdd();
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              S.s12, kMobile ? 14 : 8, S.s12, kMobile ? 14 : 8),
          child: Row(children: [
            SizedBox(
              width: kMobile ? 8 : 16,
              height: 16,
              child: OverflowBox(
                maxWidth: 16,
                maxHeight: 16,
                child: AppIcon('plus', size: 16, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 10),
            Text('Add machine', style: TS.label(AppColors.accent)),
          ]),
        ),
      ),
    );
  }
}

enum SettingsPage { general, models, routing, memory, usage, vault, scheduled }

/// Settings dialog: Zed-style sidebar + content pane. Models / vault /
/// scheduled swap in-place so they never stack a second dialog.
class SettingsPanel extends StatefulWidget {
  final DaemonClient client;
  final List<Instance> instances;
  final Instance? active;
  final void Function(Instance) onRemove;
  final void Function(Instance, String)? onRename;
  final void Function(Instance)? onSelect;
  final void Function(Instance)? onAdd;
  final VoidCallback onClose;

  /// True when hosted INSIDE the phone home under the floating bar, rather than
  /// presented as its own dialog/drawer.
  final bool embedded;

  final bool fullPage;

  /// Phone drill-down. Null shows the section list; a value shows that section.
  ///
  /// Owned by the SHELL, not by this widget: the back handler and the bar's
  /// visibility both need to read it, and neither can see inside here.
  final SettingsPage? section;
  final ValueChanged<SettingsPage?>? onSection;

  final SettingsPage? createOnOpen;
  final VoidCallback? onCreateHandled;
  final SettingsPage? initialPage;

  const SettingsPanel({
    super.key,
    required this.client,
    required this.instances,
    required this.active,
    required this.onRemove,
    this.onRename,
    this.onSelect,
    this.onAdd,
    required this.onClose,
    this.embedded = false,
    this.fullPage = false,
    this.section,
    this.onSection,
    this.createOnOpen,
    this.onCreateHandled,
    this.initialPage,
  });

  @override
  State<SettingsPanel> createState() => SettingsPanelState();
}

class SettingsPanelState extends State<SettingsPanel> {
  late final List<Instance> _instances = [...widget.instances];
  bool _notif = false;
  bool _notifBusy = false;
  final GlobalKey<VaultScreenState> _vaultKey = GlobalKey<VaultScreenState>();
  final GlobalKey<InferenceProfilesScreenState> _modelsKey =
      GlobalKey<InferenceProfilesScreenState>();
  final GlobalKey<RecurringScreenState> _recurringKey =
      GlobalKey<RecurringScreenState>();

  bool _addingMachine = false;
  final TextEditingController _addMachinePaste = TextEditingController();
  bool _addMachineBusy = false;
  String? _addMachineError;

  bool _modelsEditing = false;
  bool _recurringAdding = false;

  bool get _isNested => switch (_page) {
        SettingsPage.general => _addingMachine,
        SettingsPage.models => _modelsEditing,
        _ => false,
      };

  String? _renamingUrl;
  final TextEditingController _renameController = TextEditingController();

  late SettingsPage _page = widget.initialPage ?? SettingsPage.general;

  /// Phone drill-down, read from the shell. Desktop uses `_page` + the chip
  /// strip instead, so this is only consulted when `kMobile && embedded`.
  SettingsPage? get _mobileSection => widget.section;

  /// True when the last move through Settings went deeper, rather than back out
  /// of a section. Sets the slide direction between sections the same way the
  /// shell does between destinations. Captured from the PREVIOUS widget in
  /// `didUpdateWidget`, because that value is gone by the time `build` runs.
  bool _sectionForward = true;

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.section?.index ?? -1;
    final after = widget.section?.index ?? -1;
    if (before != after) _sectionForward = after > before;
    if (widget.createOnOpen != oldWidget.createOnOpen) _scheduleCreate();
  }

  void _scheduleCreate() {
    final page = widget.createOnOpen;
    if (page == null) return;
    Future.delayed(Motion.base, () {
      if (!mounted || widget.createOnOpen != page) return;
      widget.onCreateHandled?.call();
      switch (page) {
        case SettingsPage.general:
          _addMachine();
        case SettingsPage.models:
          _modelsKey.currentState?.addProfile();
        case SettingsPage.vault:
          _vaultKey.currentState?.add();
        case SettingsPage.scheduled:
          _recurringKey.currentState?.add();
        case SettingsPage.usage:
        case SettingsPage.memory:
        case SettingsPage.routing:
          break;
      }
    });
  }

  static const _nav = [
    (SettingsPage.general, 'server', 'General'),
    (SettingsPage.models, 'sparkles', 'Profiles'),
    (SettingsPage.routing, 'route', 'Routing'),
    (SettingsPage.usage, 'gauge', 'Usage'),
    (SettingsPage.memory, 'book-marked', 'Memory'),
    (SettingsPage.scheduled, 'calendar-clock', 'Scheduled'),
    (SettingsPage.vault, 'lock', 'Vault'),
  ];

  static const _navGroups = {
    SettingsPage.general: 'Work',
    SettingsPage.memory: 'Agents',
  };

  @override
  void initState() {
    super.initState();
    _addMachinePaste.addListener(() => setState(() {}));
    notificationsEnabled().then((v) {
      if (mounted) setState(() => _notif = v);
    });
    _scheduleCreate();
  }

  @override
  void dispose() {
    _addMachinePaste.dispose();
    _renameController.dispose();
    super.dispose();
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
    // Phone + embedded in the home: open INLINE, not behind a drill-down.
    final drill = kMobile && widget.embedded;
    if (drill) {
      return Material(
        // Same surface as the other phone destinations (chats, agents). This was
        // `surface1`, one step lighter, which made Settings read as a different
        // app the moment you tapped into it.
        color: AppColors.bg,
        child: CardGroupScope(
         child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: Motion.base,
            reverseDuration: Motion.fast,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            // `StackFit.expand`, not the default centered `Stack`: these are
            // full-body screens, and loose constraints would let each one
            // shrink-wrap into the middle of the transition.
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, anim) {
              final dx = _sectionForward ? 0.06 : -0.06;
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                          .animate(anim),
                  child: child,
                ),
              );
            },
            // Keyed so entering a section and leaving it are two different
            // children — the switcher only animates a genuine change of screen.
            child: KeyedSubtree(
              key: ValueKey(_mobileSection?.name ?? 'home'),
              child: _mobileSection == null
                  ? _mobileSettingsHome()
                  : _mobileSectionPage(),
            ),
          ),
         ),
        ),
      );
    }
    final full = widget.fullPage;
    final scaffold = Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 560) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column (Sidebar Rail)
                Container(
                  width: full ? 272 : 210,
                  decoration: BoxDecoration(
                    color: AppColors.sidebarPanel,
                    border: full
                        ? Border(right: BorderSide(color: AppColors.line))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (full) ...[
                        SizedBox(height: kMacOS ? kTitleBarHeight + 4 : 12),
                        _backToApp(),
                        const SizedBox(height: 4),
                      ] else
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.centerLeft,
                        child: Text('Settings',
                            style: sans(15, color: AppColors.fg1)),
                      ),
                      // Nav Items
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          children: [
                            for (final (page, icon, label) in _nav) ...[
                              if (_navGroups[page] != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      10, 14, 10, 4),
                                  child: Text(_navGroups[page]!.toUpperCase(),
                                      style: sans(11,
                                          spacing: 0.9,
                                          color: AppColors.fg4)),
                                ),
                              _settingsNavRow(page, icon, label),
                            ],
                          ],
                        ),
                      ),
                      // Machine Status in Sidebar Footer
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: AppColors.ok,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.active?.label.isNotEmpty == true
                                  ? widget.active!.label
                                  : 'Connected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TS.caption(),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
                // Right Column (Content Pane)
                Expanded(
                  child: Container(
                    color: AppColors.bg,
                    padding: full
                        ? EdgeInsets.only(top: kMacOS ? kTitleBarHeight : 16)
                        : EdgeInsets.zero,
                    child: LayoutBuilder(
                      builder: (context, paneConstraints) {
                        final extra = full
                            ? ((paneConstraints.maxWidth - 768) / 2)
                                .clamp(0.0, double.infinity)
                            : 0.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_isNested)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                    24 + extra,
                                    full ? 14 : 12,
                                    (full ? 24 : 10) + extra,
                                    2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: SwapText(
                                        _pageTitle(_page),
                                        style: full
                                            ? sans(17,
                                                weight: FontWeight.w500,
                                                spacing: -0.2,
                                                color: AppColors.fg1)
                                            : sans(15, color: AppColors.fg1),
                                      ),
                                    ),
                                    if (_pageAction(_page) != null)
                                      _pageAction(_page)!,
                                    if (!full) ...[
                                      const SizedBox(width: 6),
                                      IconBtn('x',
                                          size: 28,
                                          iconSize: 14,
                                          tooltip: 'Close',
                                          onTap: widget.onClose),
                                    ],
                                  ],
                                ),
                              ),
                            Expanded(
                              child: Swap(
                                stateKey: _page,
                                fill: true,
                                child: _pageBody(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          }
          // Narrow viewport fallback:
          return Column(children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                AppIcon('settings', size: 15, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Settings', style: TS.label(AppColors.fg1)),
                const Spacer(),
                IconBtn('x',
                    size: 26,
                    iconSize: 13,
                    tooltip: 'Close',
                    onTap: widget.onClose),
              ]),
            ),
            SizedBox(height: 44, child: _navChips()),
            Divider(height: 1, color: AppColors.border),
            Expanded(child: _pageBody()),
          ]);
        }),
      ),
    );
    if (!full) return scaffold;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Widget _backToApp() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: widget.onClose,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                AppIcon('chevron-left', size: 15, color: AppColors.fg3),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Back to app',
                        style: sans(13.5, color: AppColors.fg2))),
              ]),
            ),
          ),
        ),
      );

  /// Phone settings HOME.
  Widget _mobileSettingsHome() {
    final active = widget.active;
    Widget nav(SettingsPage page, String label,
            [String summary = '', String? icon]) =>
        ListRow(
          title: label,
          leading: icon == null
              ? null
              : AppIcon(icon, size: 19, color: AppColors.fg3),
          onTap: () => widget.onSection?.call(page),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (summary.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg3)),
              ),
            const SizedBox(width: S.s6),
            AppIcon('chevron-right', size: 15, color: AppColors.fg4),
          ]),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 7),
          child: Text(text.toUpperCase(),
              style: sans(12, weight: W.label, spacing: 0.7, color: AppColors.fg4)),
        );
    final name = active?.label.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.s4, 4, 0, 4),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'No machine yet' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(17,
                          weight: W.strong,
                          height: 22 / 17,
                          color: AppColors.fg1)),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (active != null) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: AppColors.ok, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                          active == null
                              ? 'Add one to begin'
                              : 'Connected · ${hostOf(active.url)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Btn(_instances.length > 1 ? 'Switch' : 'Manage',
                small: true,
                variant: BtnVariant.secondary,
                onTap: () => widget.onSection?.call(SettingsPage.general)),
          ]),
        ),
        label('Models'),
        ListGroup(children: [
          nav(SettingsPage.models, 'Profiles', 'Models and keys', 'sparkles'),
          nav(SettingsPage.routing, 'Routing', 'Fallback models', 'route'),
          nav(SettingsPage.usage, 'Usage', 'Tokens and spend', 'gauge'),
        ]),
        label('Work'),
        ListGroup(children: [
          nav(SettingsPage.memory, 'Memory', 'What agents remember', 'book-marked'),
          ApprovalsRow(client: widget.client),
          nav(SettingsPage.vault, 'Vault', 'Secrets for agents', 'lock'),
          nav(SettingsPage.scheduled, 'Scheduled', 'Recurring jobs', 'calendar-clock'),
        ]),
        if (kCanNotify) ...[
          label('Phone'),
          ListGroup(children: [_notifRow()]),
        ],
      ],
    );
  }

  /// One phone settings section.
  Widget _mobileSectionPage() {
    final section = _mobileSection!;
    void back() => widget.onSection?.call(null);
    return switch (section) {
      SettingsPage.general => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NavBackRow(title: 'Machines', onBack: back, trailing: [
              HeaderAction('Add machine', onTap: _addMachine),
            ]),
            Expanded(child: _generalPage(includeNotifications: false)),
          ],
        ),
      SettingsPage.models => InferenceProfilesScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.routing => RoutingScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.memory => MemoryScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.usage => UsageScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.vault => VaultScreen(
          client: widget.client,
          embedded: true,
          onBack: back,
        ),
      SettingsPage.scheduled => RecurringScreen(
          client: widget.client,
          listOnly: true,
          embedded: true,
          onBack: back,
        ),
    };
  }

  void _addMachine() {
    if (kMobile && widget.embedded) {
      showModal<Instance>(
        context,
        const AddInstanceScreen(),
      ).then((inst) {
        if (inst != null && mounted) {
          setState(() {
            _instances.removeWhere((e) => e.url == inst.url);
            _instances.add(inst);
          });
          InstanceStore().save(_instances);
          widget.onAdd?.call(inst);
        }
      });
      return;
    }
    setState(() {
      _addingMachine = true;
      _addMachineError = null;
      _addMachinePaste.clear();
    });
  }

  Future<void> _submitAddMachine() async {
    final raw = _addMachinePaste.text.trim();
    if (raw.isEmpty || _addMachineBusy) return;
    setState(() {
      _addMachineBusy = true;
      _addMachineError = null;
    });
    try {
      final parsed = parseConnection(raw);
      if (parsed == null) {
        throw 'That is not a valid link. Run "snippet serve" on the other machine and paste what it prints.';
      }
      final (url, token) = parsed;
      final cfg = await DaemonClient(url, token).getConfig();
      final name = cfg.hostname.isNotEmpty ? cfg.hostname : hostOf(url);
      final inst = Instance(name: name, url: url, token: token);
      if (!mounted) return;
      setState(() {
        _addMachineBusy = false;
        _instances.removeWhere((e) => e.url == inst.url);
        _instances.add(inst);
        _addingMachine = false;
        _addMachinePaste.clear();
      });
      await InstanceStore().save(_instances);
      widget.onAdd?.call(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _addMachineBusy = false;
          _addMachineError = 'Connection failed: $e';
        });
      }
    }
  }

  void _startRename(Instance i) {
    setState(() {
      _renamingUrl = i.url;
      _renameController.text = i.label;
    });
  }

  Future<void> _commitRename(Instance inst) async {
    final newName = _renameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _renamingUrl = null);
      return;
    }
    setState(() {
      final idx = _instances.indexWhere((e) => e.url == inst.url);
      if (idx >= 0) {
        _instances[idx] =
            Instance(name: newName, url: inst.url, token: inst.token);
      }
      _renamingUrl = null;
    });
    await InstanceStore().save(_instances);
    widget.onRename?.call(inst, newName);
  }

  void _selectInstance(Instance i) {
    widget.onSelect?.call(i);
  }

  String _pageTitle(SettingsPage page) => switch (page) {
        SettingsPage.general => 'General',
        SettingsPage.models => 'Profiles',
        SettingsPage.routing => 'Routing',
        SettingsPage.memory => 'Memory',
        SettingsPage.usage => 'Usage',
        SettingsPage.vault => 'Vault',
        SettingsPage.scheduled => 'Scheduled',
      };

  Widget? _pageAction(SettingsPage page) => switch (page) {
        SettingsPage.general => _addingMachine || widget.fullPage
            ? null
            : HeaderAction('Add machine', onTap: _addMachine),
        SettingsPage.models => _modelsEditing
            ? null
            : HeaderAction('Add profile',
                onTap: () => _modelsKey.currentState?.addProfile()),
        SettingsPage.scheduled => _recurringAdding
            ? null
            : HeaderAction('New job',
                onTap: () => _recurringKey.currentState?.add()),
        _ => null,
      };

  /// One row in the desktop settings rail.
  Widget _settingsNavRow(SettingsPage page, String icon, String label) {
    final selected = _page == page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() {
            _page = page;
            _addingMachine = false;
            _modelsEditing = false;
            _renamingUrl = null;
          }),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              AppIcon(icon,
                  size: 15, color: selected ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13.5,
                        color: selected ? AppColors.fg1 : AppColors.fg2)),
              ),
            ]),
          ),
        ),
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
              color: _page == page ? AppColors.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
              child: InkWell(
                onTap: () => setState(() => _page = page),
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.s12, vertical: S.s6),
                  child: Row(children: [
                    AppIcon(icon,
                        size: 14,
                        color: _page == page ? AppColors.fg1 : AppColors.fg3),
                    const SizedBox(width: S.s6),
                    Text(label,
                        style: sans(13,
                            weight: _page == page ? W.label : W.body,
                            color:
                                _page == page ? AppColors.fg1 : AppColors.fg2)),
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
      SettingsPage.general => _generalPage(),
      SettingsPage.models => InferenceProfilesScreen(
          key: _modelsKey,
          client: widget.client,
          embedded: true,
          onEditingChanged: (editing) =>
              setState(() => _modelsEditing = editing),
        ),
      SettingsPage.routing => RoutingScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.memory => MemoryScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.usage => UsageScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.vault => VaultScreen(
          key: _vaultKey,
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.scheduled => RecurringScreen(
          key: _recurringKey,
          client: widget.client,
          embedded: true,
          onAddingChanged: (adding) =>
              setState(() => _recurringAdding = adding),
        ),
    };
  }

  /// The General section's content.
  bool? _manual;

  Future<void> _loadManual() async {
    try {
      final c = await widget.client.getConfig();
      if (mounted) setState(() => _manual = c.manualApproval);
    } catch (_) {}
  }

  Future<void> _setManual(bool on) async {
    final before = _manual;
    setState(() => _manual = on);
    try {
      await widget.client.setManualApproval(on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _manual = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _renameViaPrompt(Instance i) async {
    final name = await promptText(context, title: 'Rename machine', initial: i.label);
    if (name == null || name.trim().isEmpty || !mounted) return;
    _renameController.text = name.trim();
    await _commitRename(i);
  }

  Widget _nativeGeneral() {
    if (_manual == null) _loadManual();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        SettingsGroup(
          header: 'Machines',
          footer:
              'Snippet talks to the daemon on each machine. Run snippet serve on a new one and paste the link it prints.',
          children: [
            for (final i in _instances)
              SettingsRow(
                label: i.label.isEmpty ? i.url : i.label,
                sub: i.url,
                leading: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i.url == widget.active?.url
                        ? AppColors.ok
                        : AppColors.fg4,
                  ),
                ),
                onTap: i.url == widget.active?.url || widget.onSelect == null
                    ? null
                    : () => _selectInstance(i),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(i.url == widget.active?.url ? 'In use' : 'Connect',
                      style: sans(12.5,
                          color: i.url == widget.active?.url
                              ? AppColors.fg4
                              : AppColors.accent)),
                  const SizedBox(width: 6),
                  Builder(
                    builder: (anchor) => IconBtn('more-horizontal',
                        size: 26,
                        iconSize: 14,
                        tooltip: 'More',
                        onTap: () async {
                          final pick = await showAppMenu<String>(context,
                              anchor: anchor,
                              items: [
                                appMenuItem(
                                    value: 'rename',
                                    icon: 'edit',
                                    label: 'Rename'),
                                appMenuItem(
                                    value: 'remove',
                                    icon: 'trash',
                                    label: 'Remove',
                                    danger: true),
                              ]);
                          if (pick == 'rename') _renameViaPrompt(i);
                          if (pick == 'remove') _confirmRemove(i);
                        }),
                  ),
                ]),
              ),
            SettingsRow(
              label: 'Add a machine…',
              onTap: _addMachine,
              trailing: Text('Pair', style: sans(12.5, color: AppColors.accent)),
            ),
          ],
        ),
        SettingsGroup(
          header: 'Approvals',
          footer: 'Applies to every session on this machine.',
          children: [
            SettingsRow(
              label: 'Ask before running commands',
              sub: 'Off lets agents run shell commands and edit files without stopping to ask.',
              trailing: SettingsSwitch(
                  value: _manual ?? false,
                  onChanged: _manual == null ? null : _setManual),
            ),
          ],
        ),
        if (kCanNotify)
          SettingsGroup(header: 'Notifications', children: [
            SettingsRow(
              label: 'Notify me',
              sub: 'When a session needs you or finishes.',
              trailing: SettingsSwitch(
                  value: _notif, onChanged: _notifBusy ? null : _toggleNotif),
            ),
          ]),
      ],
    );
  }

  Widget _generalPage({bool includeNotifications = true}) {
    if (_addingMachine) return _addMachinePane();
    if (widget.fullPage) return _nativeGeneral();
    return PageBody(children: [
      if (includeNotifications)
        const SectionHeader('Machines',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
      if (_instances.isEmpty)
        EmptyState(
          icon: 'server',
          title: 'No saved machines',
          body: 'Connect to a machine running snippet serve.',
          action: HeaderAction('Add machine', onTap: _addMachine),
        )
      else
        ListGroup(children: [for (final i in _instances) _instanceRow(i)]),
      if (includeNotifications) ...[
        const SizedBox(height: S.s24),
        const SectionHeader('Approvals',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
        ListGroup(children: [ApprovalsRow(client: widget.client)]),
      ],
      if (includeNotifications && kCanNotify) ...[
        const SizedBox(height: S.s24),
        const SectionHeader('Notifications',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
        ListGroup(children: [_notifRow()]),
      ],
    ]);
  }

  Widget _addMachinePane() {
    void back() => setState(() {
          _addingMachine = false;
          _addMachineError = null;
        });
    final canConnect =
        !_addMachineBusy && _addMachinePaste.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
      children: [
        Row(children: [
          IconBtn('chevron-left',
              size: 28, iconSize: 15, tooltip: 'Back', onTap: back),
          const SizedBox(width: 6),
          Text('Connect a machine',
              style: sans(17,
                  weight: FontWeight.w500, spacing: -0.2, color: AppColors.fg1)),
        ]),
        const SizedBox(height: 22),
        SettingsGroup(
          header: 'On the other machine',
          footer: 'It prints a link and a QR code. If snippet is already '
              'running there, snippet serve --status shows them again.',
          children: [
            SettingsRow(
              label: 'snippet serve',
              labelWidget: SelectableText('snippet serve',
                  style: mono(12.5, color: AppColors.fg1)),
              trailing: IconBtn('copy',
                  size: 26, iconSize: 13, tooltip: 'Copy command', onTap: () {
                Clipboard.setData(const ClipboardData(text: 'snippet serve'));
                toast(context, 'Copied');
              }),
            ),
          ],
        ),
        SettingsGroup(
          header: 'Here',
          children: [
            SettingsRow(
              label: 'Link',
              trailing: SettingsField(
                controller: _addMachinePaste,
                hint: 'https://…?token=…',
                mono: true,
                width: 380,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_addMachineError != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 12),
                child: Text(_addMachineError!,
                    style: sans(12, height: 1.4, color: AppColors.danger)),
              ),
            ),
          SettingsPill('Cancel', onTap: _addMachineBusy ? null : back),
          const SizedBox(width: 8),
          SettingsPill(_addMachineBusy ? 'Connecting…' : 'Connect',
              onTap: canConnect ? _submitAddMachine : null),
        ]),
      ],
    );
  }

  Widget _instanceRow(Instance i) {
    final isActive = i.url == widget.active?.url;
    final isRenaming = _renamingUrl == i.url;
    final compact = kMobile && widget.embedded;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.s12, S.s8, S.s4, S.s8),
        child: Row(
          children: [
            IconTile('server', tone: isActive ? Tone.ok : Tone.neutral),
            const SizedBox(width: S.s12),
            if (isRenaming) ...[
              Expanded(
                child: InlineEditField(
                  controller: _renameController,
                  hint: 'Machine name',
                  commitOnTapOutside: false,
                  showActions: true,
                  onSubmit: () => _commitRename(i),
                  onCancel: () => setState(() => _renamingUrl = null),
                ),
              ),
            ] else ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.rowTitle()),
                    const SizedBox(height: S.s2),
                    Text(hostOf(i.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.codeSmall()),
                  ],
                ),
              ),
              const SizedBox(width: S.s8),
              if (isActive)
                const Tag('Active', tone: Tone.ok, dot: true)
              else if (widget.onSelect != null)
                TextAction('Connect', onTap: () => _selectInstance(i)),
              const SizedBox(width: S.s4),
              IconBtn('edit',
                  size: compact ? M.minTarget : 30,
                  iconSize: 16,
                  tooltip: 'Rename machine',
                  onTap: () => _startRename(i)),
              IconBtn('trash',
                  size: compact ? M.minTarget : 30,
                  iconSize: 16,
                  tooltip: 'Remove machine',
                  onTap: () => _confirmRemove(i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notifRow() {
    return Padding(
      padding: kMobile
          ? const EdgeInsets.fromLTRB(16, 14, 16, 14)
          : const EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s12),
      child: Row(children: [
        if (!kMobile) ...[
          const IconTile('bell'),
          const SizedBox(width: S.s12),
        ] else ...[
          AppIcon('bell', size: 19, color: AppColors.fg3),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kMobile ? 'Notifications' : 'Session notifications',
                  style: kMobile
                      ? sans(15, weight: W.label, color: AppColors.fg1)
                      : TS.rowTitle()),
              const SizedBox(height: S.s2),
              Text(
                  kMobile
                      ? 'When a chat needs you or finishes'
                      : 'When a session finishes or needs your input',
                  style: kMobile ? sans(13, color: AppColors.fg3) : TS.meta()),
            ],
          ),
        ),
        const SizedBox(width: S.s8),
        if (_notifBusy)
          const DelayedSpinner(size: 18)
        else
          AppSwitch(on: _notif, onChanged: _toggleNotif),
      ]),
    );
  }
}

/// Action sheet to rename or remove a machine instance.
Future<void> showManageMachineSheet({
  required BuildContext context,
  required Instance instance,
  required void Function(Instance, String) onRename,
  required void Function(Instance) onRemove,
}) async {
  showAppSheet(
    context,
    title: instance.label,
    child: SheetActions([
      SheetAction('edit', 'Rename', () async {
        Navigator.pop(context);
        final name = await promptText(
          context,
          title: 'Rename machine',
          initial: instance.label,
          hint: 'Machine name',
          saveLabel: 'Rename',
        );
        if (name != null && name.isNotEmpty) {
          onRename(instance, name);
        }
      }),
      SheetAction('trash', 'Remove', () async {
        Navigator.pop(context);
        final ok = await confirmAction(
          context,
          title: 'Remove machine?',
          body:
              '${instance.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
          confirmLabel: 'Remove',
        );
        if (ok) onRemove(instance);
      }, danger: true),
    ]),
  );
}

class ApprovalsRow extends StatefulWidget {
  const ApprovalsRow({super.key, required this.client});
  final DaemonClient client;

  @override
  State<ApprovalsRow> createState() => _ApprovalsRowState();
}

class _ApprovalsRowState extends State<ApprovalsRow> {
  bool? _manual;

  @override
  void initState() {
    super.initState();
    widget.client.getConfig().then((c) {
      if (mounted) setState(() => _manual = c.manualApproval);
    }).catchError((_) {});
  }

  Future<void> _pick(BuildContext anchor) async {
    final current = _manual ?? false;
    final picked = await showAppMenu<bool>(
      context,
      anchor: anchor,
      minWidth: 260,
      maxWidth: 320,
      items: [
        appMenuRow(
          value: false,
          icon: 'check-circle',
          label: 'Yolo',
          description: 'Run shell and file edits without asking',
          selected: !current,
        ),
        appMenuRow(
          value: true,
          icon: 'shield',
          label: 'Ask',
          description: 'Pause for approval on each change',
          selected: current,
        ),
      ],
    );
    if (picked == null || picked == current || !mounted) return;
    setState(() => _manual = picked);
    try {
      await widget.client.setManualApproval(picked);
    } catch (e) {
      if (!mounted) return;
      setState(() => _manual = current);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manual = _manual;
    return Builder(
      builder: (anchor) => ListRow(
        title: 'Approvals',
        subtitle: kMobile ? null : 'Applies to every session on this machine',
        leading: AppIcon(kMobile ? 'shield-check' : 'shield',
            size: 19, color: AppColors.fg3),
        onTap: () => _pick(anchor),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(manual == null ? '' : (manual ? 'Ask' : 'Yolo'),
              style: sans(13, color: AppColors.fg3)),
          const SizedBox(width: S.s6),
          AppIcon('chevron-down', size: 15, color: AppColors.fg4),
        ]),
      ),
    );
  }
}
