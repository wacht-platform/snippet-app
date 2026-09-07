import 'package:flutter/material.dart';

import '../api.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Secret vault — names only ever reach this screen (and the agent); values go
/// straight to the daemon on save and are injected/redacted server-side.
class VaultScreen extends StatefulWidget {
  final DaemonClient client;
  final VoidCallback? onClose;
  /// When true, skip the app bar and fill the parent (settings dialog pane).
  final bool embedded;
  const VaultScreen({
    super.key,
    required this.client,
    this.onClose,
    this.embedded = false,
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

  Future<void> _add() async {
    final name = TextEditingController();
    final value = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(R.sheetTop))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 18, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add secret', style: sans(16, color: AppColors.fg1)),
              const SizedBox(height: 14),
              AppField(
                  label: 'Name',
                  controller: name,
                  mono: true,
                  hint: 'STRIPE_KEY — env-var style (A-Z, 0-9, _)'),
              const SizedBox(height: 12),
              AppField(
                  label: 'Value',
                  controller: value,
                  mono: true,
                  obscure: true,
                  hint: 'stored on the daemon, never shown again'),
              const SizedBox(height: 16),
              Btn('Save', full: true, onTap: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 8),
            ]),
      ),
    );
    if (saved != true) return;
    final n = name.text.trim().toUpperCase();
    final v = value.text;
    if (n.isEmpty || v.trim().isEmpty) {
      if (mounted) toast(context, 'Name and value are required', danger: true);
      return;
    }
    final prev = [...?_names];
    setState(() {
      _names ??= [];
      if (!_names!.contains(n)) _names!.add(n);
      _names!.sort();
    });
    try {
      await widget.client.vaultSet(n, v);
      if (mounted) toast(context, 'Saved $n');
    } catch (e) {
      if (!mounted) return;
      setState(() => _names = prev);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _remove(String name) async {
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
      body = Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Text(_error!, style: sans(13, color: AppColors.danger)),
      );
    } else {
      final names = _names ?? const [];
      final list = ListView(
        padding: EdgeInsets.fromLTRB(
            widget.embedded ? 18 : 16, widget.embedded ? 12 : 14, 16, 24),
        children: [
          Text(
            'The agent can use these as \$NAME in shell commands. Values stay on the daemon and never appear in chat.',
            style: sans(12, height: 1.4, color: AppColors.fg3),
          ),
          const SizedBox(height: 10),
          if (names.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
              child: Text('No secrets yet.',
                  style: sans(13, color: AppColors.fg3)),
            ),
          ...names.map(_secretRow),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _add,
              borderRadius: BorderRadius.circular(R.md),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(children: [
                  AppIcon('plus', size: 16, color: AppColors.fg3),
                  const SizedBox(width: 12),
                  Text('Add secret', style: sans(14, color: AppColors.fg2)),
                ]),
              ),
            ),
          ),
        ],
      );
      body = widget.embedded || kMobile
          ? list
          : Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: list));
    }
    if (widget.embedded) return body;
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

  Widget _secretRow(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        AppIcon('key', size: 16, color: AppColors.fg3),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: mono(13.5, color: AppColors.fg1))),
        Text('••••••', style: mono(12, color: AppColors.fg4)),
        IconBtn('trash', size: 32, iconSize: 16, onTap: () => _remove(name)),
      ]),
    );
  }
}
