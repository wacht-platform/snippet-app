import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../desktop_layout.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../settings_form.dart';
import '../widgets.dart';
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
  String? _selectedKey;
  String? _addProvider;
  bool _renaming = false;
  ({String provider, String id, Map<String, dynamic> result})? _pendingSignIn;
  final _nameField = TextEditingController();
  final _token = TextEditingController();
  final _label = TextEditingController();
  String? _addError;

  static const _providers = ['chatgpt', 'xai', 'claude-code'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nameField.dispose();
    _token.dispose();
    _label.dispose();
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

  void _message(String text) => toast(context, text, danger: true);

  Future<void> _add(String provider) async {
    final claude = provider == 'claude-code';
    String? token;
    if (claude) {
      token = await promptText(context,
          title: 'Add Claude Code account',
          hint: 'Token from claude setup-token',
          saveLabel: 'Next');
      if (token == null || token.isEmpty || !mounted) return;
    }
    final label = await promptText(context,
        title: 'Name this account', hint: 'Optional', saveLabel: 'Add');
    if (label == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result =
          await widget.client.addAccount(provider, label: label, token: token);
      if (claude) {
        await _load();
        return;
      }
      final id = result['id'] as String?;
      if (id == null || !mounted) return;
      await _signIn(provider, id, result);
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchSignIn(String provider, String id) {
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
          if (mounted) {
            setState(() {
              _accounts = accounts;
              _pendingSignIn = null;
              _selectedKey = '$provider/$id';
            });
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _signIn(
      String provider, String id, Map<String, dynamic> result) async {
    final uri = Uri.tryParse('${result['verification_uri'] ?? ''}');
    _watchSignIn(provider, id);
    await showAppSheet<void>(context,
        title: 'Finish sign-in',
        child: Padding(
          padding: EdgeInsets.fromLTRB(kMobile ? 4 : 0, 4, kMobile ? 4 : 0, 8),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enter this code on the sign-in page.',
                    style: sans(kMobile ? 14 : 13, color: AppColors.fg2)),
                const SizedBox(height: 12),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(10)),
                  child: SelectableText('${result['user_code'] ?? ''}',
                      style: mono(20, color: AppColors.fg1)),
                ),
                const SizedBox(height: 16),
                if (uri != null)
                  Btn('Open sign-in page',
                      full: true,
                      onTap: () =>
                          launchUrl(uri, mode: LaunchMode.externalApplication)),
                const SizedBox(height: 8),
                Btn('Done',
                    full: true,
                    variant: BtnVariant.secondary,
                    onTap: () => Navigator.pop(context)),
              ]),
        ));
  }

  Future<void> _rename(String provider, Account account) async {
    final label = await promptText(context,
        title: 'Rename account', initial: account.label);
    if (label != null && label.isNotEmpty) {
      await _mutate(
          () => widget.client
              .updateAccount(provider, id: account.id, label: label),
          provider);
    }
  }

  Future<void> _remove(String provider, Account account) async {
    final yes = await confirmAction(context,
        title: 'Remove account?',
        body:
            'Remove ${account.label.isEmpty ? account.id : account.label} from ${_title(provider)}? Snippet will stop switching to it.',
        confirmLabel: 'Remove');
    if (yes) {
      await _mutate(
          () => widget.client.removeAccount(provider, account.id), provider);
    }
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

  String _title(String provider) => switch (provider) {
        'chatgpt' => 'ChatGPT',
        'xai' => 'xAI / SuperGrok',
        _ => 'Claude Code'
      };

  String _footer(String provider) => switch (provider) {
        'chatgpt' => 'Sign in with another ChatGPT subscription.',
        'xai' => 'Sign in with another SuperGrok subscription.',
        _ => 'Run claude setup-token on a machine signed in to the other '
            'subscription and paste the token.'
      };

  List<Widget> _groups() => [
        const SettingsNote(
            'When an account reaches its 5-hour or weekly limit, Snippet '
            'moves to the next one in this order.'),
        const SizedBox(height: 18),
        for (final provider in ['chatgpt', 'xai', 'claude-code'])
          SettingsGroup(
            header: _title(provider),
            footer: _footer(provider),
            children: [
              for (var i = 0; i < (_accounts[provider] ?? const <Account>[]).length; i++)
                _row(provider, _accounts[provider]!, i),
              SettingsRow(
                label: 'Add account',
                leading: AppIcon('plus', size: 16, color: AppColors.fg3),
                onTap: _busy ? null : () => _add(provider),
              ),
            ],
          ),
      ];

  ({String provider, List<Account> list, int index})? _selectedAccount() {
    final all = [
      for (final p in _providers)
        for (var i = 0; i < (_accounts[p] ?? const <Account>[]).length; i++)
          (provider: p, list: _accounts[p]!, index: i),
    ];
    if (all.isEmpty) return null;
    return all
            .where((e) => '${e.provider}/${e.list[e.index].id}' == _selectedKey)
            .firstOrNull ??
        all.first;
  }

  void _selectKey(String key) {
    setState(() {
      _selectedKey = key;
      _renaming = false;
      _addProvider = null;
      _pendingSignIn = null;
    });
  }

  void _startAdd(String provider) {
    _token.clear();
    _label.clear();
    setState(() {
      _addProvider = provider;
      _addError = null;
      _pendingSignIn = null;
    });
  }

  void _cancelAdd() => setState(() {
        _addProvider = null;
        _addError = null;
      });

  Future<void> _submitAdd() async {
    final provider = _addProvider;
    if (provider == null || _busy) return;
    final claude = provider == 'claude-code';
    final token = _token.text.trim();
    if (claude && token.isEmpty) {
      setState(() => _addError = 'Paste the token from claude setup-token.');
      return;
    }
    setState(() {
      _busy = true;
      _addError = null;
    });
    try {
      final result = await widget.client.addAccount(provider,
          label: _label.text.trim(), token: claude ? token : null);
      if (!mounted) return;
      if (claude) {
        setState(() => _addProvider = null);
        await _load();
        return;
      }
      final id = result['id'] as String?;
      setState(() {
        _addProvider = null;
        if (id != null) {
          _pendingSignIn = (provider: provider, id: id, result: result);
        }
      });
      if (id != null) _watchSignIn(provider, id);
    } catch (e) {
      if (mounted) setState(() => _addError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveName(String provider, Account account) async {
    final label = _nameField.text.trim();
    setState(() => _renaming = false);
    if (label.isEmpty || label == account.label) return;
    await _mutate(
        () => widget.client.updateAccount(provider, id: account.id, label: label),
        provider);
  }

  Widget _desktop() {
    final sel = _selectedAccount();
    final currentKey = sel == null ? null : '${sel.provider}/${sel.list[sel.index].id}';
    return MasterDetail(
      master: MasterPane(
        title: 'Accounts',
        children: [
          for (final provider in _providers) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s12, S.s16, S.s12, S.s4),
              child: Text(_title(provider),
                  style: sans(12, weight: W.label, color: AppColors.fg3)),
            ),
            for (final account in _accounts[provider] ?? const <Account>[])
              ListRow(
                title: account.label.isEmpty ? account.id : account.label,
                subtitle: account.active ? 'In use' : null,
                selected: '$provider/${account.id}' == currentKey,
                onTap: () => _selectKey('$provider/${account.id}'),
                trailing: account.limitedUntil == null
                    ? null
                    : const Tag('Limit reached', tone: Tone.danger),
              ),
            ListRow(
              title: 'Add account',
              leading: AppIcon('plus', size: 16, color: AppColors.fg3),
              onTap: _busy ? null : () => _startAdd(provider),
            ),
          ],
        ],
      ),
      detail: _desktopDetail(sel),
    );
  }

  Widget _desktopDetail(({String provider, List<Account> list, int index})? sel) {
    final addProvider = _addProvider;
    if (addProvider != null) return _addDetail(addProvider);
    final pending = _pendingSignIn;
    if (pending != null) return _signInDetail(pending);
    if (sel == null) return const DetailEmpty('No accounts yet.');
    return _accountDetail(sel.provider, sel.list, sel.index);
  }

  Widget _addDetail(String provider) {
    final claude = provider == 'claude-code';
    return DetailPane(
      key: ValueKey('add-$provider'),
      title: 'Add ${_title(provider)} account',
      subtitle: _footer(provider),
      actions: [
        Btn('Cancel',
            variant: BtnVariant.surface,
            small: true,
            disabled: _busy,
            onTap: _cancelAdd),
        Btn(claude ? (_busy ? 'Adding…' : 'Add account') : (_busy ? 'Starting…' : 'Sign in'),
            small: true,
            disabled: _busy,
            onTap: _submitAdd),
      ],
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (claude)
              DesktopFormRow(
                label: 'Token',
                description: 'Paste the token from claude setup-token.',
                control: SettingsField(
                    controller: _token,
                    hint: 'sk-ant-…',
                    mono: true,
                    obscure: true,
                    width: 260),
              ),
            DesktopFormRow(
              label: 'Name',
              description: 'Optional. Shown in the account list.',
              divider: _addError != null,
              control: SettingsField(
                  controller: _label, hint: 'Work, Personal…', width: 260),
            ),
            if (_addError != null)
              Padding(
                padding: const EdgeInsets.only(top: S.s12),
                child: Text(_addError!,
                    style: sans(12.5, color: AppColors.danger)),
              ),
          ]),
    );
  }

  Widget _signInDetail(
      ({String provider, String id, Map<String, dynamic> result}) pending) {
    final uri = Uri.tryParse('${pending.result['verification_uri'] ?? ''}');
    return DetailPane(
      key: ValueKey('sign-in-${pending.id}'),
      title: 'Finish sign-in',
      subtitle: '${_title(pending.provider)} · waiting for the sign-in page',
      actions: [
        Btn('Done',
            variant: BtnVariant.surface,
            small: true,
            onTap: () => setState(() => _pendingSignIn = null)),
      ],
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopFormRow(
              label: 'Code',
              description: 'Enter this code on the sign-in page.',
              control: SelectableText('${pending.result['user_code'] ?? ''}',
                  style: mono(16, color: AppColors.fg1)),
            ),
            DesktopFormRow(
              label: 'Sign-in page',
              description: 'Snippet picks the account up once you finish.',
              divider: false,
              control: uri == null
                  ? Text('Not available',
                      style: sans(13, color: AppColors.fg3))
                  : Btn('Open sign-in page',
                      small: true,
                      onTap: () => launchUrl(uri,
                          mode: LaunchMode.externalApplication)),
            ),
          ]),
    );
  }

  Widget _accountDetail(String provider, List<Account> accounts, int index) {
    final account = accounts[index];
    final name = account.label.isEmpty ? account.id : account.label;
    final canRemove = !(provider == 'claude-code' && account.id == 'main');
    final limited = account.limitedUntil;
    final limitedLabel = limited == null ? null : rateResetLabel(limited);
    final usage = account.usage;
    return DetailPane(
      key: ValueKey('account-$provider/${account.id}'),
      title: name,
      subtitle: _title(provider),
      actions: [
        if (index > 0)
          IconBtn('chevron-up',
              size: 32,
              iconSize: 16,
              tooltip: 'Move up',
              onTap: _busy
                  ? null
                  : () => _move(provider, accounts, index, -1)),
        if (index < accounts.length - 1)
          IconBtn('chevron-down',
              size: 32,
              iconSize: 16,
              tooltip: 'Move down',
              onTap: _busy
                  ? null
                  : () => _move(provider, accounts, index, 1)),
        if (!_renaming)
          IconBtn('edit',
              size: 32,
              iconSize: 16,
              tooltip: 'Rename',
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _nameField.text = account.label;
                        _renaming = true;
                      })),
        if (canRemove)
          Btn('Remove',
              variant: BtnVariant.danger,
              small: true,
              icon: 'trash',
              disabled: _busy,
              onTap: () => _remove(provider, account)),
      ],
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopFormRow(
              label: 'Name',
              control: _renaming
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      SettingsField(
                          controller: _nameField, width: 220),
                      const SizedBox(width: S.s8),
                      Btn('Save',
                          small: true,
                          disabled: _busy,
                          onTap: () => _saveName(provider, account)),
                      const SizedBox(width: S.s8),
                      Btn('Cancel',
                          variant: BtnVariant.surface,
                          small: true,
                          onTap: () => setState(() => _renaming = false)),
                    ])
                  : Text(name, style: sans(13, color: AppColors.fg1)),
            ),
            DesktopFormRow(
              label: 'Status',
              control: Row(mainAxisSize: MainAxisSize.min, children: [
                Tag(account.active ? 'In use' : 'Standby',
                    tone: account.active ? Tone.accent : Tone.neutral),
                if (limitedLabel != null) ...[
                  const SizedBox(width: S.s8),
                  Text('Limit reached, resets $limitedLabel',
                      style: sans(12.5, color: AppColors.danger)),
                ],
              ]),
            ),
            if (usage?.primary != null || usage?.secondary != null)
              DesktopFormRow(
                label: 'Usage',
                control: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (usage?.primary != null)
                        _meter(limitWindowLabel(usage!.primary!), usage.primary!),
                      if (usage?.secondary != null)
                        _meter(limitWindowLabel(usage!.secondary!),
                            usage.secondary!),
                    ]),
              ),
            DesktopFormRow(
              label: 'Identifier',
              divider: false,
              control: Text(account.id,
                  style: mono(12.5, color: AppColors.fg2)),
            ),
          ]),
    );
  }

  Widget _row(String provider, List<Account> accounts, int index) {
    final account = accounts[index];
    final name = account.label.isEmpty ? account.id : account.label;
    final limited = account.limitedUntil;
    final limitedLabel = limited == null ? null : rateResetLabel(limited);
    final usage = account.usage;
    final canRemove = !(provider == 'claude-code' && account.id == 'main');
    return SettingsRow(
      label: name,
      labelWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 15 : 13, color: AppColors.fg1))),
              if (account.active) ...[
                const SizedBox(width: 8),
                Text('In use', style: sans(12, color: AppColors.accent)),
              ],
            ]),
            if (limitedLabel != null)
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Limit reached, resets $limitedLabel',
                      style: sans(12.5, color: AppColors.danger))),
            if (usage?.primary != null) _meter(limitWindowLabel(usage!.primary!), usage.primary!),
            if (usage?.secondary != null) _meter(limitWindowLabel(usage!.secondary!), usage.secondary!),
          ]),
      trailing: Builder(
          builder: (anchor) => IconBtn('more-horizontal',
              size: kMobile ? 40 : 30,
              iconSize: 17,
              tooltip: 'Account actions',
              onTap: _busy
                  ? null
                  : () async {
                      final choice = await showAppMenu<String>(context,
                          anchor: anchor,
                          minWidth: 180,
                          items: [
                            if (index > 0)
                              appMenuItem(
                                  value: 'up',
                                  label: 'Move up',
                                  icon: 'chevron-up'),
                            if (index < accounts.length - 1)
                              appMenuItem(
                                  value: 'down',
                                  label: 'Move down',
                                  icon: 'chevron-down'),
                            appMenuItem(
                                value: 'rename',
                                label: 'Rename',
                                icon: 'edit'),
                            if (canRemove)
                              appMenuItem(
                                  value: 'remove',
                                  label: 'Remove',
                                  icon: 'trash',
                                  danger: true),
                          ]);
                      switch (choice) {
                        case 'up':
                          await _move(provider, accounts, index, -1);
                        case 'down':
                          await _move(provider, accounts, index, 1);
                        case 'rename':
                          await _rename(provider, account);
                        case 'remove':
                          await _remove(provider, account);
                      }
                    })),
    );
  }

  Widget _meter(String label, RateWindow rate) {
    final percent = rate.usedPercent.clamp(0, 100).toDouble();
    final reset = rateResetLabel(rate.resetsAt)?.split(' · ').first;
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(
              width: 40, child: Text(label, style: sans(12, color: AppColors.fg4))),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 4,
                      backgroundColor: AppColors.surface3,
                      color: percent >= 85
                          ? AppColors.danger
                          : AppColors.accent))),
          const SizedBox(width: 8),
          SizedBox(
              width: 34,
              child: Text('${percent.round()}%',
                  textAlign: TextAlign.right,
                  style: sans(12, color: AppColors.fg2))),
          SizedBox(
              width: kMobile ? 104 : 120,
              child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(reset ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg4))))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const ListSkeleton();
    } else if (_error != null && _accounts.isEmpty) {
      body = EmptyState(
        icon: 'alert-triangle',
        title: "Couldn't load accounts",
        body: '$_error',
        action: Btn('Retry', small: true, onTap: _load),
      );
    } else if (kMobile) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: _groups(),
      );
    } else {
      body = _desktop();
    }
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Accounts', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return body;
  }
}
