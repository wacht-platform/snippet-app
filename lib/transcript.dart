// Transcript components: expandable mono tool rows (output inline, one tap — not
// buried in sheets), first-class lane cards with ticking elapsed, and styled system
// rows for watches, goals, and compaction.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'coordination_tool_views.dart';
import 'models.dart';
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
    final canExpand = toolIsExpandable(widget.tool, widget.args, widget.result);
    final step =
        ToolStep(tool: widget.tool, args: widget.args, result: widget.result);
    final failed = step.failed;
    final (verb, object) = toolSentenceParts(step);
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
                  child: AppIcon(
                      failed ? 'alert-triangle' : toolIcon(widget.tool),
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
                        style: TS.ui(failed ? AppColors.danger : AppColors.fg2)),
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

class BrailleSpinner extends StatelessWidget {
  final Color? color;
  const BrailleSpinner({super.key, this.color});
  @override
  Widget build(BuildContext context) =>
      Spinner(size: 14, color: color ?? AppColors.run);
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
    final headline = running
        ? toolSentence(current, running: true)
        : activitySummary(steps);
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
                    ? AppIcon(toolIcon(current.tool), size: 14, color: AppColors.run)
                    : AppIcon(failures > 0 ? 'alert-triangle' : 'check',
                        size: 14,
                        color: failures > 0 ? AppColors.danger : AppColors.fg4),
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
                child:
                    AppIcon('chevron-right', size: 12, color: AppColors.fg4),
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
                ? Padding(
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
                        padding: const EdgeInsets.only(left: 24, top: S.s6),
                        child: _ChangedFiles(changes: changes, onTap: _toggle),
                      )
                    : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
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
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < changes.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
            InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.s12),
                  child: Row(children: [
                    AppIcon(
                        switch (changes[i].kind) {
                          FileChangeKind.created => 'file-plus',
                          FileChangeKind.deleted => 'trash',
                          FileChangeKind.moved => 'arrow-right',
                          FileChangeKind.edited => 'edit',
                        },
                        size: 13, color: AppColors.fg3),
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
    final done = lane != null && !running && !failed;
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
                : 'Queued';

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
                onTapLink: (txt, href, title) => openMarkdownLink(href),
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
          icon: 'eye',
          verb: 'Watching',
          subject: m?.group(1) ?? reasoning,
          path: m?.group(2),
        );
      case 'watch_removed':
        final m =
            RegExp(r'^stopped watching "(.*)"$').firstMatch(reasoning.trim());
        return _WatchLine(
          icon: 'eye-off',
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
    required this.icon,
    required this.verb,
    required this.subject,
    this.path,
    this.muted = false,
  });

  final String icon;
  final String verb;
  final String subject;
  final String? path;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final strong = muted ? AppColors.fg3 : AppColors.fg2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s6),
      child: Row(children: [
        SizedBox(
            width: 16,
            child: Center(
                child: AppIcon(icon,
                    size: 16,
                    color: muted ? AppColors.fg4 : AppColors.accent))),
        const SizedBox(width: S.s8),
        Text(verb, style: TS.label(strong).copyWith(fontWeight: W.body)),
        const SizedBox(width: S.s6),
        Flexible(
          flex: 0,
          child: Text(subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.label(muted ? AppColors.fg3 : AppColors.fg1)),
        ),
        if (path != null && path!.isNotEmpty) ...[
          const SizedBox(width: S.s8),
          Expanded(
            child: Text(path!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.codeSmall(AppColors.fg4)),
          ),
        ] else
          const Spacer(),
      ]),
    );
  }
}

class _WatchFired extends StatelessWidget {
  const _WatchFired(
      {required this.subject, required this.path, required this.preview});

  final String subject;
  final String path;
  final String preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
              width: 16,
              child: Center(
                  child:
                      AppIcon('activity', size: 16, color: AppColors.accent))),
          const SizedBox(width: S.s8),
          Flexible(
            flex: 0,
            child: Text('$subject changed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.label(AppColors.fg1)),
          ),
          if (path.isNotEmpty) ...[
            const SizedBox(width: S.s8),
            Expanded(
              child: Text(path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.codeSmall(AppColors.fg4)),
            ),
          ] else
            const Spacer(),
        ]),
        if (preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, S.s4, 0, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s6),
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(R.sm + 2),
              ),
              child: Text(preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: mono(12, height: 1.4, color: AppColors.fg2)),
            ),
          ),
      ]),
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
