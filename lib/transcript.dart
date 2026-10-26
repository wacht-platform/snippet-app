// Transcript components: expandable mono tool rows (output inline, one tap — not
// buried in sheets), first-class lane cards with ticking elapsed, and styled system
// rows for watches, goals, and compaction.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'mochi.dart';
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'tool_sheet.dart';
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
    final failed = step.failed;
    final (verb, object) = toolSentenceParts(step);
    if (kMobile) return _phone(context, step, canExpand, failed, verb, object);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? _toggle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s4),
            child: Row(children: [
              SizedBox(
                width: 16,
                child: Center(
                  // Pending calls don't spin: the transcript has one live
                  // indicator (the status line at the bottom).
                  child:
                      AppIcon(failed ? 'alert-triangle' : toolIcon(widget.tool),
                          size: 14,
                          color: widget.result == null
                              ? AppColors.run
                              : failed
                                  ? AppColors.danger
                                  : AppColors.fg4),
                ),
              ),
              const SizedBox(width: S.s8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: verb,
                        style:
                            TS.ui(failed ? AppColors.danger : AppColors.fg2)),
                    if (object.isNotEmpty)
                      TextSpan(text: ' $object', style: TS.ui(AppColors.fg3)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ..._metaWidgets(),
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
            padding: const EdgeInsets.fromLTRB(24, S.s2, 0, S.s8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: mono(11, height: 1.4, color: AppColors.fg3),
                  child: safeToolDetailView(context,
                      tool: widget.tool,
                      args: widget.args,
                      result: widget.result),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _phone(BuildContext context, ToolStep step, bool canExpand,
      bool failed, String verb, String object) {
    final command = verb == 'Ran' || verb == 'Running';
    final dot = widget.result == null
        ? AppColors.run
        : failed
            ? AppColors.danger
            : AppColors.ok;
    final Widget line = command
        ? Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: Color.lerp(AppColors.bg, Colors.black, 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text('\$ ', style: mono(12.5, color: AppColors.fg4)),
              Expanded(
                child: Text(object,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12.5, color: AppColors.fg2)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ]),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: verb,
                        style: mono(12.5,
                            color: failed ? AppColors.danger : AppColors.fg4)),
                    if (object.isNotEmpty)
                      TextSpan(
                          text: '  $object',
                          style: mono(12.5, color: AppColors.fg2)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ..._metaWidgets(),
              if (widget.result == null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ],
            ]),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExpand ? _toggle : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: command ? 3 : 0),
            child: line,
          ),
        ),
        if (_open && canExpand)
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
            ),
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: DefaultTextStyle(
                style: mono(11.5, height: 1.45, color: AppColors.fg3),
                child: safeToolDetailView(context,
                    tool: widget.tool, args: widget.args, result: widget.result),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _metaWidgets() {
    if (widget.tool != 'change_files') return const [];
    final step =
        ToolStep(tool: widget.tool, args: widget.args, result: widget.result);
    final changes = fileChanges([step]);
    final added = changes.fold<int>(0, (sum, c) => sum + c.added);
    final removed = changes.fold<int>(0, (sum, c) => sum + c.removed);
    if (added == 0 && removed == 0) return const [];
    return [
      const SizedBox(width: S.s8),
      Text('+$added', style: TS.meta(AppColors.ok)),
      const SizedBox(width: S.s4),
      Text('-$removed', style: TS.meta(AppColors.danger)),
    ];
  }
}

/// Consecutive tools as a BeUI group: one header row, details on expand.
class ToolRun extends StatefulWidget {
  final List<Widget> rows;
  final bool running;
  final bool open;
  final ValueChanged<bool>? onOpenChanged;

  /// When given, tapping the run opens it as a sheet (bottom sheet on phones,
  /// side panel on desktop) that follows this live batch, instead of expanding
  /// inline.
  final ValueListenable<ToolBatch>? batch;
  const ToolRun(this.rows,
      {super.key,
      this.running = false,
      this.open = false,
      this.onOpenChanged,
      this.batch});
  @override
  State<ToolRun> createState() => _ToolRunState();
}

class _ToolRunState extends State<ToolRun> {
  final Set<int> _expanded = {};
  bool _showAll = false;

  void _set(VoidCallback f) => setState(f);

