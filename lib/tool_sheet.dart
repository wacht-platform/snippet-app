import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
              child: open == null
                  ? _StepList(
                      key: const ValueKey(-1),
                      batch: batch,
                      scroll: widget.scroll,
                      onClose: widget.docked ? null : widget.onClose,
                      onOpen: _show,
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
  final VoidCallback? onClose;
  const _SheetHeader({
    this.leading,
    required this.title,
    this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (kMobile)
        Padding(
          padding: const EdgeInsets.only(top: 8),
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
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
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
  const _StepList({
    super.key,
    required this.batch,
    required this.scroll,
    required this.onClose,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final steps = batch.steps;
    final failed = steps.where((s) => s.failed).length;
    final running = batch.running && steps.any((s) => s.running);
    // The list itself shows what ran; the header names it and flags state.
    final subtitle = [
      if (failed > 0) '$failed failed',
      if (running) 'running',
    ].join(' · ');
    return Column(children: [
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
          separatorBuilder: (_, __) => Container(
              height: 1,
              margin: const EdgeInsets.only(left: 44),
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
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
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
