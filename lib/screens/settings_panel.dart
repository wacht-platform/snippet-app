import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart';
import 'inference_profiles.dart';
import 'recurring.dart';
import 'shell_nav.dart';
import 'usage.dart';
import 'vault.dart';

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
            S.s12, kMobile ? S.s8 : S.s6, S.s4, kMobile ? S.s8 : S.s6),
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
                  style: TS.ui(AppColors.fg1)),
              const SizedBox(height: 1),
              Text(hostOf(i.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.codeSmall()),
            ]),
          ),
          if (selected) AppIcon('check', size: 16, color: AppColors.accent),
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
    return Pressable(
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          widget.onAdd();
        },
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(14, kMobile ? 11 : 8, 14, kMobile ? 11 : 8),
          child: Row(children: [
            AppIcon('plus', size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Text('Add machine', style: TS.label(AppColors.accent)),
          ]),
        ),
      ),
    );
  }
}

enum SettingsPage { general, models, usage, vault, scheduled }

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

  /// Phone drill-down. Null shows the section list; a value shows that section.
  ///
  /// Owned by the SHELL, not by this widget: the back handler and the bar's
  /// visibility both need to read it, and neither can see inside here.
  final SettingsPage? section;
  final ValueChanged<SettingsPage?>? onSection;

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
    this.section,
    this.onSection,
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
  bool _vaultAdding = false;
  bool _recurringAdding = false;

  bool get _isNested => switch (_page) {
        SettingsPage.general => _addingMachine,
        SettingsPage.models => _modelsEditing,
        _ => false,
      };

  String? _renamingUrl;
  final TextEditingController _renameController = TextEditingController();

  SettingsPage _page = SettingsPage.general;

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
  }

  static const _nav = [
    (SettingsPage.general, 'server', 'General'),
    (SettingsPage.models, 'ai-chip', 'Inference profiles'),
    (SettingsPage.usage, 'analytics', 'Usage'),
    (SettingsPage.vault, 'lock-key', 'Vault'),
    (SettingsPage.scheduled, 'repeat', 'Scheduled jobs'),
  ];

  @override
  void initState() {
    super.initState();
    _addMachinePaste.addListener(() => setState(() {}));
    notificationsEnabled().then((v) {
      if (mounted) setState(() => _notif = v);
    });
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
      );
    }
    return Scaffold(
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
                  width: 220,
                  decoration: BoxDecoration(color: AppColors.raised),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sidebar Header
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Settings', style: TS.sectionTitle()),
                          ],
                        ),
                      ),
                      // Nav Items
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          children: [
                            for (final (page, icon, label) in _nav)
                              _settingsNavRow(page, icon, label),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Content Pane Header
                        if (!_isNested)
                          Container(
                            height: 64,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    _pageTitle(_page),
                                    style: TS.sectionTitle(),
                                  ),
                                ),
                                if (_pageAction(_page) != null)
                                  _pageAction(_page)!,
                              ],
                            ),
                          ),
                        // Active Page Content
                        Expanded(child: _pageBody()),
                      ],
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
  }

  /// Phone settings HOME.
  Widget _mobileSettingsHome() {
    final active = widget.active;
    Widget nav(SettingsPage page, String icon, String label,
            [String summary = '']) =>
        ListRow(
          title: label,
          leading: IconTile(icon),
          onTap: () => widget.onSection?.call(page),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (summary.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.meta()),
              ),
            const SizedBox(width: S.s4),
            AppIcon('chevron-right', size: 16, color: AppColors.fg4),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s40),
      children: [
        const SectionHeader('Machine',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
        ListGroup(children: [
          if (active != null)
            ListRow(
              title: active.label,
              subtitle: hostOf(active.url),
              leading: const IconTile('server', tone: Tone.ok),
              trailing: const Tag('Connected', tone: Tone.ok, dot: true),
            ),
          nav(SettingsPage.general, 'layers', 'Manage machines',
              '${_instances.length}'),
        ]),
        if (kCanNotify) ...[
          const SizedBox(height: S.s20),
          const SectionHeader('Notifications',
              padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
          ListGroup(children: [_notifRow()]),
        ],
        const SizedBox(height: S.s20),
        const SectionHeader('Workspace',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
        ListGroup(children: [
          nav(SettingsPage.models, 'ai-chip', 'Inference profiles'),
          nav(SettingsPage.usage, 'analytics', 'Usage'),
          nav(SettingsPage.vault, 'lock-key', 'Vault'),
          nav(SettingsPage.scheduled, 'repeat', 'Scheduled jobs'),
        ]),
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
              Btn('Add machine', icon: 'plus', small: true, onTap: _addMachine),
            ]),
            Expanded(child: _generalPage(includeNotifications: false)),
          ],
        ),
      SettingsPage.models => InferenceProfilesScreen(
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
        throw 'Invalid connection string. Run "snippet daemon link" on the remote machine.';
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
        SettingsPage.models => 'Inference profiles',
        SettingsPage.usage => 'Usage',
        SettingsPage.vault => 'Vault',
        SettingsPage.scheduled => 'Scheduled jobs',
      };

  Widget? _pageAction(SettingsPage page) => switch (page) {
        SettingsPage.general => _addingMachine
            ? null
            : Btn('Add machine', icon: 'plus', small: true, onTap: _addMachine),
        SettingsPage.models => _modelsEditing
            ? null
            : Btn('Add profile',
                icon: 'plus',
                small: true,
                onTap: () => _modelsKey.currentState?.addProfile()),
        SettingsPage.vault => _vaultAdding
            ? null
            : Btn('Add secret',
                icon: 'plus',
                small: true,
                onTap: () => _vaultKey.currentState?.add()),
        SettingsPage.scheduled => _recurringAdding
            ? null
            : Btn('New job',
                icon: 'plus',
                small: true,
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
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: () => setState(() {
            _page = page;
            _addingMachine = false;
            _modelsEditing = false;
            _renamingUrl = null;
          }),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: S.s8),
            child: Row(children: [
              AppIcon(icon,
                  size: 16, color: selected ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        weight: selected ? W.label : W.body,
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
      SettingsPage.usage => UsageScreen(
          client: widget.client,
          embedded: true,
        ),
      SettingsPage.vault => VaultScreen(
          key: _vaultKey,
          client: widget.client,
          embedded: true,
          onAddingChanged: (adding) => setState(() => _vaultAdding = adding),
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
  Widget _generalPage({bool includeNotifications = true}) {
    if (_addingMachine) return _addMachinePane();
    return PageBody(children: [
      if (includeNotifications)
        const SectionHeader('Machines',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
      if (_instances.isEmpty)
        EmptyState(
          icon: 'server',
          title: 'No saved machines',
          body: 'Connect to a machine running snippet serve.',
          action:
              Btn('Add machine', icon: 'plus', small: true, onTap: _addMachine),
        )
      else
        ListGroup(children: [for (final i in _instances) _instanceRow(i)]),
      if (includeNotifications && kCanNotify) ...[
        const SizedBox(height: S.s24),
        const SectionHeader('Notifications',
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6)),
        ListGroup(children: [_notifRow()]),
      ],
    ]);
  }

  Widget _addMachinePane() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      children: [
        Row(
          children: [
            IconBtn('arrow-left',
                size: 30,
                iconSize: 16,
                tooltip: 'Back',
                onTap: () => setState(() {
                      _addingMachine = false;
                      _addMachineError = null;
                    })),
            const SizedBox(width: 8),
            Text('Connect a machine', style: TS.sectionTitle()),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: Text(
            'Control a remote machine running the snippet daemon.',
            style: TS.meta(),
          ),
        ),
        const SizedBox(height: 24),
        Text('1. Run on your remote machine',
            style: sans(12, weight: W.label, color: AppColors.fg2)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  'snippet daemon link',
                  style: mono(13, color: AppColors.accent),
                ),
              ),
              IconBtn('copy', size: 26, iconSize: 13, tooltip: 'Copy command',
                  onTap: () {
                Clipboard.setData(
                    const ClipboardData(text: 'snippet daemon link'));
                toast(context, 'Copied');
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('2. Paste connection string or URL',
            style: sans(12, weight: W.label, color: AppColors.fg2)),
        const SizedBox(height: 8),
        TextField(
          controller: _addMachinePaste,
          autofocus: true,
          style: mono(12, color: AppColors.fg1),
          decoration: InputDecoration(
            hintText: 'https://host:port?token=... or {"url":..., "token":...}',
            hintStyle: mono(12, color: AppColors.fg4),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppColors.surface1,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
          onSubmitted: (_) => _submitAddMachine(),
        ),
        if (_addMachineError != null) ...[
          const SizedBox(height: 10),
          Text(_addMachineError!, style: sans(12, color: AppColors.danger)),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Btn('Cancel',
                variant: BtnVariant.ghost,
                small: true,
                onTap: () => setState(() {
                      _addingMachine = false;
                      _addMachineError = null;
                    })),
            const SizedBox(width: 8),
            Btn(_addMachineBusy ? 'Connecting…' : 'Connect machine',
                small: true,
                disabled:
                    _addMachineBusy || _addMachinePaste.text.trim().isEmpty,
                onTap: _submitAddMachine),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s12),
      child: Row(children: [
        const IconTile('bell'),
        const SizedBox(width: S.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session notifications', style: TS.rowTitle()),
              const SizedBox(height: S.s2),
              Text('When a session finishes or needs your input',
                  style: TS.meta()),
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
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: AppIcon('edit', size: 16, color: AppColors.fg2),
          title: Text('Rename', style: TS.ui(AppColors.fg1)),
          onTap: () async {
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
                  '${instance.label}\n\nRemoves the saved connection from this app. The machine and its sessions are untouched.',
              confirmLabel: 'Remove',
            );
            if (ok) onRemove(instance);
          },
        ),
      ],
    ),
  );
}