  void _toggle() {
    final batch = widget.batch;
    if (batch != null) {
      showToolBatchSheet(context, batch: batch);
      return;
    }
    widget.onOpenChanged?.call(!widget.open);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final steps = [
      for (final r in widget.rows.whereType<DenseToolRow>())
        ToolStep(tool: r.tool, args: r.args, result: r.result),
    ];
    final current = steps.lastWhere((s) => s.running,
        orElse: () => steps.isEmpty ? const ToolStep(tool: '') : steps.last);
    final running = widget.running && steps.any((s) => s.running);
    final failures = steps.where((s) => s.failed).length;
    final changes = fileChanges(steps);
    // A run of acknowledgements only (assign, archive, …) has nothing to open.
    final openable =
        steps.isEmpty || widget.running || steps.any(toolHasDetail);
    final headline =
        running ? toolSentence(current, running: true) : activitySummary(steps);
    if (!kMobile && steps.isNotEmpty) return _trace(steps);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openable ? _toggle : null,
          child: Row(children: [
            SizedBox(
              width: 16,
              child: Center(
                child: running
                    ? AppIcon(toolIcon(current.tool),
                        size: 14, color: AppColors.run)
                    : AppIcon(failures > 0 ? 'alert-triangle' : 'check',
                        size: 14,
                        color: failures > 0
                            ? AppColors.danger
                            : (kMobile ? AppColors.ok : AppColors.fg4)),
              ),
            ),
            const SizedBox(width: S.s8),
            Expanded(
              child: Text(headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.ui(running ? AppColors.fg2 : AppColors.fg3)),
            ),
            if (!running && failures > 0) ...[
              const SizedBox(width: S.s8),
              Text('$failures failed', style: TS.meta(AppColors.danger)),
            ],
            if (openable) ...[
              const SizedBox(width: S.s6),
              AnimatedRotation(
                turns: widget.open && widget.batch == null ? 0.25 : 0,
                duration: Motion.fast,
                curve: Motion.enter,
                child: AppIcon('chevron-right', size: 12, color: AppColors.fg4),
              ),
            ],
          ]),
        ),
        AnimatedSize(
          duration: Motion.open,
          reverseDuration: Motion.close,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Motion.fast,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
            child: widget.open && widget.batch == null
                ? kMobile
                    ? Container(
                        key: const ValueKey('steps'),
                        margin: const EdgeInsets.only(left: 7, top: 8),
                        padding: const EdgeInsets.only(left: 16),
                        decoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(
                                  color: AppColors.fg1.withValues(alpha: 0.09))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.rows,
                        ),
                      )
                    : Padding(
                        key: const ValueKey('steps'),
                        padding: const EdgeInsets.only(left: 24, top: S.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.rows,
                        ),
                      )
                : changes.isNotEmpty
                    ? Padding(
                        key: const ValueKey('changes'),
                        padding: EdgeInsets.only(
                            left: kMobile ? 0 : 24, top: kMobile ? 10 : S.s6),
                        child: _ChangedFiles(changes: changes, onTap: _toggle),
                      )
                    : const SizedBox(
                        key: ValueKey('none'), width: double.infinity),
          ),
        ),
      ]),
    );
  }
}

