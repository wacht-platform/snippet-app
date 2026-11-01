import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diff_counts.dart';
import '../api.dart';
import '../local_service.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart' show parseConnection;

/// Overlay a sidebar-toggle on the welcome/empty states when the sidebar is collapsed.
class ShellWithMenu extends StatelessWidget {
  final VoidCallback? onMenu;
  final Widget child;

  const ShellWithMenu({super.key, required this.onMenu, required this.child});

  @override
  Widget build(BuildContext context) {
    if (onMenu == null) return child;
    return Stack(children: [
      child,
      Positioned(
        top: 6,
        left: 6,
        child: IconBtn(
          'sidebar',
          size: kMobile ? 44 : 38,
          iconSize: kMobile ? 25 : 19,
          tooltip: 'Sidebar',
          onTap: onMenu,
        ),
      ),
    ]);
  }
}

Future<Instance> _defaultConnect(String raw) async {
  final parsed = parseConnection(raw);
  if (parsed == null) {
    throw 'That is not a valid link. Run snippet serve --status on the other computer.';
  }
  final (url, token) = parsed;
  final cfg = await DaemonClient(url, token).getConfig();
  return Instance(
      name: cfg.hostname.isNotEmpty ? cfg.hostname : Uri.parse(url).host,
      url: url,
      token: token);
}

Future<Instance?> _defaultProbe() =>
    localInstance(timeout: const Duration(milliseconds: 900));

class ShellWelcomeView extends StatefulWidget {
  final VoidCallback onAddInstance;
  final ValueChanged<Instance>? onConnected;
  final Future<Instance> Function(String raw) connectRemote;
  final Future<Instance?> Function() probeLocal;
  final Future<InstallResult> Function(
      void Function(InstallStage stage, String detail) onStage) install;
  final bool Function() binaryInstalled;

  const ShellWelcomeView({
    super.key,
    required this.onAddInstance,
    this.onConnected,
    this.connectRemote = _defaultConnect,
    this.probeLocal = _defaultProbe,
    this.install = installLocalService,
    this.binaryInstalled = localBinaryInstalled,
  });

  @override
  State<ShellWelcomeView> createState() => _ShellWelcomeViewState();
}

