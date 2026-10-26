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

  void _selectKey(String? key) {
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
    if (_addProvider != null) return _addPage(_addProvider!);
    final pending = _pendingSignIn;
    if (pending != null) return _signInPage(pending);
    final key = _selectedKey;
    if (key != null) {
      for (final p in _providers) {
        final list = _accounts[p] ?? const <Account>[];
        for (var i = 0; i < list.length; i++) {
          if ('$p/${list[i].id}' == key) return _accountPage(p, list, i);
        }
      }
    }
    return SettingsColumn(children: [
      const SettingsHeader(
        title: 'Accounts',
        subtitle: 'Signed-in providers and their usage limits.',
      ),
      const SizedBox(height: S.s8),
      for (final provider in _providers)
        SettingsGroup(
          header: _title(provider),
          children: [
            for (final account in _accounts[provider] ?? const <Account>[])
              _listRow(provider, account),
            SettingsRow(
              label: 'Add account',
              leading: AppIcon('plus', size: 14, color: AppColors.fg3),
              onTap: _busy ? null : () => _startAdd(provider),
            ),
          ],
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
            'When an account reaches its 5-hour or weekly limit, Snippet moves to the next one in this order.',
            style: sans(12, height: 1.5, color: AppColors.fg4)),
      ),
    ]);
  }

  Widget _listRow(String provider, Account account) {
    final name = account.label.isEmpty ? account.id : account.label;
    final usage = account.usage;
    final parts = <String>[
      if (usage?.primary != null)
        '${limitWindowLabel(usage!.primary!)} ${usage.primary!.usedPercent.clamp(0, 100).round()}%',
      if (usage?.secondary != null)
        '${limitWindowLabel(usage!.secondary!)} ${usage.secondary!.usedPercent.clamp(0, 100).round()}%',
    ];
    return SettingsRow(
      label: name,
      sub: parts.isEmpty ? null : parts.join('  ·  '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (account.limitedUntil != null) ...[
          const Tag('Limit reached', tone: Tone.danger),
          const SizedBox(width: S.s8),
        ],
        if (account.active) const Tag('In use', tone: Tone.accent),
      ]),
      chevron: true,
      onTap: () => _selectKey('$provider/${account.id}'),
    );
  }

  Widget _backTo(String label, VoidCallback onTap) =>
      SettingsBack(label, onTap: onTap);

  Widget _addPage(String provider) {
    final claude = provider == 'claude-code';
    return SettingsColumn(children: [
      SettingsHeader(
        back: _backTo('Accounts', _cancelAdd),
        title: 'Add ${_title(provider)} account',
        subtitle: _footer(provider),
        actions: [
          Btn(
              claude
                  ? (_busy ? 'Adding…' : 'Add account')
                  : (_busy ? 'Starting…' : 'Sign in'),
              small: true,
              disabled: _busy,
              onTap: _submitAdd),
        ],
      ),
      const SizedBox(height: S.s8),
      SettingsGroup(
        footer: _addError,
        children: [
          if (claude)
            SettingsRow(
              label: 'Token',
              sub: 'Paste the token from claude setup-token.',
              trailing: SettingsField(
                  controller: _token,
                  hint: 'sk-ant-…',
                  mono: true,
                  obscure: true,
                  width: 260),
            ),
          SettingsRow(
            label: 'Name',
            sub: 'Optional. Shown in the account list.',
            trailing: SettingsField(
                controller: _label, hint: 'Work, Personal…', width: 260),
          ),
        ],
      ),
    ]);
  }

  Widget _signInPage(
      ({String provider, String id, Map<String, dynamic> result}) pending) {
    final uri = Uri.tryParse('${pending.result['verification_uri'] ?? ''}');
    return SettingsColumn(children: [
      SettingsHeader(
        back: _backTo('Accounts', () => setState(() => _pendingSignIn = null)),
        title: 'Finish sign-in',
        subtitle: '${_title(pending.provider)} · waiting for the sign-in page',
        actions: [
          if (uri != null)
            Btn('Open sign-in page',
                small: true,
                onTap: () =>
                    launchUrl(uri, mode: LaunchMode.externalApplication)),
        ],
      ),
      const SizedBox(height: S.s8),
      SettingsGroup(
        footer: 'Snippet picks the account up once you finish.',
        children: [
          SettingsRow(
            label: 'Code',
            sub: 'Enter this code on the sign-in page.',
            trailing: SelectableText('${pending.result['user_code'] ?? ''}',
                style: mono(16, color: AppColors.fg1)),
          ),
        ],
      ),
    ]);
  }

  Widget _accountPage(String provider, List<Account> accounts, int index) {
    final account = accounts[index];
    final name = account.label.isEmpty ? account.id : account.label;
    final canRemove = !(provider == 'claude-code' && account.id == 'main');
    final limited = account.limitedUntil;
    final limitedLabel = limited == null ? null : rateResetLabel(limited);
    final usage = account.usage;
    return SettingsColumn(children: [
      SettingsHeader(
        back: _backTo('Accounts', () => _selectKey(null)),
        title: name,
        subtitle: _title(provider),
        actions: [
          if (index > 0)
            IconBtn('chevron-up',
                size: 28,
                iconSize: 15,
                tooltip: 'Move up',
                onTap: _busy ? null : () => _move(provider, accounts, index, -1)),
          if (index < accounts.length - 1)
            IconBtn('chevron-down',
                size: 28,
                iconSize: 15,
                tooltip: 'Move down',
                onTap: _busy ? null : () => _move(provider, accounts, index, 1)),
        ],
      ),
      const SizedBox(height: S.s8),
      SettingsGroup(children: [
        SettingsRow(
          label: 'Name',
          trailing: _renaming
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  SettingsField(controller: _nameField, width: 200),
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
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(name, style: sans(13, color: AppColors.fg2)),
                  const SizedBox(width: S.s12),
                  Btn('Rename',
                      variant: BtnVariant.surface,
                      small: true,
                      onTap: () {
                        _nameField.text = account.label;
                        setState(() => _renaming = true);
                      }),
                ]),
        ),
        SettingsRow(
          label: 'Status',
          sub: limitedLabel == null ? null : 'Limit reached, $limitedLabel',
          trailing: Tag(account.active ? 'In use' : 'Standby',
              tone: account.active ? Tone.accent : Tone.neutral),
        ),
        if (usage?.primary != null || usage?.secondary != null)
          SettingsRow(
            label: 'Usage',
            labelWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Usage', style: sans(13, color: AppColors.fg1)),
                  if (usage?.primary != null)
                    _meter(limitWindowLabel(usage!.primary!), usage.primary!),
                  if (usage?.secondary != null)
                    _meter(limitWindowLabel(usage!.secondary!), usage.secondary!),
                ]),
          ),
        SettingsRow(
          label: 'Identifier',
          trailing: Text(account.id, style: mono(12.5, color: AppColors.fg2)),
        ),
      ]),
      if (canRemove)
        SettingsGroup(children: [
          SettingsRow(
            label: 'Remove account',
            danger: true,
            onTap: _busy ? null : () => _remove(provider, account),
          ),
        ]),
    ]);
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
                  child: Text('Limit reached, $limitedLabel',
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
    if (!kMobile) {
      if (_loading && _accounts.isEmpty) {
        body = const SettingsColumn(children: [
          SettingsHeader(
            title: 'Accounts',
            subtitle: 'Signed-in providers and their usage limits.',
          ),
          SizedBox(height: S.s8),
          SettingsGroup(children: [SettingsRow(label: 'Loading accounts…')]),
        ]);
      } else if (_error != null && _accounts.isEmpty) {
        body = SettingsColumn(children: [
          const SettingsHeader(
            title: 'Accounts',
            subtitle: 'Signed-in providers and their usage limits.',
          ),
          const SizedBox(height: S.s8),
          SettingsGroup(children: [
            SettingsRow(
              label: "Couldn't load accounts",
              sub: '$_error',
              danger: true,
              trailing: Btn('Retry',
                  small: true, variant: BtnVariant.secondary, onTap: _load),
            ),
          ]),
        ]);
      } else {
        body = _desktop();
      }
    } else if (_loading) {
      body = const ListSkeleton();
    } else if (_error != null && _accounts.isEmpty) {
      body = EmptyState(
        icon: 'alert-triangle',
        title: "Couldn't load accounts",
        body: '$_error',
        action: Btn('Retry', small: true, onTap: _load),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: _groups(),
      );
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