extension on _ToolRunState {
  Widget _trace(List<ToolStep> steps) {
    final running = widget.running && steps.any((s) => s.running);
    final open = running || widget.open;
    const cap = 5;
    final all = !running || _showAll || steps.length <= cap;
    final shown = all ? steps : steps.sublist(steps.length - cap);
    Widget row(ToolStep st) {
      final idx = steps.indexOf(st);
      final canOpen = toolHasDetail(st);
      final expanded = _expanded.contains(idx);
      return Column(
        key: ValueKey('step-$idx'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TraceRow(
            step: st,
            expanded: expanded,
            onTap: canOpen
                ? () => _set(() =>
                    expanded ? _expanded.remove(idx) : _expanded.add(idx))
                : null,
          ),
          AnimatedSize(
            duration: Motion.fast,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(26, 2, 0, 8),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 360),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: SingleChildScrollView(
                        child: DefaultTextStyle(
                          style: mono(12, height: 1.45, color: AppColors.fg2),
                          child: safeToolDetailView(context,
                              tool: st.tool, args: st.args, result: st.result),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      );
    }

    final changes = fileChanges(steps);
    final add = changes.fold<int>(0, (a, c) => a + c.added);
    final del = changes.fold<int>(0, (a, c) => a + c.removed);
    final failures = steps.where((s) => !s.running && s.failed).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!running)
          _TraceHeader(
            label: activitySummary(steps),
            open: open,
            add: changes.isEmpty ? null : add,
            del: changes.isEmpty ? null : del,
            failures: failures,
            onTap: () => widget.onOpenChanged?.call(!widget.open),
          ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: EdgeInsets.only(top: running ? 0 : 2),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!all)
                          _TraceMore(
                            count: steps.length - cap,
                            onTap: () => _set(() => _showAll = true),
                          ),
                        for (final st in shown) row(st),
                      ]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

class _ChangedFiles extends StatelessWidget {
  const _ChangedFiles({required this.changes, required this.onTap});

  final List<FileChange> changes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: kMobile ? AppColors.surface1 : AppColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kMobile ? 16 : R.md),
          side: kMobile
              ? BorderSide(color: AppColors.fg1.withValues(alpha: 0.08))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < changes.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
            InkWell(
              onTap: onTap,
              child: SizedBox(
                height: kMobile ? 42 : 34,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: kMobile ? 14 : S.s12),
                  child: Row(children: [
                    AppIcon(
                        switch (changes[i].kind) {
                          FileChangeKind.created => 'file-plus',
                          FileChangeKind.deleted => 'trash',
                          FileChangeKind.moved => 'arrow-right',
                          FileChangeKind.edited => 'edit',
                        },
                        size: 13,
                        color: AppColors.fg3),
                    const SizedBox(width: S.s8),
                    Expanded(
                      child: Text(changes[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TS.codeSmall(AppColors.fg1)),
                    ),
                    if (changes[i].added + changes[i].removed > 0) ...[
                      const SizedBox(width: S.s8),
                      Text('+${changes[i].added}',
                          style: TS.meta(AppColors.ok)),
                      const SizedBox(width: S.s4),
                      Text('−${changes[i].removed}',
                          style: TS.meta(AppColors.danger)),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ]),
      );
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
    final lane = live();
    final failed = lane?.status == 'failed';
    final running = lane?.running ?? false;
    final paused = lane?.status == 'paused';
    final done = lane != null && !running && !failed && !paused;
    final activity = lane?.activity?.trim();
    final displaySummary = summary?.trim().isNotEmpty == true
        ? summary!.trim()
        : lane?.summary?.trim();
    final tone = running
        ? Tone.accent
        : failed
            ? Tone.danger
            : done
                ? Tone.ok
                : Tone.neutral;
    final status = running
        ? 'Running'
        : failed
            ? 'Failed'
            : done
                ? 'Completed'
                : paused
                    ? 'Paused'
                    : 'Queued';

    {
      final agent = lane?.agent?.trim() ?? '';
      final dot = running
          ? AppColors.run
          : failed
              ? AppColors.danger
              : done
                  ? AppColors.ok
                  : AppColors.fg4;
      final started = DateTime.tryParse(lane?.startedAt ?? '');
      String elapsed() {
        if (started == null) return '';
        final d = DateTime.now().toUtc().difference(started.toUtc());
        if (d.inMinutes < 1) return '${d.inSeconds}s';
        if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
        return '${d.inHours}h ${d.inMinutes % 60}m';
      }

      if (kMobile) {
        final line = running
            ? (activity?.isNotEmpty == true ? activity! : 'Working')
            : (displaySummary?.isNotEmpty == true ? displaySummary! : status);
        return Semantics(
          button: true,
          label: '$title, ${status.toLowerCase()}. Open the lane.',
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(children: [
                    running
                        ? WorkingMochi(
                            size: 22,
                            color: agent.isEmpty
                                ? mochiPalette.first.$2
                                : mochiColorFor(agent))
                        : MochiIcon(
                            color: failed
                                ? AppColors.danger
                                : (agent.isEmpty
                                    ? AppColors.ok
                                    : mochiColorFor(agent)),
                            size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(14.5,
                                  weight: W.strong, color: AppColors.fg1)),
                          const SizedBox(height: 1),
                          Text(line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5, color: AppColors.fg3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(running ? elapsed() : status,
                        style: sans(12,
                            tabular: true,
                            color: running
                                ? AppColors.accent
                                : failed
                                    ? AppColors.danger
                                    : AppColors.ok)),
                  ]),
                ),
              ),
            ),
          ),
        );
      }
      final detail = running
          ? (activity?.isNotEmpty == true ? activity! : 'Working')
          : (displaySummary?.isNotEmpty == true ? displaySummary! : status);
      return Semantics(
        button: true,
        label: '$title, ${status.toLowerCase()}. Open the lane.',
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(R.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                    child: Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        flex: 0,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                weight: W.strong,
                                height: 18 / 13,
                                color: AppColors.fg1)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            agent.isEmpty ? detail : '$agent · $detail',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5,
                                height: 18 / 12.5, color: AppColors.fg4)),
                      ),
                      const SizedBox(width: 10),
                      Text(running ? elapsed() : status,
                          style: sans(12,
                              tabular: true,
                              height: 18 / 12,
                              color: running
                                  ? AppColors.fg3
                                  : failed
                                      ? AppColors.danger
                                      : AppColors.fg4)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$title, ${status.toLowerCase()}. Open delegated lanes.',
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s6),
        child: Material(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(R.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(S.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IconTile(
                      running
                          ? 'agent'
                          : failed
                              ? 'alert-triangle'
                              : 'check',
                      tone: tone,
                      size: 28,
                    ),
                    const SizedBox(width: S.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TS.rowTitle()),
                          if (running &&
                              activity != null &&
                              activity.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: S.s2),
                              child: Text(activity,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TS.codeSmall()),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: S.s8),
                    Tag(status, tone: tone, live: running),
                    const SizedBox(width: S.s4),
                    AppIcon('chevron-right', size: 14, color: AppColors.fg4),
                  ]),
                  if (displaySummary != null && displaySummary.isNotEmpty) ...[
                    const SizedBox(height: S.s8),
                    InsetPanel(
                      padding: const EdgeInsets.all(S.s8),
                      child: MarkdownPreview(data: displaySummary, maxLines: 2),
                    ),
                  ],
                ],
              ),
            ),
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
                onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
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


