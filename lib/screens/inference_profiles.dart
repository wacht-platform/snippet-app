import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../settings_form.dart';
import '../widgets.dart';
import 'inference_profile_editor.dart';
import 'shell_nav.dart';

class InferenceProfilesScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;

  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;

  /// Host-supplied back action for [embedded] use. The screen draws its OWN
  /// `NavBackRow`, so exactly one header exists per level — the host drawing it
  /// instead is what produced two stacked back rows in the model editor.
  final VoidCallback? onBack;
  final ValueChanged<bool>? onEditingChanged;

  const InferenceProfilesScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
    this.onBack,
    this.onEditingChanged,
  });
  @override
  State<InferenceProfilesScreen> createState() =>
      InferenceProfilesScreenState();
}

class InferenceProfilesScreenState extends State<InferenceProfilesScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<ServerConfig> _future;
  bool _inEditor = false;
  InferenceProfile? _editProfile;
  bool? _keepTaskProfile;
  String? _selected;
  bool _creating = false;
  GlobalKey<InferenceProfileEditorState> _editorKey =
      GlobalKey<InferenceProfileEditorState>();

  bool get _split => !kMobile && widget.embedded;

  Future<bool> _canLeave() async {
    final editor = _editorKey.currentState;
    if (editor == null || !editor.dirty) return true;
    return confirmAction(context,
        title: 'Discard changes?',
        body: 'Your edits to this profile have not been saved.',
        confirmLabel: 'Discard');
  }

  Future<void> _choose(String? name, {bool creating = false}) async {
    if (!creating && name == _selected && !_creating) return;
    if (!await _canLeave() || !mounted) return;
    setState(() {
      _editorKey = GlobalKey<InferenceProfileEditorState>();
      _selected = name;
      _creating = creating;
    });
  }

  Future<void> _setKeepTaskProfile(bool on) async {
    setState(() => _keepTaskProfile = on);
    try {
      await widget.client.setKeepTaskProfile(on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _keepTaskProfile = !on);
      toast(context, "Couldn't change it: $e", danger: true);
    }
  }

  final Map<String, InferenceProfile> _saving = {};
  final Set<String> _deletingProfiles = {};

  void addProfile() => _edit(null);

  void _submitted(InferenceProfile draft, Future<void> save) {
    setState(() {
      _saving[draft.name] = draft;
      if (_split && _creating) {
        _editorKey = GlobalKey<InferenceProfileEditorState>();
        _creating = false;
        _selected = draft.name;
      }
    });
    save.then((_) {
      if (!mounted) return;
      widget.client.invalidateConfig();
      setState(() {
        _saving.remove(draft.name);
        _load(force: true);
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _saving.remove(draft.name));
      toast(context, "Couldn't save ${draft.name}: $e", danger: true);
    });
  }

  List<InferenceProfile> _withSaving(List<InferenceProfile> all) {
    final profiles = _deletingProfiles.isEmpty
        ? all
        : [
            for (final p in all)
              if (!_deletingProfiles.contains(p.name)) p
          ];
    if (_saving.isEmpty) return profiles;
    final activating = _saving.values.any((p) => p.active);
    final out = [
      for (final p in profiles)
        _saving[p.name] ?? (activating && p.active ? p.withActive(false) : p),
    ];
    for (final d in _saving.values) {
      if (!out.any((p) => p.name == d.name)) out.add(d);
    }
    return out;
  }

  bool get inEditor => _inEditor;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    modelsRevision.addListener(_onModelsChanged);
    _load();
  }

  void _load({bool force = false}) {
    _future = widget.client.getConfig(force: force);
  }

  void _onModelsChanged() {
    if (!mounted || _inEditor) return;
    setState(() {
      _load(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant InferenceProfilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _load();
    }
  }

  @override
  void dispose() {
    modelsRevision.removeListener(_onModelsChanged);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _load();
    });
  }

  Future<void> _run(Future<void> Function() op, String onError) async {
    try {
      await op();
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$onError: $e', danger: true);
    }
  }

  Future<void> _edit(InferenceProfile? p) async {
    if (_split) {
      await _choose(p?.name, creating: p == null);
      return;
    }
    if (kMobile && widget.embedded) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (ctx) => InferenceProfileEditor(
            client: widget.client,
            existing: p,
            onDelete: p == null
                ? null
                : () async {
                    if (await _confirmDelete(p) && ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
            onClose: () => Navigator.pop(context),
            onSaved: () => Navigator.pop(context, true),
            onSubmit: _submitted,
          ),
        ),
      );
      if (saved == true && mounted) _refresh();
      return;
    }
    setState(() {
      _inEditor = true;
      _editProfile = p;
    });
    widget.onEditingChanged?.call(true);
  }

  void _closeEditor({bool saved = false}) {
    if (!mounted) return;
    setState(() {
      _inEditor = false;
      _editProfile = null;
    });
    widget.onEditingChanged?.call(false);
    if (saved) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(context); // Rebuild on theme change
    if (_split) return _splitView();
    if (_inEditor) {
      final editing = _editProfile;
      final editor = InferenceProfileEditor(
        client: widget.client,
        existing: _editProfile,
        onDelete: editing == null
            ? null
            : () async {
                if (await _confirmDelete(editing)) _closeEditor();
              },
        embedded: widget.embedded,
        onClose: () => _closeEditor(),
        onSaved: () => _closeEditor(saved: true),
        onSubmit: _submitted,
      );
      if (!widget.embedded) return editor;
      // The editor brings NO header of its own when embedded — THIS level owns
      // it, on both platforms:
      //   phone   → the host draws no header, so this is the only row;
      //   desktop → the chip strip names the SECTION but offers no way back to
      //             the profiles list, so this row is what returns there.
      // Drawing a second row is what produced the stacked-header bug: the host
      // drew one for "Inference profiles" AND the editor drew its own for
      // "Edit profile".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(widget.embedded ? 18 : 4, 6, 24, 6),
            child: NavBackRow(
              title: _editProfile == null ? 'Add profile' : 'Edit profile',
              onBack: _closeEditor,
            ),
          ),
          Expanded(child: editor),
        ],
      );
    }
    final body = FutureBuilder<ServerConfig>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ListSkeleton();
        }
        final cfg = snap.data;
        final profiles = _withSaving(cfg?.profiles ?? const []);
        return PageBody(children: [
          if (profiles.isEmpty)
            EmptyState(
              icon: 'ai-chip',
              title: 'No inference profiles',
              body:
                  'Add an API key or a local model provider to start sessions.',
              action: kMobile
                  ? null
                  : Btn('Add profile',
                      icon: 'plus', small: true, onTap: () => _edit(null)),
            )
          else ...[
            SettingsGroup(
              footer:
                  'New chats use the active profile. Lanes and background work follow Routing.',
              children: [
                for (final p in profiles)
                  SettingsRow(
                    label: p.name,
                    sub: '${p.provider} · ${p.model}',
                    leading: ProviderLogo(p.provider, size: kMobile ? 18 : 16),
                    onTap: () => _edit(p),
                    chevron: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!p.usable) const WarnChip(),
                      if (p.active)
                        Text('Active',
                            style: sans(kMobile ? 14 : 12, color: AppColors.fg3)),
                    ]),
                  ),
              ],
            ),
            SettingsGroup(children: [
              SettingsRow(
                label: "Keep a task's model",
                sub: 'Chats stay on the model a task used.',
                trailing: SettingsSwitch(
                  value: _keepTaskProfile ?? cfg?.keepTaskProfile ?? true,
                  onChanged: _setKeepTaskProfile,
                ),
              ),
            ]),
          ],
        ]);
      },
    );
    if (widget.embedded) {
      // Desktop dialog pane: host owns navigation (chip strip), so no back row.
      if (widget.onBack == null) return body;
      // Phone drill-down: this level owns the header (see the editor branch).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(
              title: 'Profiles',
              onBack: widget.onBack!,
              trailing: [
                HeaderAction('Add profile', onTap: () => _edit(null)),
              ]),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Inference profiles',
              compact: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
              actions: [
                HeaderAction('Add profile', onTap: () => _edit(null)),
              ]),
          Expanded(child: body),
        ]),
      ),
    );
  }

  Widget _splitView() {
    return FutureBuilder<ServerConfig>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ListSkeleton();
        }
        final cfg = snap.data;
        final profiles = _withSaving(cfg?.profiles ?? const []);
        final creating = _creating || profiles.isEmpty;
        final current = creating
            ? null
            : profiles.where((p) => p.name == _selected).firstOrNull ??
                profiles.where((p) => p.active).firstOrNull ??
                profiles.first;
        final keep = _keepTaskProfile ?? cfg?.keepTaskProfile ?? true;
        final master = MasterPane(
          title: 'Profiles',
          actions: [
            IconBtn('plus',
                size: 28,
                iconSize: 14,
                tooltip: 'Add profile',
                onTap: () => _choose(null, creating: true)),
          ],
          children: [
            if (creating)
              ListRow(
                title: 'New profile',
                subtitle: 'Not saved yet',
                leading: AppIcon('plus', size: 16, color: AppColors.fg3),
                selected: true,
              ),
            for (final p in profiles)
              ListRow(
                title: p.name,
                subtitle: '${p.provider} · ${p.model}',
                leading: ProviderLogo(p.provider, size: 16),
                selected: !creating && p.name == current?.name,
                onTap: () => _choose(p.name),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!p.usable) const WarnChip(),
                  if (p.active) ...[
                    if (!p.usable) const SizedBox(width: S.s4),
                    const Tag('Active', tone: Tone.ok, dot: true),
                  ],
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s8, S.s24, S.s8, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Keep a task's model",
                          style: sans(13.5,
                              weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Text('Chats stay on the model a task used.',
                          style:
                              sans(12.5, height: 1.45, color: AppColors.fg3)),
                    ],
                  ),
                ),
                const SizedBox(width: S.s12),
                SettingsSwitch(value: keep, onChanged: _setKeepTaskProfile),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s8, S.s12, S.s8, 0),
              child: Text(
                  'New chats use the active profile. Lanes and background work follow Routing.',
                  style: sans(12.5, height: 1.45, color: AppColors.fg3)),
            ),
          ],
        );
        final detail = InferenceProfileEditor(
            key: _editorKey,
            client: widget.client,
            existing: current,
            detail: true,
            embedded: true,
            onDelete: current == null
                ? null
                : () async {
                    if (await _confirmDelete(current) && mounted) {
                      setState(() {
                        _editorKey = GlobalKey<InferenceProfileEditorState>();
                        _selected = null;
                      });
                    }
                  },
            onSubmit: _submitted,
        );
        return MasterDetail(master: master, detail: detail);
      },
    );
  }

  Future<bool> _confirmDelete(InferenceProfile p) async {
    final ok = await confirmAction(context,
        title: 'Delete ${p.name}?',
        body: p.active
            ? 'This is the active profile. New chats will need another one.'
            : 'Chats already using it keep their history.');
    if (!ok || !mounted) return false;
    setState(() => _deletingProfiles.add(p.name));
    try {
      await widget.client.deleteProfile(p.name);
      if (!mounted) return true;
      widget.client.invalidateConfig();
      setState(() {
        _deletingProfiles.remove(p.name);
        _load(force: true);
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _deletingProfiles.remove(p.name));
      toast(context, "Couldn't delete ${p.name}: $e", danger: true);
      return false;
    }
  }
}
