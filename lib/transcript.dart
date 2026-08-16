// Transcript components: expandable mono tool rows (output inline, one tap — not
// buried in sheets), first-class lane cards with ticking elapsed, and styled system
// rows for watches, goals, and compaction.
import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';
import 'tool_views.dart';
import 'widgets.dart';

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
  late bool _expanded;

  bool get _pending => widget.result == null;
  bool get _ok {
    final r = widget.result;
    return r is Map && r['status'] == 'success';
  }

  @override
  void initState() {
    super.initState();
    // BeUI: running tools show their live output; completed tools stay one line.
    _expanded = widget.result == null;
  }

  @override
  void didUpdateWidget(covariant DenseToolRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result == null && widget.result != null) {
      _expanded = false;
    }
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

  Widget _inlineDetail(BuildContext context) {
    if (!_expanded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 2, bottom: 8, top: 1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: mono(11.5, height: 1.45, color: AppColors.fg3),
            child: safeToolDetailView(context,
                tool: widget.tool, args: widget.args, result: widget.result),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final glyph = _pending
        ? const _BrailleSpinner()
        : Text(_ok ? '✓' : '✗',
            style: mono(12, color: _ok ? AppColors.ok : AppColors.danger));
    final meta = _meta;

    final summary = toolArgSummary(widget.tool, widget.args);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 16, child: Center(child: glyph)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(toolTitle(widget.tool),
                      style: sans(13.5,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg4)),
                    ),
                ],
              ),
            ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 2),
                child: Text(meta, style: sans(11.5, color: AppColors.fg4)),
              ),
          ]),
        ),
      ),
      _inlineDetail(context),
    ]);
  }
}

/// Terminal-style running indicator: the classic braille spinner, mono + amber —
/// on-theme for Terminal Ink where the Material ring felt foreign.
class _BrailleSpinner extends StatefulWidget {
  const _BrailleSpinner();
  @override
  State<_BrailleSpinner> createState() => _BrailleSpinnerState();
}

/// Shared braille animation timer: one Timer.periodic drives all visible
/// spinners, avoiding N individual timers when many tool calls run at once.
class _BrailleSpinnerState extends State<_BrailleSpinner> {
  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  static Timer? _sharedTimer;
  static int _tick = 0;
  static final Set<State<_BrailleSpinner>> _listeners = {};

  static void _onTick(_) {
    _tick = (_tick + 1) % _frames.length;
    for (final s in _listeners) {
      if (s.mounted) s.setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _listeners.add(this);
    if (_sharedTimer == null || !_sharedTimer!.isActive) {
      _sharedTimer = Timer.periodic(const Duration(milliseconds: 150), _onTick);
    }
  }

  @override
  void dispose() {
    _listeners.remove(this);
    if (_listeners.isEmpty) {
      _sharedTimer?.cancel();
      _sharedTimer = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_frames[_tick], style: mono(12, color: AppColors.run));
}

/// A run of consecutive tool rows behind a subtle left rail. It opens compactly
/// with the newest tool step visible; tapping the summary reveals the full run.
class ToolRun extends StatefulWidget {
  final List<Widget> rows;
  const ToolRun(this.rows, {super.key});
  @override
  State<ToolRun> createState() => _ToolRunState();
}

class _ToolRunState extends State<ToolRun> {
  static const int visibleTail = 1;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final rows = widget.rows;
    final collapsed = !_all && rows.length > visibleTail;
    final shown = collapsed ? rows.sublist(rows.length - visibleTail) : rows;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (collapsed)
          InkWell(
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 24),
              child: Text('${rows.length - visibleTail} completed steps',
                  style: sans(12, color: AppColors.fg4)),
            ),
          ),
        ...shown,
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Lane notice — the transcript keeps only a compact pointer. Full lane output
// belongs in the dedicated lanes screen.
// ---------------------------------------------------------------------------

class LaneNotice extends StatelessWidget {
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
  Widget build(BuildContext context) {
    Theme.of(context);
    final lane = live();
    final failed = lane?.status == 'failed';
    final running = lane?.running ?? false;
    final color = running
        ? AppColors.accent
        : failed
            ? AppColors.danger
            : AppColors.fg4;
    final status = running
        ? 'running'
        : failed
            ? 'failed'
            : 'complete';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: running ? AppColors.accentLine : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                AppIcon('layers', size: 15, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5,
                        weight: FontWeight.w600, color: AppColors.fg2),
                  ),
                ),
                const SizedBox(width: 9),
                Text(status, style: mono(10.5, color: color)),
                const SizedBox(width: 5),
                AppIcon('chevron-right', size: 13, color: AppColors.fg4),
              ]),
              if (summary != null && summary!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                MarkdownPreview(data: summary!, maxLines: 2),
              ],
            ],
          ),
        ),
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

    final (glyph, color) = switch (step) {
      'watch_added' || 'watch_removed' => ('◉', AppColors.run),
      'file_watch' => ('◉', AppColors.accent),
      'goal_set' || 'goal_completed' || 'goal_paused' || 'goal_cancelled' => (
          '◇',
          AppColors.accent
        ),
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

/// Centered hairline + label — used for compaction and tool-prune boundaries.
class _SystemDivider extends StatelessWidget {
  final String label;
  const _SystemDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final style = mono(10.5, color: AppColors.fg4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        const Expanded(child: Divider(height: 1, thickness: 0.6)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Expanded(child: Divider(height: 1, thickness: 0.6)),
      ]),
    );
  }
}