class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder, this.onTap});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: _hover && widget.onTap != null
                  ? AppColors.fg1.withValues(alpha: 0.04)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: widget.builder(_hover),
          ),
        ),
      );
}

Widget _diffMeta(int add, int del) => Text.rich(
      TextSpan(children: [
        TextSpan(text: '+$add', style: mono(11.5, color: AppColors.ok)),
        TextSpan(text: ' −$del', style: mono(11.5, color: AppColors.danger)),
      ]),
    );

class _TraceHeader extends StatelessWidget {
  const _TraceHeader({
    required this.label,
    required this.open,
    required this.onTap,
    this.add,
    this.del,
    this.failures = 0,
  });
  final String label;
  final bool open;
  final VoidCallback onTap;
  final int? add;
  final int? del;
  final int failures;

  @override
  Widget build(BuildContext context) => _Hoverable(
        onTap: onTap,
        builder: (hover) => SizedBox(
          height: 28,
          child: Row(children: [
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      color: hover || open ? AppColors.fg2 : AppColors.fg3)),
            ),
            if (add != null && del != null && add! + del! > 0) ...[
              const SizedBox(width: 8),
              _diffMeta(add!, del!),
            ],
            if (failures > 0) ...[
              const SizedBox(width: 8),
              Text('$failures failed', style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: Motion.fast,
              child: AppIcon('chevron-right', size: 12, color: AppColors.fg4),
            ),
            const SizedBox(width: 8),
          ]),
        ),
      );
}

class _TraceMore extends StatelessWidget {
  const _TraceMore({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Hoverable(
        onTap: onTap,
        builder: (_) => SizedBox(
          height: 26,
          child: Row(children: [
            const SizedBox(width: 32),
            Text('$count earlier ${count == 1 ? 'step' : 'steps'}',
                style: sans(12.5, color: AppColors.fg4)),
          ]),
        ),
      );
}

String _stepIcon(ToolStep st) {
  final t = st.tool;
  if (t == 'read_file' || t == 'view_file') return 'file-text';
  if (t.contains('search') || t.contains('grep') || t.contains('glob') ||
      t.contains('find')) {
    return t == 'web_search' ? 'globe' : 'search';
  }
  if (t.contains('list') || t.contains('dir')) return 'folder';
  return toolIcon(t);
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.step, required this.expanded, this.onTap});
  final ToolStep step;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = step;
    final ch = fileChanges([st]);
    final add = ch.fold<int>(0, (a, c) => a + c.added);
    final del = ch.fold<int>(0, (a, c) => a + c.removed);
    final failed = !st.running && st.failed;
    final exit = st.result is Map ? (st.result as Map)['exit_code'] : null;
    final badExit = exit is num && exit != 0;
    final (verb, obj) = toolSentenceParts(st);
    final isCommand = st.tool == 'bash' && obj.isNotEmpty;
    return _Hoverable(
      onTap: onTap,
      builder: (hover) => SizedBox(
        height: 26,
        child: Row(children: [
          SizedBox(
            width: 26,
            child: Center(
              child: st.running
                  ? const Spinner(size: 11)
                  : AppIcon(_stepIcon(st),
                      size: 13,
                      color: failed ? AppColors.danger : AppColors.fg4),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: verb,
                    style: sans(13,
                        color: st.running ? AppColors.fg2 : AppColors.fg3)),
                if (obj.isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                      text: obj,
                      style: isCommand
                          ? mono(12, color: AppColors.fg2)
                          : sans(13, color: AppColors.fg2)),
                ],
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ch.isNotEmpty && add + del > 0) ...[
            const SizedBox(width: 10),
            _diffMeta(add, del),
          ] else if (failed || badExit) ...[
            const SizedBox(width: 10),
            Text(badExit ? 'exit $exit' : 'failed',
                style: sans(12, color: AppColors.danger)),
          ],
          SizedBox(
            width: 24,
            child: onTap != null && (hover || expanded)
                ? Center(
                    child: AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: Motion.fast,
                      child: AppIcon('chevron-right',
                          size: 12, color: AppColors.fg4),
                    ),
                  )
                : null,
          ),
        ]),
      ),
    );
  }
}
