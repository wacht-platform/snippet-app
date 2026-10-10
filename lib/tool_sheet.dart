import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'media_views.dart';
import 'panel.dart';
import 'platform.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'tool_views.dart';
import 'widgets.dart';

/// One batch of consecutive tool calls, as the sheet shows it.
class ToolBatch {
  final List<ToolStep> steps;
  final bool running;
  const ToolBatch(this.steps, {this.running = false});
}

/// Open a tool batch: a draggable bottom sheet on phones, a right-side panel on
/// wider windows. [batch] keeps updating while the calls are still running.
Future<void> showToolBatchSheet(
  BuildContext context, {
  required ValueListenable<ToolBatch> batch,
  int? initialStep,
}) {
  final scope = DaemonScope.scopeOf(context);
  final openInPane = scope?.onOpenTools;
  if (!kMobile && openInPane != null) {
    openInPane(batch);
    return Future.value();
  }
  Widget body(VoidCallback close, {ScrollController? scroll}) {
    final view = ToolBatchView(
      batch: batch,
      onClose: close,
      scroll: scroll,
      initialStep: initialStep,
    );
    if (scope == null) return view;
    final openTab = scope.onOpenFile;
    return DaemonScope(
      client: scope.client,
      // A file opened from the side panel lands in a tab behind it, so the
      // panel steps aside first.
      onOpenFile: openTab == null
          ? null
          : (path, name) {
              close();
              openTab(path, name);
            },
      child: view,
    );
  }

  if (!kMobile) {
    return presentScreen<void>(
      context,
      style: PanelStyle.drawer,
      maxWidth: 560,
      builder: (_, close) => body(close),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: AppColors.surface1,
    sheetAnimationStyle: sheetMotion,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.62],
      builder: (_, scroll) =>
          body(() => Navigator.of(sheetContext).pop(), scroll: scroll),
    ),
  );
}

/// The sheet's content: the list of calls, and one call's full detail pushed on
/// top of it with a horizontal slide.
class ToolBatchView extends StatefulWidget {
  final ValueListenable<ToolBatch> batch;
  final VoidCallback onClose;
  final ScrollController? scroll;
  final int? initialStep;

  /// Shown in the desktop side pane, whose tab strip already closes it.
  final bool docked;
  const ToolBatchView({
    super.key,
    required this.batch,
    required this.onClose,
    this.scroll,
    this.initialStep,
    this.docked = false,
  });

  @override
  State<ToolBatchView> createState() => _ToolBatchViewState();
}

class _ToolBatchViewState extends State<ToolBatchView> {
  int? _open;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _open = widget.initialStep;
  }

  void _show(int? index) => setState(() {
        _forward = index != null;
        _open = index;
      });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ToolBatch>(
      valueListenable: widget.batch,
      builder: (context, batch, _) {
        final open =
            _open != null && _open! < batch.steps.length ? _open : null;
        return PopScope(
          canPop: open == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _show(null);
          },
          // The host paints the surface: the pane and drawer are the app's
          // background, the phone sheet its own raised colour.
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedSwitcher(
              duration: Motion.base,
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(open ?? -1);
                final dx = (_forward == incoming) ? 0.12 : -0.12;
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: Offset(dx, 0), end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                );
              },
              child: open == null && kMobile
                  ? _Timeline(
                      key: const ValueKey(-1),
                      batch: batch,
                      scroll: widget.scroll,
                      onClose: widget.docked ? null : widget.onClose,
                      onShowAll: _show,
                    )
                  : open == null
                      ? _StepList(
                          key: const ValueKey(-1),
                          batch: batch,
                          scroll: widget.scroll,
                          onClose: widget.docked ? null : widget.onClose,
                          onOpen: _show,
                          header: !widget.docked,
                        )
                      : _StepDetail(
                          key: ValueKey(open),
                          step: batch.steps[open],
                          index: open,
                          total: batch.steps.length,
                          scroll: widget.scroll,
                          onBack: () => _show(null),
                          onClose: widget.docked ? null : widget.onClose,
                        ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool compact;
  final VoidCallback? onClose;
  const _SheetHeader({
    this.leading,
    required this.title,
    this.subtitle,
    this.compact = false,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (kMobile)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: kMobile ? 0 : 8),
        child: Row(children: [
          leading ?? const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(compact ? 13 : 15,
                        weight: W.label, color: AppColors.fg1)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
          if (onClose != null)
            IconBtn('x',
                size: 34, iconSize: 16, tooltip: 'Close', onTap: onClose),
        ]),
      ),
      Container(height: 1, color: AppColors.border),
    ]);
  }
}

