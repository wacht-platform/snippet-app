import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_layout.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../settings_form.dart';
import 'shell_nav.dart';

/// Secret vault — names only ever reach this screen (and the agent); values go
/// straight to the daemon on save and are injected/redacted server-side.
class VaultScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;

  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;

  /// Host-supplied back action for [embedded] use. This screen draws its OWN
  /// `NavBackRow`, so exactly one header exists per level.
  final VoidCallback? onBack;
  final ValueChanged<bool>? onAddingChanged;

  const VaultScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
    this.onBack,
    this.onAddingChanged,
  });
  @override
  State<VaultScreen> createState() => VaultScreenState();
}

class VaultScreenState extends State<VaultScreen> {
  List<String>? _names;
  bool _loading = true;
  String? _error;

  /// Desktop only: the inline add form is open in the list.
  bool _adding = false;

  bool get isAdding => _adding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final names = await widget.client.vaultList();
      if (!mounted) return;
      setState(() {
        _names = names;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Add a secret.
  ///
  /// DESKTOP opens an INLINE form in the list instead of a sheet. The vault is
  /// itself a pane inside the Settings dialog, so a modal on top produced a
  /// dialog-on-dialog — two stacked surfaces for one field pair, and the
  /// backdrop dimmed the very list you were adding to.
  ///
  /// MOBILE keeps the sheet: a form inline in a phone list fights the scroll
  /// and the keyboard, and `showAppSheet` already handles the insets.
  Future<void> add() => _add();

  final _name = TextEditingController();
  final _value = TextEditingController();
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_adding) return;
    _name.clear();
    _value.clear();
    setState(() {
      _adding = true;
      _formError = null;
    });
    widget.onAddingChanged?.call(true);
  }

  void _cancel() {
    setState(() => _adding = false);
    widget.onAddingChanged?.call(false);
  }

