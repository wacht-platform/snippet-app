// Dev-tool-dense transcript components: a live status rail, expandable mono
// tool rows (output inline, one tap — not buried in sheets), first-class lane
// cards with ticking elapsed, and styled system rows (watches, goals,
// compaction) that stop hiding what the agent is doing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'models.dart';
import 'theme.dart';
import 'tool_views.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Status rail — the always-visible facts: ctx gauge, tokens, lanes, watches,
// rate limit, approval. Dense, mono, one line; horizontally scrollable.
// ---------------------------------------------------------------------------

class StatusRail extends StatelessWidget {
  final HarnessState? state;
  final String? modelLabel;
  final VoidCallback? onUsageTap;
  final VoidCallback? onLanesTap;
  const StatusRail(
      {super.key,
      required this.state,
      this.modelLabel,
      this.onUsageTap,
      this.onLanesTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final s = state;
    final items = <Widget>[];

    if (s != null && s.contextWindow > 0) {
      final pct = (s.lastPromptTokens / s.contextWindow).clamp(0.0, 1.0);
      items.add(_railTap(
        onTap: onUsageTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 34,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppColors.surface3,
                color: pct > 0.85 ? AppColors.danger : AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('${(pct * 100).round()}%',
              style: mono(11, color: AppColors.fg2)),
        ]),
      ));
    }
    if (s != null && (s.promptTokens > 0 || s.completionTokens > 0)) {
      items.add(_railTap(
        onTap: onUsageTap,
        child: Text('↑${fmtSi(s.promptTokens)} ↓${fmtSi(s.completionTokens)}',
            style: mono(11, color: AppColors.fg3)),
      ));
    }
    final runningLanes = s?.lanes.where((l) => l.running).length ?? 0;
    if (runningLanes > 0) {
      items.add(_railTap(
        onTap: onLanesTap,
        child:
            Text('◆ $runningLanes', style: mono(11, color: AppColors.accent)),
      ));
    }
    if ((s?.watchCount ?? 0) > 0) {
      items.add(
          Text('◉ ${s!.watchCount}', style: mono(11, color: AppColors.run)));
    }
    final rp = s?.ratePrimary;
    if (rp != null) {
      items.add(_railTap(
        onTap: onUsageTap,
        child: Text(
            '${rateWindowLabel(rp.windowMinutes)} ${rp.leftPercent.round()}%',
            style: mono(11,
                color: rp.leftPercent < 15 ? AppColors.danger : AppColors.fg3)),
      ));
    }
    if (s?.goal?.ongoing ?? false) {
      items.add(Text(s!.goal!.paused ? '◇ paused' : '◇ goal',
          style: mono(11, color: AppColors.accent)));
    }
    if (s != null) {
      items.add(Text(s.approvalMode == 'auto' ? 'auto' : 'ask',
          style: mono(11,
              color:
                  s.approvalMode == 'auto' ? AppColors.fg4 : AppColors.run)));
    }
    if (s?.compacting ?? false) {
      items.add(Text('compacting…', style: mono(11, color: AppColors.run)));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                  width: 1,
                  height: 12,
                  color: AppColors.border,
                  margin: EdgeInsets.symmetric(horizontal: 10)),
            items[i],
          ],
        ]),
      ),
    );
  }

  Widget _railTap({VoidCallback? onTap, required Widget child}) =>
      onTap == null ? child : InkWell(onTap: onTap, child: child);
}

// ---------------------------------------------------------------------------
// Dense tool row — mono, status glyph, arg summary, right meta; tap expands the
// full tool view INLINE (capped height) instead of opening a sheet.
// ---------------------------------------------------------------------------

class DenseToolRow extends StatefulWidget {
  final String tool;
  final dynamic args;
  final dynamic result; // null while running
  const DenseToolRow({super.key, required this.tool, this.args, this.result});

  @override
  State<DenseToolRow> createState() => _DenseToolRowState();
}

class _DenseToolRowState extends State<DenseToolRow> {
  bool get _pending => widget.result == null;
  bool get _ok {
    final r = widget.result;
    return r is Map && r['status'] == 'success';
  }

  void _openDrawer(BuildContext context) {
    showAppSheet(context,
        title: toolTitle(widget.tool),
        child: toolDetailView(context,
            tool: widget.tool,
            args: widget.args,
            result: widget.result is Map
                ? (widget.result as Map).cast<String, dynamic>()
                : null));
  }

  // Right-aligned meta: bash exit code, edit diff stat, else ✓/✗.
  String get _meta {
    final r = widget.result;
    if (r is! Map) return '';
    if (widget.tool == 'bash') {
      final exit =
          (r['data'] is Map) ? (r['data']['exit_code']?.toString() ?? '') : '';
      return exit.isEmpty ? '' : 'exit $exit';
    }
    if (widget.tool == 'edit_file' ||
        widget.tool == 'write_file' ||
        widget.tool == 'replace_file_content') {
      final a = widget.args;
      if (a is Map) {
        final add = (a['new_string'] ?? a['content'] ?? '')
            .toString()
            .split('\n')
            .length;
        final del = (a['old_string'] ?? '').toString().split('\n').length;
        return '+$add −${a['old_string'] == null ? 0 : del}';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final glyph = _pending
        ? const _BrailleSpinner()
        : Text(_ok ? '✓' : '✗',
            style: mono(12, color: _ok ? AppColors.fg4 : AppColors.danger));
    final meta = _meta;

    return InkWell(
      borderRadius: BorderRadius.circular(R.xs),
      onTap: () => _openDrawer(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 16, child: Center(child: glyph)),
          const SizedBox(width: 6),
          Text(widget.tool,
              style: mono(12, weight: FontWeight.w600, color: AppColors.fg2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              toolArgSummary(widget.tool, widget.args),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(12, color: AppColors.fg3),
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(meta,
                style: mono(11, color: _ok ? AppColors.fg4 : AppColors.danger)),
          ],
          const SizedBox(width: 4),
          AppIcon('chevron-right', size: 13, color: AppColors.fg4),
        ]),
      ),
    );
  }
}