class _StepList extends StatelessWidget {
  final ToolBatch batch;
  final ScrollController? scroll;
  final VoidCallback? onClose;
  final ValueChanged<int> onOpen;

  /// Docked in the desktop pane, the tab already names the list.
  final bool header;
  const _StepList({
    super.key,
    required this.batch,
    required this.scroll,
    required this.onClose,
    required this.onOpen,
    this.header = true,
  });

  @override
  Widget build(BuildContext context) {
    final steps = batch.steps;
    final running = batch.running && steps.any((s) => s.running);
    // The list itself shows what ran and which failed (their rows turn red);
    // the header only says when it is still going.
    final subtitle = running ? 'running' : '';
    return Column(children: [
      if (header)
        _SheetHeader(
          title: 'Activity',
          subtitle: subtitle,
          onClose: onClose,
        ),
      Expanded(
        child: ListView.separated(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: steps.length,
          // Dividers span the same 16px margins as the header and the icons,
          // rather than starting at the label and running off the right edge.
          separatorBuilder: (_, __) => Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.border),
          itemBuilder: (_, i) =>
              _StepRow(step: steps[i], onTap: () => onOpen(i)),
        ),
      ),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  final ToolStep step;
  final VoidCallback onTap;
  const _StepRow({required this.step, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (verb, object) = toolSentenceParts(step);
    final changes = step.tool == 'change_files'
        ? fileChanges([step])
        : const <FileChange>[];
    final added = changes.fold<int>(0, (sum, c) => sum + c.added);
    final removed = changes.fold<int>(0, (sum, c) => sum + c.removed);
    final openable = toolHasDetail(step);
    return InkWell(
      onTap: openable ? onTap : null,
      child: Padding(
        // Right inset centres the chevron under the header's close button.
        padding: const EdgeInsets.fromLTRB(16, 11, 23, 11),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: Center(
              child: step.running
                  ? Spinner(size: 14, color: AppColors.run)
                  : AppIcon(
                      step.failed ? 'alert-triangle' : toolIcon(step.tool),
                      size: 15,
                      color: step.failed ? AppColors.danger : AppColors.fg3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: verb,
                    style: sans(13,
                        weight: W.label,
                        color: step.failed ? AppColors.danger : AppColors.fg1)),
                if (object.isNotEmpty)
                  TextSpan(
                      text: ' $object', style: sans(13, color: AppColors.fg3)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (added + removed > 0) ...[
            const SizedBox(width: 8),
            Text('+$added', style: TS.meta(AppColors.ok)),
            const SizedBox(width: 4),
            Text('−$removed', style: TS.meta(AppColors.danger)),
          ],
          if (openable) ...[
            const SizedBox(width: 8),
            AppIcon('chevron-right', size: 13, color: AppColors.fg4),
          ] else
            const SizedBox(width: 21),
        ]),
      ),
    );
  }
}

class _StepDetail extends StatelessWidget {
  final ToolStep step;
  final int index;
  final int total;
  final ScrollController? scroll;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  const _StepDetail({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.scroll,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final (verb, object) = toolSentenceParts(step);
    // The command itself is in the body; the header carries its label only.
    final title = step.tool == 'bash'
        ? (object.isEmpty ? verb : 'Command')
        : (object.isEmpty ? verb : '$verb $object');
    return Column(children: [
      _SheetHeader(
        leading: IconBtn('chevron-left',
            size: 34, iconSize: 18, tooltip: 'Back', onTap: onBack),
        title: title,
        subtitle: null,
        compact: true,
        onClose: onClose,
      ),
      Expanded(
        child: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          // A running step shows what it already carries (a diff, a long
          // command); only an empty one says it is running.
          child: step.running && !toolHasDetail(step)
              ? Row(children: [
                  Spinner(size: 14, color: AppColors.run),
                  const SizedBox(width: 8),
                  Text('Running…', style: sans(13, color: AppColors.fg3)),
                ])
              : DefaultTextStyle(
                  style: mono(12, height: 1.45, color: AppColors.fg2),
                  child: safeToolDetailView(context,
                      tool: step.tool, args: step.args, result: step.result),
                ),
        ),
      ),
    ]);
  }
}

/// The phone's activity view: a summary, then every step on one timeline. A
/// step opens in place; failed and running steps open by themselves, so what
/// needs attention shows without a tap. "Show all" goes to the full detail.
class _Timeline extends StatefulWidget {
  final ToolBatch batch;
  final ScrollController? scroll;
  final VoidCallback? onClose;
  final ValueChanged<int> onShowAll;
  const _Timeline({
    super.key,
    required this.batch,
    required this.scroll,
    required this.onClose,
    required this.onShowAll,
  });

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final Map<int, bool> _choice = {};

  bool _isOpen(int i, ToolStep step) =>
      _choice[i] ?? (step.failed || (step.running && _hasOutput(step)));

  @override
  Widget build(BuildContext context) {
    final steps = widget.batch.steps;
    final running = widget.batch.running && steps.any((s) => s.running);
    final failed = steps.where((s) => s.failed).length;
    final status = [
      '${steps.length} ${steps.length == 1 ? 'step' : 'steps'}',
      if (failed > 0) '$failed failed',
      if (running) 'running' else if (failed == 0) 'all passed',
    ].join(' · ');
    final dot = running
        ? AppColors.run
        : failed > 0
            ? AppColors.danger
            : AppColors.ok;
    final commands = steps
        .where((s) => s.tool == 'bash' || s.tool == 'manage_process')
        .length;
    final searches = steps
        .where((s) => s.tool == 'web_search' || s.tool == 'web_read')
        .length;
    final files = fileChanges(steps);
    final added = files.fold<int>(0, (n, f) => n + f.added);
    final removed = files.fold<int>(0, (n, f) => n + f.removed);
    final chips = <Widget>[
      if (commands > 0)
        _chip(Text('$commands ${commands == 1 ? 'command' : 'commands'}',
            style: sans(12, color: AppColors.fg2))),
      if (files.isNotEmpty)
        _chip(Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${files.length} ${files.length == 1 ? 'file' : 'files'} ',
              style: sans(12, color: AppColors.fg2)),
          if (added > 0) Text('+$added ', style: sans(12, color: AppColors.ok)),
          if (removed > 0)
            Text('−$removed', style: sans(12, color: AppColors.danger)),
        ])),
      if (searches > 0)
        _chip(Text('$searches ${searches == 1 ? 'search' : 'searches'}',
            style: sans(12, color: AppColors.fg2))),
    ];
    final lastPassed = !running && failed == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.lineStrong,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activity',
                    style: sans(20, spacing: -0.4, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(status, style: sans(13, color: AppColors.fg3)),
                ]),
              ],
            ),
          ),
          if (widget.onClose != null)
            Material(
              color: AppColors.surface2,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onClose,
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(
                      child: AppIcon('x', size: 14, color: AppColors.fg3)),
                ),
              ),
            ),
        ]),
      ),
      if (chips.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: chips),
        ),
      const SizedBox(height: 14),
      Expanded(
        child: ListView.builder(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          itemCount: steps.length,
          itemBuilder: (_, i) => _TimelineStep(
            step: steps[i],
            last: i == steps.length - 1,
            passedDot: lastPassed && i == steps.length - 1,
            open: _isOpen(i, steps[i]),
            onToggle: () => setState(() => _choice[i] = !_isOpen(i, steps[i])),
            onShowAll: () => widget.onShowAll(i),
          ),
        ),
      ),
    ]);
  }

  Widget _chip(Widget child) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Center(widthFactor: 1, child: child),
      );
}