  Future<void> _save() async {
    if (_busy) return;
    final n = _name.text.trim().toUpperCase();
    final v = _value.text;
    if (n.isEmpty || v.trim().isEmpty) {
      setState(() => _formError =
          n.isEmpty ? 'Give the secret a name.' : 'Give the secret a value.');
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await widget.client.vaultSet(n, v);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _names ??= [];
        if (!_names!.contains(n)) _names!.add(n);
        _names!.sort();
        _adding = false;
      });
      widget.onAddingChanged?.call(false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _formError = '$e';
        });
      }
    }
  }

  Future<void> _remove(String name) async {
    // Confirm first. This is the only place in the app where a destructive
    // action had no guard, and a secret cannot be recovered — the value is
    // never readable again after save.
    final ok = await confirmAction(
      context,
      title: 'Remove $name?',
      body:
          'The agent will no longer be able to use it. The stored value cannot be recovered — you would need to add it again.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    final prev = [...?_names];
    setState(() => _names?.remove(name));
    try {
      await widget.client.vaultDelete(name);
      if (mounted) toast(context, 'Removed $name');
    } catch (e) {
      if (!mounted) return;
      setState(() => _names = prev);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (!kMobile) return _desktopPage();
    Widget body;
    if (_loading && _names == null) {
      body = const ListSkeleton(subtitle: false);
    } else if (_error != null && _names == null) {
      // An unreachable daemon is not an empty vault. Give it a real message and
      // a retry rather than dumping the raw exception at the user.
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('alert-triangle', size: 20, color: AppColors.danger),
            const SizedBox(height: 10),
            Text("Couldn't load secrets", style: TS.label(AppColors.fg1)),
            const SizedBox(height: 5),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(11, height: 1.4, color: AppColors.fg3)),
            const SizedBox(height: 14),
            Btn('Retry', small: true, onTap: _load),
          ]),
        ),
      );
    } else {
      final names = _names ?? const [];
      body = PageBody(children: [
        const SizedBox(height: 4),
        SettingsGroup(
          footer: 'Use these as \$NAME in shell commands. Values stay on '
              'the machine and are never shown again.',
          children: [
            for (final n in names) _secretRow(n),
            if (_adding) ..._form() else _addRow(names.isEmpty),
          ],
        ),
      ]);
    }
    if (widget.embedded) {
      // See usage.dart: a null back action means the host owns navigation.
      if (widget.onBack == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Vault', onBack: widget.onBack!, trailing: const []),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
              title: 'Vault',
              compact: true,
              onBack: widget.onClose ?? () => Navigator.pop(context),
              actions: const []),
          Expanded(child: body),
        ]),
      ),
    );
  }

  Widget _desktopPage() {
    final names = _names ?? const <String>[];
    final Widget content;
    if (_loading && _names == null) {
      content = const ListSkeleton(subtitle: false);
    } else if (_error != null && _names == null) {
      content = SettingsGroup(children: [
        SettingsRow(
          label: "Couldn't load secrets",
          sub: _error,
          trailing: Btn('Retry', small: true, variant: BtnVariant.surface, onTap: _load),
        ),
      ]);
    } else {
      content = SettingsGroup(
        footer: 'Values stay on this machine and are never shown again.',
        children: [
          if (_adding) ..._desktopForm(),
          for (final n in names) _secretRow(n),
          if (names.isEmpty && !_adding)
            SettingsRow(
                label: 'No secrets yet',
                sub: 'Add one and agents can use it as \$NAME.'),
        ],
      );
    }
    return SettingsColumn(children: [
      SettingsHeader(
        title: 'Vault',
        subtitle: 'Secrets agents can use as \$NAME without seeing the value.',
        actions: [
          if (!_adding) Btn('Add secret', small: true, icon: 'plus', onTap: _add),
        ],
      ),
      const SizedBox(height: S.s8),
      content,
    ]);
  }

  List<Widget> _desktopForm() => [
        SettingsRow(
          label: 'Name',
          sub: 'Use it as \$NAME in shell commands.',
          trailing: SettingsField(
              controller: _name, hint: 'STRIPE_KEY', mono: true, width: 260),
        ),
        SettingsRow(
          label: 'Value',
          sub: 'Sent to the daemon on save and redacted from output.',
          trailing: SettingsField(
              controller: _value,
              hint: 'sk_live_…',
              mono: true,
              obscure: true,
              width: 260),
        ),
        SettingsRow(
          label: _formError ?? '',
          labelWidget: _formError == null
              ? const SizedBox.shrink()
              : Text(_formError!, style: sans(12, color: AppColors.danger)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Btn('Cancel',
                small: true,
                variant: BtnVariant.surface,
                disabled: _busy,
                onTap: _cancel),
            const SizedBox(width: 8),
            Btn(_busy ? 'Saving…' : 'Save secret',
                small: true, disabled: _busy, onTap: _save),
          ]),
        ),
      ];

  Widget _addRow(bool empty) => SettingsRow(
        label: 'Add secret',
        sub: empty ? 'No secrets yet' : null,
        labelWidget: Row(children: [
          AppIcon('plus', size: kMobile ? 15 : 13, color: AppColors.accent),
          SizedBox(width: kMobile ? 8 : 7),
          Text('Add secret',
              style: sans(kMobile ? 15 : 13, color: AppColors.accent)),
        ]),
        onTap: _add,
      );

  List<Widget> _form() => [
        SettingsRow(
          label: 'Name',
          trailing: SettingsField(
              controller: _name, hint: 'STRIPE_KEY', mono: true, width: 260),
        ),
        SettingsRow(
          label: 'Value',
          trailing: SettingsField(
              controller: _value,
              hint: 'sk_live_…',
              mono: true,
              obscure: true,
              width: 260),
        ),
        SettingsRow(
          label: _formError ?? '',
          labelWidget: Text(_formError ?? '',
              style: sans(kMobile ? 13 : 12, color: AppColors.danger)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            SettingsPill('Cancel', onTap: _busy ? null : _cancel),
            const SizedBox(width: 8),
            SettingsPill(_busy ? 'Saving…' : 'Save', onTap: _save),
          ]),
        ),
      ];

  Widget _secretRow(String name) => SettingsRow(
        label: name,
        labelWidget: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(kMobile ? 14 : 12.5, color: AppColors.fg1)),
        trailing: IconBtn('trash',
            size: kMobile ? 36 : 26,
            iconSize: kMobile ? 15 : 13,
            tooltip: 'Remove $name',
            onTap: () => _remove(name)),
      );
}
