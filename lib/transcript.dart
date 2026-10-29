// Transcript components: an activity timeline for tool calls (one thin line,
// a node and one sentence per step, a single block for detail), lane cards,
// and styled system rows for watches, goals, and compaction.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mochi.dart';
import 'motion.dart' show Shimmer;
import 'screens/session_coordination_cards.dart' show CardMarkdownBody;
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'tool_views.dart';
import 'transcript_card.dart';
import 'widgets.dart';

double get _sentenceSize => kMobile ? 14 : 13;
double get _objectSize => kMobile ? 13 : 12;

enum _NodeState { ok, failed, running, neutral }

class _Node extends StatefulWidget {
  const _Node(this.state);
  final _NodeState state;

  @override
  State<_Node> createState() => _NodeState2();
}

class _NodeState2 extends State<_Node> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        widget.state == _NodeState.running && !reduceMotion(context);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didUpdateWidget(_Node old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 9.0;
    final (fill, border) = switch (widget.state) {
      _NodeState.ok => (readingBg, AppColors.ok),
      _NodeState.failed => (AppColors.danger, AppColors.danger),
      _NodeState.running => (AppColors.accent, AppColors.accent),
      _NodeState.neutral => (readingBg, AppColors.fg4),
    };
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
    );
    if (widget.state != _NodeState.running) return Center(child: dot);
    return Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: (1 - _c.value) * 0.45,
              child: Container(
                width: size + 8 * _c.value,
                height: size + 8 * _c.value,
                decoration: BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
              ),
            ),
            dot,
          ],
        ),
      ),
    );
  }
}

_NodeState _nodeFor(ToolStep step) {
  if (step.running) return _NodeState.running;
  if (step.failed) return _NodeState.failed;
  final r = step.result;
  if (r is Map && r['status'] == null && r['data'] == null) {
    return _NodeState.neutral;
  }
  return _NodeState.ok;
}

Widget _sentence(String verb, String object) => Text.rich(
      TextSpan(children: [
        TextSpan(
            text: verb,
            style: sans(_sentenceSize, height: 1.4, color: AppColors.fg2)),
        if (object.isNotEmpty)
          TextSpan(
              text: ' $object',
              style: mono(_objectSize, height: 1.4, color: AppColors.fg1)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

class DenseToolRow extends StatefulWidget {
  final String tool;
  final dynamic args;
  final dynamic result; // null while running
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;
  const DenseToolRow(
      {super.key,
      required this.tool,
      this.args,
      this.result,
      this.open,
      this.onOpenChanged});

  bool get pending => result == null;

  @override
  State<DenseToolRow> createState() => _DenseToolRowState();
}

class _DenseToolRowState extends State<DenseToolRow> {
  bool _localOpen = false;

  bool get _open => widget.open ?? _localOpen;

  void _toggle() {
    final next = !_open;
    if (widget.onOpenChanged != null) {
      widget.onOpenChanged!(next);
    } else {
      setState(() => _localOpen = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final step =
        ToolStep(tool: widget.tool, args: widget.args, result: widget.result);
    final canExpand = toolHasDetail(step);
    final (verb, object) = toolSentenceParts(step);
    final changes = fileChanges([step]);
    final added = changes.fold<int>(0, (n, c) => n + c.added);
    final removed = changes.fold<int>(0, (n, c) => n + c.removed);
    final open = _open && canExpand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? _toggle : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: kMobile ? 32 : 26),
            child: Row(children: [
              SizedBox(width: 16, child: _Node(_nodeFor(step))),
              const SizedBox(width: S.s8),
              Flexible(child: _sentence(verb, object)),
              if (added > 0) ...[
                const SizedBox(width: S.s8),
                Text('+$added', style: mono(_objectSize, color: AppColors.ok)),
              ],
              if (removed > 0) ...[
                const SizedBox(width: S.s6),
                Text('−$removed',
                    style: mono(_objectSize, color: AppColors.danger)),
              ],
            ]),
          ),
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 0, 8),
                  child: _StepDetail(step: step),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _StepDetail extends StatefulWidget {
  const _StepDetail({required this.step});
  final ToolStep step;

  @override
  State<_StepDetail> createState() => _StepDetailState();
}

class _StepDetailState extends State<_StepDetail> {
  static const _cap = 240.0;
  final _key = GlobalKey();
  bool _full = false;
  double _height = 0;

  double get _lineHeight => (kMobile ? 12.5 : 12) * 1.45;

  void _measure() {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if ((box.size.height - _height).abs() > 0.5) {
      setState(() => _height = box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final overflow = _height > _cap + 1;
    final tool = toolBaseName(step.tool);
    final countsLines =
        tool == 'bash' || tool == 'read_file' || tool == 'change_files';
    final lines = (_height / _lineHeight).round();
    final more = countsLines ? 'Show all $lines lines' : 'Show all';
    final meta = toolMetaParts(step);
    final copy = toolCopyText(step);
    final metaStyle = mono(kMobile ? 12 : 11.5, color: AppColors.fg3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRect(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: _full ? double.infinity : _cap),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: KeyedSubtree(
                      key: _key,
                      child: safeToolDetailView(context,
                          tool: step.tool,
                          args: step.args,
                          result: step.result),
                    ),
                  ),
                ),
              ),
              if (overflow)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _full = !_full),
                  child: Padding(
                    padding: const EdgeInsets.only(top: S.s8),
                    child: Text(_full ? 'Show less' : more,
                        style: sans(kMobile ? 13 : 12.5,
                            weight: W.label, color: AppColors.fg3)),
                  ),
                ),
            ],
          ),
        ),
        if (meta.isNotEmpty || copy.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.s6, left: 2),
            child: Row(children: [
              if (meta.isNotEmpty) Text(meta.join(' · '), style: metaStyle),
              if (meta.isNotEmpty && copy.isNotEmpty)
                Text(' · ', style: metaStyle),
              if (copy.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: copy));
                    toast(context, 'Copied');
                  },
                  child: Text('Copy',
                      style: metaStyle.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.fg4)),
                ),
            ]),
          ),
      ],
    );
  }
}

