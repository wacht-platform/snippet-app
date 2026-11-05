import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../diff_counts.dart';
import '../local_service.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_instance.dart' show parseConnection;
import 'welcome_art.dart';

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
  final Future<bool> Function() probeRunning;
  final Future<InstallResult> Function(
      void Function(InstallStage stage, String detail) onStage) install;
  final bool Function() binaryInstalled;
  final Duration recheck;

  const ShellWelcomeView({
    super.key,
    required this.onAddInstance,
    this.onConnected,
    this.connectRemote = _defaultConnect,
    this.probeLocal = _defaultProbe,
    this.probeRunning = localServiceUp,
    this.install = installLocalService,
    this.binaryInstalled = localBinaryInstalled,
    this.recheck = const Duration(seconds: 3),
  });

  @override
  State<ShellWelcomeView> createState() => _ShellWelcomeViewState();
}

class _ShellWelcomeViewState extends State<ShellWelcomeView>
    with SingleTickerProviderStateMixin {
  Instance? _found;
  bool _runningUnreadable = false;
  bool _installed = false;
  bool _installing = false;
  InstallStage _stage = InstallStage.download;
  String _detail = '';
  String? _error;
  Instance? _pending;
  Timer? _timer;
  int? _hover;
  late final AnimationController _clock;
  final _paste = TextEditingController();
  bool _remoteBusy = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _clock =
        AnimationController(vsync: this, duration: const Duration(seconds: 9));
    _clock.repeat();
    if (!kMobile) {
      _installed = widget.binaryInstalled();
      _probe();
      _timer = Timer.periodic(widget.recheck, (_) => _probe());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_installing || _found != null || _pending != null) return;
    final i = await widget.probeLocal();
    final up = i != null || await widget.probeRunning();
    if (!mounted) return;
    setState(() {
      _found = i;
      _runningUnreadable = i == null && up;
      if (i != null) _timer?.cancel();
    });
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

  Widget _progress() {
    final stages = [
      if (!_installed) ...[
        (InstallStage.download, 'Download'),
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            textAlign: TextAlign.center,
            style: sans(12.5, weight: W.label, color: AppColors.fg1)),
      );

  Text _body(String text) => Text(text,
      textAlign: TextAlign.center,
      style: sans(12, height: 1.5, color: AppColors.fg3));

  Widget _localControls() {
    if (_found != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('Snippet is running here',
              style: sans(12.5, color: AppColors.fg1)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(_found!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg4)),
          ),
        ]),
        const SizedBox(height: 12),
        Btn('Connect',
            small: true, onTap: () => widget.onConnected?.call(_found!)),
      ]);
    }
    if (_pending != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _label('Not set to start automatically'),
        _body('It works now, but stops when this computer restarts. '
            'To fix that, run:'),
        const SizedBox(height: 10),
        const _CommandBox(enableCommand),
        const SizedBox(height: 12),
        Btn('Continue',
            small: true, onTap: () => widget.onConnected?.call(_pending!)),
      ]);
    }
    if (_installing) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _label('Setting up'),
        Align(alignment: Alignment.center, child: _progress()),
      ]);
    }
    if (_runningUnreadable) {
      return _body('Snippet is running here, but this app cannot read its '
          'link. Run snippet serve --status and paste the link on the right.');
    }
    if (!canInstallLocalService) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _body('Run these in a terminal. This screen picks the service up '
            'as soon as it is running.'),
        const SizedBox(height: 10),
        if (!_installed) ...[
          const _CommandBox(installCommand),
          const SizedBox(height: 6),
        ],
        const _CommandBox(enableCommand),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_installed) ...[
        _body('Snippet is installed but not running.'),
        const SizedBox(height: 12),
      ],
      if (_error != null) ...[
        Text(_error!,
            textAlign: TextAlign.center,
            style: sans(11.5, height: 1.45, color: AppColors.danger)),
        const SizedBox(height: 8),
        const _CommandBox(installCommand),
        const SizedBox(height: 12),
      ],
      Btn(
          _error != null
              ? 'Try again'
              : _installed
                  ? 'Start the service'
                  : 'Install',
          small: true,
          icon: _installed ? null : 'download',
          onTap: _install),
    ]);
  }

  Widget _remoteControls() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: AppField(
                  controller: _paste,
                  mono: true,
                  hint: 'https://\u2026?token=\u2026',
                  onSubmitted: _connectRemote)),
          const SizedBox(width: 8),
          Btn('Connect',
              small: true,
              disabled: _remoteBusy,
              onTap: () => _connectRemote(_paste.text)),
        ]),
        const SizedBox(height: 8),
        if (_remoteError != null)
          Text(_remoteError!,
              textAlign: TextAlign.center,
              style: sans(11.5, height: 1.4, color: AppColors.danger))
        else
          SelectableText.rich(
            TextSpan(
                style: sans(11.5, height: 1.5, color: AppColors.fg4),
                children: [
                  const TextSpan(text: 'On that computer: '),
                  TextSpan(
                      text: enableCommand,
                      style: mono(11, color: AppColors.fg3)),
                  const TextSpan(text: ', then '),
                  TextSpan(
                      text: 'snippet serve --status',
                      style: mono(11, color: AppColors.fg3)),
                ]),
            textAlign: TextAlign.center,
          ),
      ]);

  int? get _active {
    if (_hover != null) return _hover;
    if (_installing || _pending != null || _error != null) return 0;
    if (_remoteBusy || _remoteError != null || _paste.text.isNotEmpty) {
      return 1;
    }
    return null;
  }

  Widget _side(int index,
      {required String title,
      required String body,
      required double artHeight,
      required Widget controls}) {
    final active = _active;
    final on = active == index;
    final dim = active != null && !on;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = index),
      onExit: (_) => setState(() {
        if (_hover == index) _hover = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        color: on ? AppColors.surface1 : AppColors.bg,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 380),
          opacity: dim ? 0.55 : 1,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: artHeight,
                    width: double.infinity,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: on ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, h, __) => _artFor(index, h),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              textAlign: TextAlign.center, style: display(18)),
                          const SizedBox(height: 8),
                          Text(body,
                              textAlign: TextAlign.center,
                              style: sans(12.5,
                                  height: 1.55, color: AppColors.fg3)),
                          const SizedBox(height: 22),
                          controls,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _artFor(int index, double h) => index == 0
      ? UnboxArt(time: _clock, hover: h)
      : PlugArt(time: _clock, hover: h);

  Widget _desktop() => LayoutBuilder(builder: (context, box) {
        final stacked = box.maxWidth < 760;
        final artHeight =
            stacked ? 170.0 : (box.maxHeight * 0.5).clamp(190.0, 400.0);
        return _split(box, stacked, artHeight);
      });

  Widget _split(BoxConstraints box, bool stacked, double artHeight) {
    final left = _side(0,
        title: 'On this computer',
        body: 'Install the service here. It runs in the background, starts '
            'with your computer, and your work stays on this machine.',
        artHeight: artHeight,
        controls: _localControls());
    final right = _side(1,
        title: 'On another computer',
        body: 'Already running snippet on a server or another machine? '
            'Paste its link and work with it from here.',
        artHeight: artHeight,
        controls: _remoteControls());
    {
      final active = _active;
      final lf = active == null ? 0.5 : (active == 0 ? 0.56 : 0.44);
      const d = Duration(milliseconds: 420);
      final line = Container(
          width: stacked ? null : 1,
          height: stacked ? 1 : null,
          color: AppColors.border);
      return Stack(children: [
        Positioned.fill(
          child: stacked
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [left, line, right]))
              : Row(children: [
                  AnimatedContainer(
                      key: const ValueKey('welcome-left'),
                      duration: d,
                      curve: Curves.easeOutCubic,
                      width: box.maxWidth * lf,
                      child: left),
                  line,
                  Expanded(child: right),
                ]),
        ),
        Positioned(
          top: 14,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MochiIcon(color: const Color(0xFFB9C6FF), size: 16),
              const SizedBox(width: 8),
              Text('Snippet needs a service',
                  style: sans(12.5, color: AppColors.fg3)),
            ]),
          ),
        ),
      ]);
    }
  }

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

  Widget _phone() => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: 460, minHeight: box.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 200,
                  child: PlugArt(time: _clock, hover: 0.5),
                ),
                const SizedBox(height: 8),
                Text('Connect to your computer',
                    textAlign: TextAlign.center, style: display(24)),
                const SizedBox(height: 10),
                Text(
                  'Snippet does its work in a small service that runs on a '
                  'computer or server. This app is your window onto it.',
                  textAlign: TextAlign.center,
                  style: sans(14.5, height: 1.5, color: AppColors.fg3),
                ),
                const SizedBox(height: 28),
                _wideButton('Scan QR code', 'scan', widget.onAddInstance),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: Container(height: 1, color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or paste its link',
                        style: sans(12.5, color: AppColors.fg4)),
                  ),
                  Expanded(child: Container(height: 1, color: AppColors.border)),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                      child: AppField(
                          controller: _paste,
                          mono: true,
                          hint: 'https://\u2026?token=\u2026',
                          onSubmitted: _connectRemote)),
                  const SizedBox(width: 8),
                  PillBtn('Connect',
                      onTap: _remoteBusy || _paste.text.trim().isEmpty
                          ? null
                          : () => _connectRemote(_paste.text)),
                ]),
                if (_remoteError != null) ...[
                  const SizedBox(height: 10),
                  Text(_remoteError!,
                      textAlign: TextAlign.center,
                      style: sans(12.5, height: 1.4, color: AppColors.danger)),
                ],
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Not running yet? On your computer:',
                          style: sans(13.5,
                              weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 14),
                      const _WelcomeStep(
                          n: '1', title: 'Install', command: installCommand),
                      const SizedBox(height: 14),
                      const _WelcomeStep(
                          n: '2',
                          title: 'Start it',
                          command: enableCommand),
                      const SizedBox(height: 14),
                      const _WelcomeStep(
                        n: '3',
                        title: 'Show its link and QR code',
                        command: 'snippet serve --status',
                        note: 'Prints the link and a QR code to scan.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.bg,
      child: kMobile ? _phone() : _desktop(),
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
      _StageState.done => AppIcon('check', size: 14, color: AppColors.ok),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 18, height: 18, child: Center(child: lead)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: sans(12.5,
                      color: state == _StageState.pending
                          ? AppColors.fg4
                          : AppColors.fg1)),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(10.5, color: AppColors.fg3)),
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
