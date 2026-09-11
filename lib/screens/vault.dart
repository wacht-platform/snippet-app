import 'package:flutter/material.dart';

import '../api.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
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

  const VaultScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
    this.onBack,
  });
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<String>? _names;
  bool _loading = true;
  String? _error;

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

  /// Add a secret. The sheet owns validation, so a mistake keeps the form OPEN
  /// with the text intact — the previous flow closed first and then toasted
  /// "Name and value are required", losing everything the user had typed.
  Future<void> _add() async {
    final name = await showAppSheet<String>(
      context,
      title: 'Add secret',
      child: _AddSecretSheet(client: widget.client),
    );
    if (name == null || !mounted) return;
    setState(() {
      _names ??= [];
      if (!_names!.contains(name)) _names!.add(name);
      _names!.sort();
    });
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
    Widget body;
    if (_loading && _names == null) {
      body = Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.fg3)));
    } else if (_error != null && _names == null) {
      // An unreachable daemon is not an empty vault. Give it a real message and
      // a retry rather than dumping the raw exception at the user.
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('alert-triangle', size: 20, color: AppColors.danger),
            const SizedBox(height: 10),
            Text("Couldn't load secrets",
                style: sans(13.5, weight: W.label, color: AppColors.fg1)),
            const SizedBox(height: 5),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(11.5, height: 1.4, color: AppColors.fg4)),
            const SizedBox(height: 14),
            Btn('Retry', small: true, onTap: _load),
          ]),
        ),
      );
    } else {
      final names = _names ?? const [];
      final list = ListView(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 16, 14, kMobile ? M.gutter : 16, 28),
        children: [
          Text(
            'Use these as \$NAME in shell commands. Values stay on the daemon and are never shown again.',
            style:
                sans(kMobile ? M.meta : 12, height: 1.45, color: AppColors.fg4),
          ),
          const SizedBox(height: 16),
          _inlineLabel('Secrets'),
          const SizedBox(height: 8),
          _card([
            if (names.isEmpty)
              _emptyRow()
            else ...[
              for (final n in names) _secretRow(n),
            ],
          ]),
          const SizedBox(height: 12),
          _addRow(),
        ],
      );
      body = widget.embedded || kMobile
          ? list
          : Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: list));
    }
    if (widget.embedded) {
      // See usage.dart: a null back action means the host owns navigation.
      if (widget.onBack == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Vault', onBack: widget.onBack!),
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
              onBack: widget.onClose ?? () => Navigator.pop(context)),
          Expanded(child: body),
        ]),
      ),
    );
  }

  /// Section label, matching the settings screens so the two cannot drift.
  Widget _inlineLabel(String t) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(t.toUpperCase(),
            style: sans(kMobile ? 11 : 10,
                weight: W.label, color: AppColors.fg4, spacing: 0.5)),
      );

  /// Grouped surface with hairline separators — the same treatment as every
  /// other list in Settings. The rows here used to float bare on the page.
  Widget _card(List<Widget> children) => Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, thickness: 1, color: AppColors.border),
            ],
          ],
        ),
      );

  Widget _emptyRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(children: [
          AppIcon('lock-key', size: 16, color: AppColors.fg4),
          const SizedBox(width: 12),
          Expanded(
            child: Text('No secrets stored yet.',
                style: sans(kMobile ? M.meta : 12, color: AppColors.fg3)),
          ),
        ]),
      );

  /// One stored secret.
  ///
  /// Fixed height and real touch targets: the old row was nominally 48px with a
  /// 32px trash, both under the app's 52/44 scale, and the trash had neither a
  /// tooltip nor a label.
  Widget _secretRow(String name) {
    return SizedBox(
      height: kMobile ? M.rowHeight : 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          // Tinted tile, matching the settings index rows.
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(R.xs),
            ),
            child: AppIcon('lock-key', size: 14, color: AppColors.fg3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(kMobile ? 13 : 12.5, color: AppColors.fg1)),
          ),
          // A masked placeholder, not the value — the value never leaves the
          // daemon, so there is nothing here to reveal.
          Text('••••••', style: mono(11.5, color: AppColors.fg4)),
          const SizedBox(width: 4),
          IconBtn('trash',
              size: kMobile ? M.minTarget : 34,
              iconSize: kMobile ? 16 : 15,
              tooltip: 'Remove $name',
              onTap: () => _remove(name)),
        ]),
      ),
    );
  }

  /// The add affordance, as a full-height row at the app's touch minimum.
  Widget _addRow() {
    const pad = EdgeInsets.symmetric(horizontal: 14);
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _add,
        child: SizedBox(
          height: kMobile ? M.minTarget : 44,
          child: Padding(
            padding: pad,
            child: Row(children: [
              AppIcon('plus', size: 16, color: AppColors.accent),
              const SizedBox(width: 12),
              Text('Add secret', style: sans(13.5, color: AppColors.fg1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The add-secret form.
///
/// A real form rather than a fire-and-forget sheet: it validates BEFORE closing,
/// shows the reason inline, and only pops once the daemon has accepted the
/// value. The previous flow popped first and toasted afterwards, so a mistyped
/// entry lost both fields.
class _AddSecretSheet extends StatefulWidget {
  final DaemonClient client;
  const _AddSecretSheet({required this.client});
  @override
  State<_AddSecretSheet> createState() => _AddSecretSheetState();
}

class _AddSecretSheetState extends State<_AddSecretSheet> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final n = _name.text.trim().toUpperCase();
    final v = _value.text;
    if (n.isEmpty) {
      setState(() => _error = 'Give the secret a name.');
      return;
    }
    if (v.trim().isEmpty) {
      setState(() => _error = 'Give the secret a value.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.vaultSet(n, v);
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          label: 'Name',
          controller: _name,
          mono: true,
          autofocus: !kMobile,
          hint: 'STRIPE_KEY',
          helper: 'Upper-case letters, digits and underscores.',
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'Value',
          controller: _value,
          mono: true,
          obscure: true,
          hint: 'sk_live_…',
          helper: 'Stored on the daemon. It cannot be read back after saving.',
          onSubmitted: (_) => _save(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            AppIcon('alert-triangle', size: 13, color: AppColors.danger),
            const SizedBox(width: 7),
            Expanded(
              child: Text(_error!,
                  style: sans(11.5, height: 1.4, color: AppColors.danger)),
            ),
          ]),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Btn('Cancel',
                variant: BtnVariant.ghost,
                full: true,
                onTap: _busy ? null : () => Navigator.pop(context)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Btn(
              _busy ? 'Saving…' : 'Save',
              full: true,
              disabled: _busy,
              onTap: _save,
            ),
          ),
        ]),
      ],
    );
  }
}
