// Transcript components: expandable mono tool rows (output inline, one tap — not
// buried in sheets), first-class lane cards with ticking elapsed, and styled system
// rows for watches, goals, and compaction.
import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'panel.dart';
import 'platform.dart';
import 'theme.dart';
import 'tool_views.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Dense tool row — mono, status glyph, arg summary, right meta; tap expands the
// full tool view INLINE (capped height) instead of opening a sheet.
// ---------------------------------------------------------------------------

class _ToolDetailPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  const _ToolDetailPanel(
      {required this.title, required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface1,
      appBar: AppBar(
        title: Text(title,
            style: sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
        leading: IconBtn('x',
            size: 36, iconSize: 18, tooltip: 'Close', onTap: onClose),
        backgroundColor: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: AppColors.border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

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
    final detail = safeToolDetailView(context,
        tool: widget.tool,
        args: widget.args,
        result: widget.result is Map ? widget.result : null);
    if (kMobile) {
      showAppSheet(context, title: toolTitle(widget.tool), child: detail);
    } else {
      presentScreen(context,
          builder: (_, close) => _ToolDetailPanel(
              title: toolTitle(widget.tool), onClose: close, child: detail));
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