/// Terminal-style running indicator: the classic braille spinner, mono + amber —
/// on-theme for Terminal Ink where the Material ring felt foreign.
class _BrailleSpinner extends StatefulWidget {
  const _BrailleSpinner();
  @override
  State<_BrailleSpinner> createState() => _BrailleSpinnerState();
}

class _BrailleSpinnerState extends State<_BrailleSpinner> {
  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  Timer? _t;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_frames[_i], style: mono(12, color: AppColors.run));
}

/// A run of consecutive tool rows behind a subtle left rail. Short runs render
/// fully; long ones collapse to the last few with a "+N earlier" toggle.
class ToolRun extends StatefulWidget {
  final List<Widget> rows;
  const ToolRun(this.rows, {super.key});
  @override
  State<ToolRun> createState() => _ToolRunState();
}

class _ToolRunState extends State<ToolRun> {
  static const int visibleTail = 6;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final rows = widget.rows;
    final collapsed = !_all && rows.length > visibleTail + 2;
    final shown = collapsed ? rows.sublist(rows.length - visibleTail) : rows;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border2, width: 2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (collapsed)
          InkWell(
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text('⌄ +${rows.length - visibleTail} earlier steps',
                  style: mono(11, color: AppColors.fg4)),
            ),
          ),
        ...shown,
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Lane card — first-class: status dot, subject, ticking elapsed while running,
// summary preview when done; expands inline to the full summary.
// ---------------------------------------------------------------------------

class LaneCard extends StatefulWidget {
  /// Spawn row: [live] resolves the CURRENT record from state so the card
  /// updates in place (running → done) without new transcript entries.
  final String title;
  final LaneInfo? Function() live;
  final String? summary; // completion summary when this row is the completion
  const LaneCard(
      {super.key, required this.title, required this.live, this.summary});

  @override
  State<LaneCard> createState() => _LaneCardState();
}

class _LaneCardState extends State<LaneCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Tick the elapsed label only while the lane runs.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final l = widget.live();
      if (l == null || !l.running) {
        _tick?.cancel();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(String startedAt) {
    final t = DateTime.tryParse(startedAt);
    if (t == null) return '';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  void _showDetails(BuildContext context, LaneInfo? lane) {
    final handoff = lane?.handoff;
    final report = lane?.report;
    final summary = widget.summary ?? lane?.summary;
    final error = lane?.error;
    if ([handoff, report, summary, error]
        .every((s) => s == null || s.trim().isEmpty)) return;

    Widget section(String heading, String? text, {bool errorTone = false}) {
      if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading,
              style: mono(11,
                  weight: FontWeight.w600,
                  color: errorTone ? AppColors.danger : AppColors.fg3)),
          const SizedBox(height: 6),
          MarkdownBody(
            data: text,
            selectable: true,
            styleSheet: markdownStyle(context),
            builders: {'pre': PreBlockBuilder()},
          ),
        ]),
      );
    }

    showAppSheet(context,
        title: 'Delegated thread · ${widget.title}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          section('HANDOFF', handoff),
          section('RESULT', report ?? summary),
          section('ERROR', error, errorTone: true),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final l = widget.live();
    final running = l?.running ?? false;
    final failed = (l?.status ?? '') == 'failed';
    final summary = widget.summary ?? l?.summary;
    final hasDetails = [l?.handoff, l?.report, summary, l?.error]
        .any((s) => s != null && s.trim().isNotEmpty);
    final dot = running
        ? AppColors.accent
        : failed
            ? AppColors.danger
            : AppColors.fg4;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
            color: running ? AppColors.accentLine : AppColors.border),
      ),
      child: InkWell(
        onTap: hasDetails ? () => _showDetails(context, l) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      sans(13, weight: FontWeight.w600, color: AppColors.fg1)),
            ),
            if (hasDetails) ...[
              const SizedBox(width: 6),
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
            ],
            const SizedBox(width: 8),
            Text(
              running
                  ? 'running · ${l != null ? _elapsed(l.startedAt) : ''}'
                  : failed
                      ? 'failed'
                      : 'done',
              style: mono(11,
                  color: running
                      ? AppColors.accent
                      : (failed ? AppColors.danger : AppColors.fg4)),
            ),
          ]),
          if (summary != null && summary.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary.replaceAll(RegExp(r'^#{1,6}\s*'), '').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(12, height: 1.45, color: AppColors.fg3)),
          ],
        ]),
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
    final (glyph, color) = switch (step) {
      'watch_added' || 'watch_removed' => ('◉', AppColors.run),
      'file_watch' => ('◉', AppColors.accent),
      'goal_set' || 'goal_completed' || 'goal_paused' || 'goal_cancelled' => (
          '◇',
          AppColors.accent
        ),
      'history_compaction_pass' ||
      'history_compacted' ||
      'history_compaction_skipped' =>
        ('▣', AppColors.fg4),
      'interrupted' => ('■', AppColors.danger),
      _ => ('·', AppColors.fg4),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 16,
            child: Center(child: Text(glyph, style: mono(11, color: color)))),
        const SizedBox(width: 6),
        Expanded(
          child: Text(reasoning,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: sans(11.5, height: 1.4, color: AppColors.fg4)),
        ),
      ]),
    );
  }
}