/// A run of tool steps hanging off one thin line. Up to [_directLimit] steps
/// show directly; a longer run shows a summary and its last step.
class ToolRun extends StatefulWidget {
  final List<Widget> rows;
  final bool running;
  final bool open;
  final ValueChanged<bool>? onOpenChanged;
  const ToolRun(this.rows,
      {super.key, this.running = false, this.open = false, this.onOpenChanged});
  @override
  State<ToolRun> createState() => _ToolRunState();
}

class _ToolRunState extends State<ToolRun> {
  static const _directLimit = 3;
  bool _localOpen = false;

  bool get _open => widget.onOpenChanged != null ? widget.open : _localOpen;

  void _toggle() {
    if (widget.onOpenChanged != null) {
      widget.onOpenChanged!(!widget.open);
    } else {
      setState(() => _localOpen = !_localOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final rows = widget.rows;
    final steps = [
      for (final r in rows.whereType<DenseToolRow>())
        ToolStep(tool: r.tool, args: r.args, result: r.result),
    ];
    final long = rows.length > _directLimit;
    final open = _open;
    final List<Widget> shown = !long || open ? rows : [rows.last];
    final failures = steps.where((s) => !s.running && s.failed).length;
    final summaryNode = widget.running && steps.any((s) => s.running)
        ? _NodeState.running
        : failures > 0
            ? _NodeState.failed
            : _NodeState.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Stack(children: [
        Positioned(
          left: 7.5,
          top: 14,
          bottom: 14,
          width: 1,
          child: ColoredBox(color: AppColors.border2),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (long)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: kMobile ? 32 : 26),
                child: Row(children: [
                  SizedBox(width: 16, child: _Node(summaryNode)),
                  const SizedBox(width: S.s8),
                  Flexible(
                    child: Text(activitySummary(steps),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(_sentenceSize,
                            height: 1.4, color: AppColors.fg2)),
                  ),
                  if (failures > 0) ...[
                    const SizedBox(width: S.s8),
                    Text('$failures failed',
                        style: sans(_objectSize, color: AppColors.danger)),
                  ],
                  const SizedBox(width: S.s6),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: Motion.fast,
                    child: AppIcon('chevron-right',
                        size: 12, color: AppColors.fg4),
                  ),
                ]),
              ),
            ),
          ...shown,
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Lane notice — the transcript keeps only a compact pointer. Full lane output
// belongs in the dedicated lanes screen.
// ---------------------------------------------------------------------------

class LaneNotice extends StatefulWidget {
  final String title;
  final LaneInfo? Function() live;
  final VoidCallback onOpen;
  final String? summary;

  const LaneNotice({
    super.key,
    required this.title,
    required this.live,
    required this.onOpen,
    this.summary,
  });

  @override
  State<LaneNotice> createState() => _LaneNoticeState();
}

class _LaneNoticeState extends State<LaneNotice> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(LaneInfo? lane) {
    final started = DateTime.tryParse(lane?.startedAt ?? '');
    if (started == null) return 'Running';
    final d = DateTime.now().toUtc().difference(started.toUtc());
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final lane = widget.live();
    final running = lane?.running ?? false;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
    final state = lane?.status ?? '';
    final failed = state == 'failed';
    final paused = state == 'paused';
    final completed = state == 'completed' || state == 'done';
    final summary = widget.summary?.trim().isNotEmpty == true
        ? widget.summary!.trim()
        : lane?.summary?.trim() ?? '';
    final agent = (lane?.agent?.trim().isNotEmpty == true
            ? lane!.agent!.trim()
            : lane?.profile?.trim()) ??
        '';
    final title = widget.title.trim().isNotEmpty
        ? widget.title.trim()
        : lane?.title.trim() ?? '';
    final (String? status, Tone tone) = running
        ? (_elapsed(lane), Tone.accent)
        : failed
            ? ('Failed', Tone.danger)
            : completed
                ? ('Completed', Tone.ok)
                : paused
                    ? ('Paused', Tone.neutral)
                    : lane == null
                        ? (null, Tone.neutral)
                        : (
                            state == 'cancelled' ? 'Cancelled' : 'Queued',
                            Tone.neutral
                          );
    final color = agent.isEmpty ? mochiPalette.first.$2 : mochiColorFor(agent);
    final small = TranscriptCard.metaSize;
    final header = Row(children: [
      running
          ? WorkingMochi(size: 14, color: color)
          : MochiIcon(
              color: failed
                  ? AppColors.danger
                  : completed
                      ? color
                      : AppColors.fg4,
              size: 14),
      const SizedBox(width: S.s6),
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: title.isEmpty ? 'Lane' : title),
            if (agent.isNotEmpty)
              TextSpan(
                  text: '  $agent', style: sans(small, color: AppColors.fg4)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sans(TranscriptCard.titleSize,
              weight: W.label, height: 1.3, color: AppColors.fg1),
        ),
      ),
      if (status != null && status.isNotEmpty) ...[
        const SizedBox(width: S.s8),
        running
            ? Text(status, style: mono(small - 1, color: AppColors.fg3))
            : CardStatus(status, tone: tone),
      ],
    ]);
    Widget? body;
    if (running) {
      body = _LaneActivityLine(lane: lane, size: small);
    } else if (failed && (lane?.error?.trim().isNotEmpty ?? false)) {
      body = Text(lane!.error!.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: sans(small, height: 1.4, color: AppColors.fg3));
    } else if (summary.isNotEmpty) {
      body = CardMarkdownBody(
          body: summary, preview: MarkdownPreview.plain(summary));
    }
    final pad = kMobile
        ? const EdgeInsets.fromLTRB(12, 8, 12, 9)
        : const EdgeInsets.fromLTRB(12, 6, 12, 7);
    return Semantics(
      button: true,
      label: '$title, ${(status ?? '').toLowerCase()}. Open the lane.',
      onTap: widget.onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpen,
            child: Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  if (body != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: S.s2),
                      child: body,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaneActivityLine extends StatelessWidget {
  final LaneInfo? lane;
  final double size;
  const _LaneActivityLine({required this.lane, required this.size});

  @override
  Widget build(BuildContext context) {
    final current = lane?.activity?.trim() ?? '';
    final thinking = lane?.activityKind == 'model' || current.isEmpty;
    String last = '';
    if (thinking) {
      for (final a in (lane?.activityLog ?? const <LaneActivity>[]).reversed) {
        if (a.kind == 'tool_call' && a.text.trim().isNotEmpty) {
          last = a.text.trim();
          break;
        }
      }
    }
    final now = thinking ? 'Thinking' : current;
    final style = sans(size, height: 1.4, color: AppColors.fg2);
    return AnimatedSwitcher(
      duration: Motion.fast,
      layoutBuilder: (cur, prev) => Stack(
          alignment: Alignment.centerLeft,
          children: [...prev, if (cur != null) cur]),
      child: Row(
        key: ValueKey('$now|$last'),
        children: [
          Flexible(
            flex: 0,
            child: Shimmer(
              color: AppColors.fg2,
              child: Text(now,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
          if (last.isNotEmpty)
            Expanded(
              child: Text('  ·  $last',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: AppColors.fg4)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Styled system rows: watches, goals, compaction, generic decisions — each
// recognizable at a glance instead of identical grey notes.
// ---------------------------------------------------------------------------

class SystemRow extends StatelessWidget {
  final String step;
  final String reasoning;
  const SystemRow({super.key, required this.step, required this.reasoning});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change

    // Full-width quiet dividers (match TUI compaction / tool-prune chrome).
    if (step == 'history_compacted') {
      return _SystemDivider(label: 'context compacted');
    }
    if (step == 'idle_memory_save') {
      return _SystemDivider(label: 'saved memory while you were away');
    }
    if (step == 'history_compaction_pass' ||
        step == 'history_compaction_skipped') {
      return const SizedBox.shrink();
    }
    if (step == 'tool_payloads_pruned') {
      final detail = reasoning.trim();
      final label = detail.isEmpty
          ? 'old tool results cleared'
          : 'tools cleared · $detail';
      return _SystemDivider(label: label);
    }

    final isGoal = step == 'goal_set' ||
        step == 'goal_completed' ||
        step == 'goal_paused' ||
        step == 'goal_cancelled';
    // A goal fire is a scheduled instruction — render it like any normal
    // user message bubble instead of a special card. End states stay as
    // quiet one-line notes so the canvas isn't cluttered with chrome.
    if (isGoal) {
      if (step == 'goal_set') {
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          child: Bubble(mine: true, text: reasoning),
        );
      }
      final label = switch (step) {
        'goal_completed' => 'goal completed',
        'goal_paused' => 'goal paused',
        _ => 'goal cancelled',
      };
      // The completion summary (the agent's complete_goal report) is the
      // outcome of the run — show it, not just a bare divider. Other end
      // states stay quiet.
      if (step != 'goal_completed') {
        return _SystemDivider(label: label);
      }
      final detail = reasoning.trim();
      return Padding(
        padding: const EdgeInsets.only(top: S.s4, bottom: S.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SystemDivider(label: label),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.s8),
              child: MarkdownBody(
                data: detail,
                selectable: true,
                styleSheet: markdownStyle(context),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (txt, href, title) =>
                    openMarkdownLink(href, context, txt),
              ),
            ),
        ]),
      );
    }

    switch (step) {
      case 'watch_added':
        final m = RegExp(r'^watching "(.*)" \((.*)\)$', dotAll: true)
            .firstMatch(reasoning.trim());
        return _WatchLine(
          verb: 'Watching',
          subject: m?.group(1) ?? reasoning,
          path: m?.group(2),
        );
      case 'watch_removed':
        final m =
            RegExp(r'^stopped watching "(.*)"$').firstMatch(reasoning.trim());
        return _WatchLine(
          verb: 'Stopped watching',
          subject: m?.group(1) ?? reasoning,
          muted: true,
        );
      case 'file_watch':
        final m = RegExp(r'^"(.*?)" — (.*?) grew: ?(.*)$', dotAll: true)
            .firstMatch(reasoning);
        return _WatchFired(
          subject: m?.group(1) ?? 'Watched file',
          path: m?.group(2) ?? '',
          preview: (m?.group(3) ?? reasoning).trim(),
        );
      case 'interrupted':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: S.s6),
          child: Row(children: [
            SizedBox(
                width: 16,
                child: Center(
                    child: AppIcon('stop', size: 14, color: AppColors.danger))),
            const SizedBox(width: S.s8),
            Text('You stopped the run', style: TS.label(AppColors.danger)),
          ]),
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 16,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(
                  child: AppIcon('activity', size: 14, color: AppColors.fg4)),
            )),
        const SizedBox(width: S.s8),
        Expanded(
          child: Text(reasoning,
              maxLines: 3, overflow: TextOverflow.ellipsis, style: TS.meta()),
        ),
      ]),
    );
  }
}

class _WatchLine extends StatelessWidget {
  const _WatchLine({
    required this.verb,
    required this.subject,
    this.path,
    this.muted = false,
  });

  final String verb;
  final String subject;
  final String? path;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hasPath = path != null && path!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Row(children: [
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: verb,
                  style: TS.ui(muted ? AppColors.fg4 : AppColors.fg2)),
              TextSpan(
                  text: ' $subject',
                  style: TS.ui(muted ? AppColors.fg4 : AppColors.fg3)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasPath && !muted) ...[
          const SizedBox(width: S.s8),
          Flexible(
            child: Text(path!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.meta(AppColors.fg4)),
          ),
        ],
      ]),
    );
  }
}

