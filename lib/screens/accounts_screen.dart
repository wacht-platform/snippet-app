import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import 'shell_nav.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen(
      {super.key, required this.client, this.embedded = false, this.onBack});
  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  Map<String, List<Account>> _accounts = {};
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accounts = await widget.client.getAccounts();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _mutate(
      Future<Map<String, dynamic>> Function() action, String provider) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      final listing = result[provider];
      if (listing is List) {
        final updated = Map<String, List<Account>>.from(_accounts);
        updated[provider] = listing
            .map((a) => Account.fromJson((a as Map).cast<String, dynamic>()))
            .toList();
        if (mounted) setState(() => _accounts = updated);
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add(String provider) async {
    final tokenController = TextEditingController();
    final labelController = TextEditingController();
    final claude = provider == 'claude-code';
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Add ${_title(provider)} account'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                if (claude)
                  const Text(
                      'On any machine, run claude setup-token and paste the resulting token here.'),
                if (claude)
                  TextField(
                      controller: tokenController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'Setup token')),
                TextField(
                    controller: labelController,
                    decoration:
                        const InputDecoration(labelText: 'Name (optional)')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'))
              ],
            ));
    if (accepted != true) {
      tokenController.dispose();
      labelController.dispose();
      return;
    }
    try {
      final result = await widget.client.addAccount(provider,
          label: labelController.text.trim(),
          token: claude ? tokenController.text.trim() : null);
      if (claude) {
        await _load();
      } else {
        final id = result['id'] as String?;
        if (id == null) return;
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Finish sign-in'),
                  content: SelectableText(
                      'Enter code: ${result['user_code'] ?? ''}\n\n${result['verification_uri'] ?? ''}'),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          final uri = Uri.tryParse(
                              '${result['verification_uri'] ?? ''}');
                          if (uri != null) {
                            Navigator.pop(context);
                            await _openUri(uri);
                          }
                        },
                        child: const Text('Open sign-in page')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'))
                  ],
                ));
        _poll?.cancel();
        final start = DateTime.now();
        _poll = Timer.periodic(const Duration(seconds: 3), (timer) async {
          if (DateTime.now().difference(start) > const Duration(minutes: 10)) {
            timer.cancel();
            return;
          }
          try {
            final accounts = await widget.client.getAccounts();
            if (accounts[provider]!.any((a) => a.id == id)) {
              timer.cancel();
              if (mounted) setState(() => _accounts = accounts);
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      tokenController.dispose();
      labelController.dispose();
    }
  }

  Future<void> _openUri(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _rename(String provider, Account account) async {
    final controller = TextEditingController(text: account.label);
    final label = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Rename account'),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Save'))
              ],
            ));
    controller.dispose();
    if (label != null && label.isNotEmpty) {
      await _mutate(
          () => widget.client
              .updateAccount(provider, id: account.id, label: label),
          provider);
    }
  }

  Future<void> _remove(String provider, Account account) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Remove account?'),
              content:
                  Text('Remove ${account.label} from ${_title(provider)}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove'))
              ],
            ));
    if (yes == true) {
      await _mutate(
          () => widget.client.removeAccount(provider, account.id), provider);
    }
  }

  String _title(String provider) => switch (provider) {
        'chatgpt' => 'ChatGPT',
        'xai' => 'xAI / SuperGrok',
        _ => 'Claude Code'
      };

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                      'When an account reaches its 5-hour or weekly limit, snippet switches to the next one in this order.')),
              if (_error != null)
                Text('Unable to load accounts: $_error',
                    style: TextStyle(color: AppColors.danger)),
              for (final provider in ['chatgpt', 'xai', 'claude-code'])
                _section(provider),
            ],
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.embedded && widget.onBack != null)
        NavBackRow(title: 'Accounts', onBack: widget.onBack!),
      Expanded(
          child:
              Padding(padding: EdgeInsets.all(kMobile ? 16 : 24), child: body)),
    ]);
  }

  Widget _section(String provider) {
    final accounts = _accounts[provider] ?? [];
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(_title(provider), style: TS.sectionTitle())),
            TextButton.icon(
                onPressed: _busy ? null : () => _add(provider),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add account'))
          ]),
          if (accounts.isEmpty)
            Text('No accounts added', style: TS.label(AppColors.fg2)),
          for (var i = 0; i < accounts.length; i++) _row(provider, accounts, i),
        ]));
  }

  Widget _row(String provider, List<Account> accounts, int index) {
    final account = accounts[index];
    final limited = account.limitedUntil;
    final limitedLabel = limited == null ? null : rateResetLabel(limited);
    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(account.label.isEmpty ? account.id : account.label,
                    style: TS.label(AppColors.fg1))),
            if (account.active)
              Text('In use', style: TS.label(AppColors.accent))
          ]),
          if (account.usage?.primary != null)
            _meter('5h', account.usage!.primary!),
          if (account.usage?.secondary != null)
            _meter('Weekly', account.usage!.secondary!),
          if (limitedLabel != null)
            Text('Limited until $limitedLabel',
                style: TS.label(AppColors.danger)),
          Row(children: [
            TextButton(
                onPressed: _busy ? null : () => _rename(provider, account),
                child: const Text('Rename')),
            IconButton(
                onPressed: _busy || index == 0
                    ? null
                    : () => _move(provider, accounts, index, -1),
                icon: const Icon(Icons.arrow_upward, size: 18)),
            IconButton(
                onPressed: _busy || index == accounts.length - 1
                    ? null
                    : () => _move(provider, accounts, index, 1),
                icon: const Icon(Icons.arrow_downward, size: 18)),
            if (!(provider == 'claude-code' && account.id == 'main'))
              IconButton(
                  onPressed: _busy ? null : () => _remove(provider, account),
                  icon: const Icon(Icons.delete_outline, size: 18))
          ]),
        ]));
  }

  Future<void> _move(
      String provider, List<Account> accounts, int index, int delta) async {
    final reordered = [...accounts];
    final item = reordered.removeAt(index);
    reordered.insert(index + delta, item);
    await _mutate(
        () => widget.client.updateAccount(provider,
            order: reordered.map((a) => a.id).toList()),
        provider);
  }

  Widget _meter(String label, RateWindow rate) {
    final percent = rate.usedPercent.clamp(0, 100).toDouble();
    final reset = rateResetLabel(rate.resetsAt);
    return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(children: [
          SizedBox(
              width: 48, child: Text(label, style: TS.label(AppColors.fg2))),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 5,
                      backgroundColor: AppColors.border,
                      color: percent >= 85
                          ? AppColors.danger
                          : AppColors.accent))),
          const SizedBox(width: 8),
          Text('${percent.round()}%', style: TS.label(AppColors.fg1)),
          if (reset != null)
            Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(reset, style: TS.label(AppColors.fg2)))
        ]));
  }
}