Map _data(ToolStep step) {
  final r = step.result;
  if (r is! Map) return const {};
  return r['data'] is Map ? r['data'] as Map : r;
}

String _output(ToolStep step) {
  final d = _data(step);
  final parts = [
    for (final key in const ['stdout', 'stderr', 'output', 'content', 'text'])
      (d[key] ?? '').toString().trimRight(),
    if (step.failed && step.result is Map)
      ((step.result as Map)['error'] ?? '').toString().trim(),
  ].where((s) => s.isNotEmpty);
  return parts.join('\n');
}

bool _hasOutput(ToolStep step) => _output(step).isNotEmpty;

class _TimelineStep extends StatelessWidget {
  final ToolStep step;
  final bool last;
  final bool passedDot;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onShowAll;
  const _TimelineStep({
    required this.step,
    required this.last,
    required this.passedDot,
    required this.open,
    required this.onToggle,
    required this.onShowAll,
  });

  String _sub() {
    final a = step.args is Map ? step.args as Map : const {};
    switch (step.tool) {
      case 'bash':
        return (a['command'] ?? '').toString().split('\n').first.trim();
      case 'change_files':
        final paths = {
          for (final c in step.changes) (c['path'] ?? '').toString()
        }..removeWhere((p) => p.isEmpty);
        return paths.length == 1 ? paths.first : '';
      default:
        final (_, object) = toolSentenceParts(step);
        return object;
    }
  }

  bool get _monoSub => step.tool == 'bash' || step.tool == 'change_files';