/// What a watched file's new lines say: the readable lines, and the exit code
/// when the command appended a `__DONE__ exit=N` style sentinel.
({List<String> lines, int? exit}) _readWatchPreview(String preview) {
  final sentinel = RegExp(r'^__[A-Z_]+__(?:\s+exit=(-?\d+))?');
  int? exit;
  final lines = <String>[];
  for (final raw in preview.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final m = sentinel.firstMatch(line.trim());
    if (m != null) {
      if (m.group(1) != null) exit = int.tryParse(m.group(1)!);
      continue;
    }
    lines.add(line);
  }
  return (lines: lines, exit: exit);
}

class _WatchFired extends StatefulWidget {
  const _WatchFired(
      {required this.subject, required this.path, required this.preview});

  final String subject;
  final String path;
  final String preview;

  @override
  State<_WatchFired> createState() => _WatchFiredState();
}

class _WatchFiredState extends State<_WatchFired> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final read = _readWatchPreview(widget.preview);
    final exit = read.exit;
    final status = switch (exit) {
      null => 'updated',
      0 => 'finished · exit 0',
      _ => 'failed · exit $exit',
    };
    final canExpand = read.lines.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s4),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: widget.subject, style: TS.ui(AppColors.fg2)),
                    TextSpan(text: '  $status', style: TS.meta(AppColors.fg4)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canExpand) ...[
                const SizedBox(width: S.s6),
                AppIcon(_open ? 'chevron-down' : 'chevron-right',
                    size: 12, color: AppColors.fg4),
              ],
            ]),
          ),
        ),
        if (_open && canExpand)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, S.s2, 0, S.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.path.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.s4),
                    child: Text(widget.path, style: TS.meta(AppColors.fg4)),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(read.lines.join('\n'),
                        style: mono(11, height: 1.4, color: AppColors.fg3)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A coordination event in the chat canvas: this agent was messaged, or this
/// agent dispatched work into a session.
///
/// Rendered in the CONVERSATION because the event concerns THIS session's agent
/// — a message arriving for it, or work it handed out. It is deliberately a
/// quiet one-line notice, not a chat bubble: the message itself lives in the
/// agent's direct thread, and pretending otherwise here would suggest you are
/// talking in this chat when you are not.
class AgentEventRow extends StatelessWidget {
  const AgentEventRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    this.accent = false,
  });

  final String icon;
  final String label;
  final String detail;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = accent ? AppColors.accent : AppColors.fg3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: sans(12, weight: W.label, color: color)),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, height: 1.35, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width card for goal events in the chat canvas — a distinct block with
/// an accent rail and a status label, instead of a faint one-liner.
/// Centered hairline + label — used for compaction and tool-prune boundaries.
class _SystemDivider extends StatelessWidget {
  final String label;
  const _SystemDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s12),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: AppColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s12),
          child: Text(label[0].toUpperCase() + label.substring(1),
              style: TS.meta(), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(child: Container(height: 1, color: AppColors.line)),
      ]),
    );
  }
}