class _ShellWelcomeViewState extends State<ShellWelcomeView> {
  bool _connecting = false;
  bool _installed = false;
  bool _installing = false;
  InstallStage _stage = InstallStage.download;
  String _detail = '';
  String? _error;
  Instance? _pending;
  final _paste = TextEditingController();
  bool _remoteBusy = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    if (canInstallLocalService) _probeLocal();
  }

  Future<void> _probeLocal() async {
    _installed = widget.binaryInstalled();
    final i = await widget.probeLocal();
    if (!mounted) return;
    if (i != null && widget.onConnected != null) {
      setState(() => _connecting = true);
      widget.onConnected!(i);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _connectRemote(String raw) async {
    if (_remoteBusy || raw.trim().isEmpty) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    try {
      final inst = await widget.connectRemote(raw.trim());
      if (mounted) widget.onConnected?.call(inst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _remoteBusy = false;
          _remoteError =
              '$e'.startsWith('That is not') ? '$e' : 'Could not connect: $e';
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _stage = _installed ? InstallStage.start : InstallStage.download;
      _detail = '';
    });
    final r = await widget.install((s, d) {
      if (mounted) {
        setState(() {
          _stage = s;
          _detail = d;
        });
      }
    });
    if (!mounted) return;
    if (r.instance != null && r.autoStart) {
      widget.onConnected?.call(r.instance!);
    } else if (r.instance != null) {
      setState(() {
        _installing = false;
        _pending = r.instance;
      });
    } else {
      setState(() {
        _installing = false;
        _error = r.error;
      });
    }
  }

  Widget _card({
    required String icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      Container(
        padding: EdgeInsets.all(kMobile ? 18 : 20),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: AppIcon(icon, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: sans(kMobile ? 15.5 : 14.5,
                            weight: W.label, color: AppColors.fg1)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: sans(kMobile ? 13.5 : 12.5,
                            height: 1.45, color: AppColors.fg3)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      );

  Widget _wideButton(String label, String icon, VoidCallback? onTap) =>
      Pressable(
        enabled: onTap != null,
        child: Material(
          color: AppColors.accentFill,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.md),
            child: SizedBox(
              height: kMobile ? 50 : 42,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(icon, size: 16, color: AppColors.accentFg),
                const SizedBox(width: 8),
                Text(label,
                    style: sans(kMobile ? 15 : 13.5,
                        weight: W.label, color: AppColors.accentFg)),
              ]),
            ),
          ),
        ),
      );

  Widget _remoteLink() => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Already running on another computer?  ',
                style: sans(13, color: AppColors.fg3)),
            InkWell(
              onTap: widget.onAddInstance,
              borderRadius: BorderRadius.circular(R.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text('Connect to a remote',
                    style: sans(13, weight: W.label, color: AppColors.accent)),
              ),
            ),
          ],
        ),
      );

  Widget _progress() {
    final stages = [
      if (!_installed) ...[
        (InstallStage.download, 'Download snippet'),
        (InstallStage.install, 'Install'),
      ],
      (InstallStage.start, 'Start the service'),
      (InstallStage.connect, 'Connect'),
    ];
    return Column(children: [
      for (final (s, label) in stages)
        _StageRow(
          label: label,
          detail: s == _stage ? _detail : '',
          state: s.index < _stage.index
              ? _StageState.done
              : s == _stage
                  ? _StageState.active
                  : _StageState.pending,
        ),
    ]);
  }

  List<Widget> _localCard({bool withRemoteLink = true}) {
    final title = _connecting
        ? 'Found it on this computer'
        : _installing
            ? 'Setting up on this computer'
            : _installed
                ? 'Installed on this computer'
                : 'Run it on this computer';
    final subtitle = _connecting
        ? 'The service is already running. Connecting now.'
        : _installing
            ? 'This takes under a minute.'
            : _installed
                ? 'The service is installed but not running.'
                : 'One install, no account. It runs in the background '
                    'and starts automatically with your computer.';
    if (_pending != null) {
      return [
        _card(
          icon: 'server',
          title: 'Running, but not set to start automatically',
          subtitle: 'The service works now, but will stop when this '
              'computer restarts.',
          children: [
            const Text('To make it start automatically, run:'),
            const SizedBox(height: 8),
            const _CommandBox(enableCommand),
            const SizedBox(height: 16),
            _wideButton(
                'Continue', 'check', () => widget.onConnected?.call(_pending!)),
          ],
        ),
      ];
    }
    return [
      _card(
        icon: 'server',
        title: title,
        subtitle: subtitle,
        children: [
          if (_connecting)
            const _StageRow(
                label: 'Connecting to this computer', state: _StageState.active)
          else if (_installing)
            _progress()
          else ...[
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Text(_error!,
                    style: sans(12.5, height: 1.45, color: AppColors.danger)),
              ),
              const SizedBox(height: 12),
            ],
            _wideButton(
              _error != null
                  ? 'Try again'
                  : _installed
                      ? 'Start the service'
                      : 'Install on this computer',
              _error != null
                  ? 'refresh'
                  : _installed
                      ? 'play'
                      : 'download',
              _install,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text('Or run the installer yourself',
                  style: sans(12, color: AppColors.fg4)),
              const SizedBox(height: 6),
              const _CommandBox(installCommand),
            ],
          ],
        ],
      ),
      if (withRemoteLink && !_connecting && !_installing) _remoteLink(),
    ];
  }

  Widget _remotePane() => _card(
        icon: 'globe',
        title: 'Connect to another computer',
        subtitle: 'Link this app to a service already running elsewhere.',
        children: [
          if (!canInstallLocalService) ...[
            Text('1. Install snippet on a Linux or macOS computer',
                style: sans(12.5, color: AppColors.fg2)),
            const SizedBox(height: 6),
            const _CommandBox(installCommand),
            const SizedBox(height: 12),
          ],
          if (canInstallLocalService) ...[
            SelectableText.rich(
              TextSpan(
                  style: sans(12, height: 1.5, color: AppColors.fg3),
                  children: [
                    const TextSpan(text: 'On that computer run '),
                    TextSpan(
                        text: enableCommand,
                        style: mono(11.5, color: AppColors.fg1)),
                    const TextSpan(text: ', then '),
                    TextSpan(
                        text: 'snippet serve --status',
                        style: mono(11.5, color: AppColors.fg1)),
                    const TextSpan(text: ' for the link.'),
                  ]),
            ),
          ] else ...[
            Text('2. Start it and show its link',
                style: sans(12.5, color: AppColors.fg2)),
            const SizedBox(height: 6),
            const _CommandBox(enableCommand),
            const SizedBox(height: 6),
            const _CommandBox('snippet serve --status'),
          ],
          const SizedBox(height: 14),
          AppField(
              controller: _paste,
              mono: true,
              hint: 'Paste the link it prints',
              onSubmitted: _connectRemote),
          if (_remoteError != null) ...[
            const SizedBox(height: 8),
            Text(_remoteError!,
                style: sans(12, height: 1.4, color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          _remoteBusy
              ? Row(children: [
                  Spinner(size: 13, color: AppColors.fg3),
                  const SizedBox(width: 9),
                  Text('Connecting', style: sans(12.5, color: AppColors.fg3)),
                ])
              : _wideButton(
                  'Connect', 'plus', () => _connectRemote(_paste.text)),
        ],
      );

  Widget _desktopPanes() => LayoutBuilder(builder: (context, box) {
        final remote = _remotePane();
        if (!canInstallLocalService) {
          return Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: remote));
        }
        final local = _localCard(withRemoteLink: false).first;
        if (box.maxWidth < 640) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [local, const SizedBox(height: 12), remote]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: local),
            const SizedBox(width: 12),
            Expanded(child: remote),
          ]),
        );
      });

  List<Widget> _manualCard() => [
        _card(
          icon: 'server',
          title: 'Run it on a computer',
          subtitle: kMobile
              ? 'Install snippet on your computer, then connect this phone to it.'
              : 'Install snippet on a Linux or macOS computer, then connect here.',
          children: [
            const _WelcomeStep(
              n: '1',
              title: 'Install',
              command: installCommand,
            ),
            const SizedBox(height: 14),
            const _WelcomeStep(
              n: '2',
              title: 'Start it',
              command: enableCommand,
              note: 'Keeps it running in the background, including after '
                  'you close the terminal or restart.',
            ),
            const SizedBox(height: 14),
            const _WelcomeStep(
              n: '3',
              title: 'Show its link',
              command: 'snippet serve --status',
              note: 'Prints the link and a QR code.',
            ),
            const SizedBox(height: 14),
            _WelcomeStep(
              n: '4',
              title: kMobile
                  ? 'Scan the QR code, or paste the link'
                  : 'Paste the link here',
            ),
            const SizedBox(height: 18),
            _wideButton(kMobile ? 'Scan or paste' : 'Connect',
                kMobile ? 'scan' : 'plus', widget.onAddInstance),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding:
              EdgeInsets.symmetric(horizontal: kMobile ? 20 : 28, vertical: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: kMobile ? 460 : 780),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: MochiIcon(
                        color: const Color(0xFFB9C6FF),
                        size: kMobile ? 56 : 40)),
                const SizedBox(height: 20),
                Text(
                  'Snippet needs a service',
                  textAlign: TextAlign.center,
                  style: display(kMobile ? 26 : 24),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'It does its work in a small service that runs in the '
                    'background. This app is the window onto it.',
                    textAlign: TextAlign.center,
                    style: sans(kMobile ? 14.5 : 13.5,
                        height: 1.5, color: AppColors.fg3),
                  ),
                ),
                SizedBox(height: kMobile ? 26 : 22),
                if (kMobile) ..._manualCard() else _desktopPanes(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _StageState { done, active, pending }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state, this.detail = ''});
  final String label;
  final String detail;
  final _StageState state;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lead = switch (state) {
      _StageState.done => AppIcon('check', size: 16, color: AppColors.ok),
      _StageState.active => SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.accent)),
      _StageState.pending => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border2, width: 1.5),
          )),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 22, height: 20, child: Center(child: lead)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: sans(13.5,
                      color: state == _StageState.pending
                          ? AppColors.fg4
                          : AppColors.fg1)),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: AppColors.fg3)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CommandBox extends StatelessWidget {
  const _CommandBox(this.command);
  final String command;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Expanded(
            child: SelectableText(command,
                style: mono(kMobile ? 12 : 11.5, color: AppColors.fg1)),
          ),
          IconBtn('copy', size: 30, iconSize: 13, tooltip: 'Copy', onTap: () {
            Clipboard.setData(ClipboardData(text: command));
            toast(context, 'Copied');
          }),
        ]),
      );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep(
      {required this.n, required this.title, this.command, this.note});
  final String n;
  final String title;
  final String? command;
  final String? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(n, style: sans(12, weight: W.label, color: AppColors.fg2)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(title,
                  style: sans(kMobile ? 14.5 : 13, color: AppColors.fg1)),
            ),
            if (command != null) ...[
              const SizedBox(height: 8),
              _CommandBox(command!),
            ],
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: sans(12, height: 1.4, color: AppColors.fg4)),
            ],
          ],
        ),
      ),
    ]);
  }
}

class ShellRecentPlaceholder extends StatelessWidget {
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final void Function(String id, String title, String? profile) onOpenSession;

  const ShellRecentPlaceholder({
    super.key,
    required this.sessions,
    required this.sessionsLoading,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final list = (sessions ?? const <SessionInfo>[]).take(8).toList();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              Text('Recent sessions', style: display(kMobile ? 24 : 20)),
              const SizedBox(height: 6),
              Text(
                'Pick up where you left off, or start a new chat from Browse.',
                style: sans(12, height: 1.4, color: AppColors.fg3),
              ),
              const SizedBox(height: 18),
              if (sessionsLoading && sessions == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Spinner(size: 20, color: AppColors.fg3),
                  ),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No sessions yet.',
                    style: TS.meta(),
                  ),
                )
              else
                ...list.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => onOpenSession(s.id, s.title, s.profile),
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title.isEmpty ? '(untitled)' : s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg1),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                lastPathSegment(s.projectFolder,
                                    ifEmpty: s.projectFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(10, color: AppColors.fg3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              relativeTime(s.lastActive),
                              style: mono(10, color: AppColors.fg3),
                            ),
                            DiffCounts(s, size: 10.5),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