  Widget? _meta() {
    if (step.running) {
      return Text('running', style: sans(12, color: AppColors.run));
    }
    if (step.tool == 'change_files') {
      final f = fileChanges([step]);
      final add = f.fold<int>(0, (n, c) => n + c.added);
      final del = f.fold<int>(0, (n, c) => n + c.removed);
      if (add + del == 0) return null;
      return Text.rich(TextSpan(children: [
        if (add > 0)
          TextSpan(text: '+$add', style: sans(12, color: AppColors.ok)),
        if (add > 0 && del > 0) const TextSpan(text: ' '),
        if (del > 0)
          TextSpan(text: '−$del', style: sans(12, color: AppColors.danger)),
      ]));
    }
    final d = _data(step);
    final exit = (d['exit_code'] as num?)?.toInt();
    if (step.tool == 'bash' && exit != null) {
      return Text('exit $exit',
          style: sans(12,
              color: exit == 0 ? AppColors.fg4 : AppColors.danger,
              tabular: true));
    }
    final results = d['results'];
    if (results is List && results.isNotEmpty) {
      return Text('${results.length} results',
          style: sans(12, color: AppColors.fg4));
    }
    if (step.failed) {
      return Text('failed', style: sans(12, color: AppColors.danger));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (verb, object) = toolSentenceParts(step);
    final title = step.tool == 'change_files'
        ? (object.isEmpty ? verb : '$verb $object')
        : object.isEmpty
            ? verb
            : step.tool == 'bash'
                ? (step.running ? 'Running a command' : 'Ran a command')
                : verb.replaceFirst(RegExp(r' (for|of)$'), '');
    final sub = _sub();
    final meta = _meta();
    final dotColor = step.running
        ? AppColors.run
        : step.failed
            ? AppColors.danger
            : passedDot
                ? AppColors.ok
                : AppColors.fg4;
    final openable = toolHasDetail(step) || _hasOutput(step);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 12,
          child: Column(children: [
            const SizedBox(height: 7),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: step.running
                    ? [
                        BoxShadow(
                            color: AppColors.run.withValues(alpha: 0.22),
                            spreadRadius: 4)
                      ]
                    : null,
              ),
            ),
            if (!last)
              Expanded(
                child: Container(
                  width: 1,
                  margin: const EdgeInsets.only(top: 4),
                  color: AppColors.border2,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: openable ? onToggle : null,
                  borderRadius: BorderRadius.circular(R.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(15,
                                      height: 20 / 15,
                                      color: step.failed
                                          ? AppColors.diffDelFg
                                          : AppColors.fg1)),
                            ),
                            if (meta != null) ...[
                              const SizedBox(width: 10),
                              Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: meta),
                            ],
                          ]),
                      if (sub.isNotEmpty && sub != title) ...[
                        const SizedBox(height: 3),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _monoSub
                                ? mono(12, color: AppColors.fg4)
                                : sans(12, color: AppColors.fg4)),
                      ],
                    ],
                  ),
                ),
                if (open && openable) ...[
                  const SizedBox(height: 10),
                  _StepBody(step: step, onShowAll: onShowAll),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _StepBody extends StatelessWidget {
  final ToolStep step;
  final VoidCallback onShowAll;
  const _StepBody({required this.step, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final output = _output(step);
    final tail = step.tool != 'change_files' && output.isNotEmpty;
    final lines = output.split('\n');
    final shown = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
    Widget link(String label, VoidCallback onTap, {bool muted = false}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(label,
                style:
                    sans(13, color: muted ? AppColors.fg3 : AppColors.accent)),
          ),
        );
    if (!tail && !(step.running && output.isEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle(
            style: mono(12, height: 1.45, color: AppColors.fg2),
            child: safeToolDetailView(context,
                tool: step.tool, args: step.args, result: step.result),
          ),
          const SizedBox(height: 4),
          link('Show all', onShowAll),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tail)
            for (final line in shown)
              Text(line,
                  style: mono(11.5,
                      height: 18 / 11.5,
                      color:
                          RegExp(r'FAIL|error|panicked', caseSensitive: false)
                                  .hasMatch(line)
                              ? AppColors.diffDelFg
                              : AppColors.fg3))
          else if (step.running && output.isEmpty)
            Text('Waiting for output…', style: sans(13, color: AppColors.fg4))
          else
            DefaultTextStyle(
              style: mono(12, height: 1.45, color: AppColors.fg2),
              child: safeToolDetailView(context,
                  tool: step.tool, args: step.args, result: step.result),
            ),
          const SizedBox(height: 6),
          Row(children: [
            link('Show all', onShowAll),
            if (tail) ...[
              const SizedBox(width: 18),
              link('Copy', () {
                Clipboard.setData(ClipboardData(text: output));
                toast(context, 'Copied');
              }, muted: true),
            ],
          ]),
        ],
      ),
    );
  }
}
