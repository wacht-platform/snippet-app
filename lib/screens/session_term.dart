part of 'session.dart';

class _StatMeta extends StatelessWidget {
  final String icon, label, tone;
  const _StatMeta(
      {required this.icon, required this.label, this.tone = 'default'});
  @override
  Widget build(BuildContext context) {
    final c = tone == 'accent'
        ? AppColors.accent
        : tone == 'run'
            ? AppColors.run
            : AppColors.fg2;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(icon, size: 14, color: tone == 'default' ? AppColors.fg4 : c),
      const SizedBox(width: 6),
      Text(label, style: mono(12, color: c)),
    ]);
  }
}

String _activityElapsed(String? startedAt, DateTime fallback) {
  final parsed = DateTime.tryParse(startedAt ?? '');
  final start = parsed?.toLocal() ?? fallback;
  final d = DateTime.now().difference(start);
  final secs = d.inSeconds.clamp(0, 24 * 3600);
  final m = secs ~/ 60;
  final s = secs % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

class _CompactingStatus extends StatefulWidget {
  final String? startedAt;
  final String? detail;
  const _CompactingStatus({this.startedAt, this.detail});
  @override
  State<_CompactingStatus> createState() => _CompactingStatusState();
}

class _CompactingStatusState extends State<_CompactingStatus> {
  late final DateTime _mountedAt = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed => _activityElapsed(widget.startedAt, _mountedAt);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final detail = widget.detail?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
                width: 22,
                child: Center(child: WorkingDots(color: AppColors.accent))),
            const SizedBox(width: 8),
            Expanded(
              child: Shimmer(
                color: AppColors.accent,
                child: Text('Compacting context…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 8),
            Text(_elapsed,
                style: sans(12, color: AppColors.fg4, tabular: true)),
          ]),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(detail,
                  style: sans(13, height: 1.4, color: AppColors.fg3)),
            ),
        ],
      ),
    );
  }
}

class _ChurningStatus extends StatefulWidget {
  final String? startedAt;
  final String thinking;
  const _ChurningStatus({this.startedAt, this.thinking = ''});
  @override
  State<_ChurningStatus> createState() => _ChurningStatusState();
}

class _ChurningStatusState extends State<_ChurningStatus> {
  static const _verbs = [
    'Churning',
    'Pondering',
    'Rummaging',
    'Noodling',
    'Tinkering',
    'Scheming',
    'Weaving',
    'Sifting',
    'Puttering',
    'Brewing',
    'Fiddling',
    'Mulling',
    'Foraging',
    'Juggling',
    'Unraveling',
    'Conjuring',
    'Whittling',
    'Riffling',
    'Plotting',
    'Kneading',
  ];

  late final DateTime _mountedAt = DateTime.now();
  late final math.Random _rng = math.Random();
  Timer? _tick;
  Timer? _swap;
  late String _verb = _verbs[_rng.nextInt(_verbs.length)];
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scheduleSwap();
  }

  void _scheduleSwap() {
    final wait = Duration(milliseconds: 2800 + _rng.nextInt(4200));
    _swap?.cancel();
    _swap = Timer(wait, () {
      if (!mounted) return;
      String next;
      do {
        next = _verbs[_rng.nextInt(_verbs.length)];
      } while (next == _verb && _verbs.length > 1);
      setState(() => _verb = next);
      _scheduleSwap();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _swap?.cancel();
    super.dispose();
  }

  String get _elapsed => _activityElapsed(widget.startedAt, _mountedAt);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final thought = widget.thinking.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                thought.isEmpty ? null : () => setState(() => _open = !_open),
            child: Row(
              children: [
                SizedBox(
                    width: 22,
                    child: Center(child: WorkingDots(color: AppColors.accent))),
                const SizedBox(width: 8),
                Expanded(
                  child: Shimmer(
                    color: AppColors.accent,
                    child: SwapText('$_verb…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_elapsed,
                    style: sans(12, color: AppColors.fg4, tabular: true)),
                if (thought.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  AppIcon(_open ? 'chevron-down' : 'chevron-right',
                      size: 13, color: AppColors.accent.withValues(alpha: 0.7)),
                ],
              ],
            ),
          ),
          if (_open && thought.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ThinkingMarkdown(data: thought),
            ),
        ],
      ),
    );
  }
}

class _ClearScrollTerminal extends Terminal {
  _ClearScrollTerminal() : super(maxLines: 5000);

  @override
  void eraseDisplay() {
    if (!buffer.isAltBuffer) {
      final n = viewHeight;
      for (var i = 0; i < n; i++) {
        buffer.index();
      }
    }
    buffer.eraseDisplay();
    buffer.setCursor(0, 0);
  }
}

class _LiveStreamRow extends StatelessWidget {
  final ValueListenable<_LiveFrame> frame;
  final bool running;
  final bool compacting;
  final String? startedAt;
  final bool hasVisibleAction;
  final String? compactionDetail;

  const _LiveStreamRow({
    super.key,
    required this.frame,
    required this.running,
    required this.compacting,
    required this.startedAt,
    required this.hasVisibleAction,
    required this.compactionDetail,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_LiveFrame>(
      valueListenable: frame,
      builder: (context, value, _) {
        final children = <Widget>[];
        if (value.visible && value.text.trim().isNotEmpty) {
          children.add(Padding(
            key: const ValueKey('live-text'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Bubble(
              mine: false,
              text: value.text.trim(),
              selectable: false,
            ),
          ));
        }
        if (compacting) {
          children.addAll([
            const SizedBox(height: 10),
            _CompactingStatus(
              startedAt: startedAt,
              detail: compactionDetail,
            ),
          ]);
        } else if (running) {
          children.addAll([
            const SizedBox(height: 10),
            _ChurningStatus(
              startedAt: startedAt,
              thinking: hasVisibleAction ? '' : value.thinking,
            ),
          ]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _LiveFrame {
  final String text;
  final String thinking;
  final bool visible;
  const _LiveFrame({this.text = '', this.thinking = '', this.visible = false});
}

class _LiveTerm {
  _LiveTerm(this.id, {required this.title}) : terminal = _ClearScrollTerminal();
  final String id;
  String title;
  final Terminal terminal;
  int cols = 80;
  int rows = 24;
  bool alive = false;
  bool live = false;
}

class TerminalInfo {
  const TerminalInfo({
    required this.id,
    required this.title,
    required this.alive,
    required this.live,
  });

  final String id;
  final String title;
  final bool alive;
  final bool live;
}

class TerminalHost {
  TerminalHost({
    required this.terms,
    required this.focus,
    required this.buildView,
    required void Function(String id) onFocus,
    required void Function() onRequestNew,
    required void Function(String id) onRequestClose,
  })  : _focus = onFocus,
        _new = onRequestNew,
        _close = onRequestClose;

  final List<TerminalInfo> terms;
  final int focus;
  final Widget Function(String id, {required bool mobileKeys}) buildView;

  final void Function(String id) _focus;
  final void Function() _new;
  final void Function(String id) _close;

  void focusTerm(String id) => _focus(id);
  void newTerminal() => _new();
  void closeTerm(String id) => _close(id);

  String? get activeId {
    if (terms.isEmpty) return null;
    final i = focus >= 0 && focus < terms.length ? focus : 0;
    return terms[i].id;
  }

  TerminalInfo? get active {
    final id = activeId;
    if (id == null) return null;
    for (final t in terms) {
      if (t.id == id) return t;
    }
    return null;
  }
}
