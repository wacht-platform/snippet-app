import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
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
  String? _delegate;

  void addProfile() => _edit(null);
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
    String? delegate;
    try {
      delegate = (await widget.client.getConfig()).delegate;
    } catch (_) {}
    if (!mounted) return;
    if (kMobile && widget.embedded) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => InferenceProfileEditor(
            client: widget.client,
            existing: p,
            delegateName: delegate,
            onClose: () => Navigator.pop(context),
            onSaved: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (saved == true && mounted) _refresh();
      return;
    }
    setState(() {
      _inEditor = true;
      _editProfile = p;
      _delegate = delegate;
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
    if (_inEditor) {
      final editor = InferenceProfileEditor(
        client: widget.client,
        existing: _editProfile,
        delegateName: _delegate,
        embedded: widget.embedded,
        onClose: () => _closeEditor(),
        onSaved: () => _closeEditor(saved: true),
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
        final profiles = cfg?.profiles ?? const [];
        return PageBody(children: [
          if (profiles.isEmpty)
            EmptyState(
              icon: 'ai-chip',
              title: 'No inference profiles',
              body:
                  'Add an API key or a local model provider to start sessions.',
              action: Btn('Add profile',
                  icon: 'plus', small: true, onTap: () => _edit(null)),
            )
          else ...[
            ListGroup(children: [
              for (final p in profiles) _profileCard(p, cfg?.delegate),
            ]),
            const SettingsNote(
                'New chats use the active profile. Parallel lanes use the delegate.'),
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
              title: 'Inference profiles',
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

  Widget _profileCard(InferenceProfile p, String? delegate) {
    final isDelegate =
        delegate != null && delegate.isNotEmpty && delegate == p.name;
    return ListRow(
      title: p.name,
      onTap: () => _edit(p),
      leading: IconTile('ai-chip', tone: p.active ? Tone.accent : Tone.neutral),
      titleWidget: Row(children: [
        Flexible(
          child: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.rowTitle()),
        ),
        if (p.active) ...[
          const SizedBox(width: S.s8),
          const Tag('Active', tone: Tone.accent),
        ],
        if (isDelegate) ...[
          const SizedBox(width: S.s6),
          const Tag('Delegate'),
        ],
        if (!p.usable) ...[
          const SizedBox(width: S.s6),
          const WarnChip(),
        ],
      ]),
      subtitle: '${p.provider} · ${p.model}',
      // Phones keep destructive actions off the row: long-press for them.
      onLongPress: kMobile ? () => _profileActions(p) : null,
      trailing: kMobile ? null : _deleteProfileButton(p),
    );
  }

  Widget _deleteProfileButton(InferenceProfile p) => IconBtn(
        'trash',
        size: 32,
        iconSize: 16,
        tooltip: 'Delete profile',
        onTap: () => _confirmDelete(p),
      );

  void _profileActions(InferenceProfile p) => showAppSheet(context,
      title: p.name,
      child: SheetActions([
        SheetAction('edit', 'Edit', () {
          Navigator.pop(context);
          _edit(p);
        }),
        SheetAction('trash', 'Delete', () {
          Navigator.pop(context);
          _confirmDelete(p);
        }, danger: true),
      ]));

  Future<void> _confirmDelete(InferenceProfile p) async {
    final ok = await confirmAction(context,
        title: 'Delete ${p.name}?',
        body: p.active
            ? 'This is the active profile. New chats will need another one.'
            : 'Chats already using it keep their history.');
    if (ok) await _run(() => widget.client.deleteProfile(p.name), 'delete');
  }
}
