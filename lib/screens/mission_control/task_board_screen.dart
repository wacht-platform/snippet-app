import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../panel.dart';
import '../../platform.dart';
import '../shell_nav.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'task_detail_screen.dart';

/// The task board — where a human files work.
///
/// This replaces the coordination board. That was a single global room every
/// participant had to read; a task is the unit a person actually thinks in, and
/// each task owns its own conversation (see [TaskDetailScreen]), so an agent
/// working on one task is not woken by every other task's traffic.
///
/// Columns on a wide window, a status-grouped list on a narrow one: the same
/// [TaskStatus] order drives both, so the two cannot disagree about what comes
/// first.
class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.refreshSignal,
  });

  final DaemonClient client;

  /// When embedded in the hub, suppress our own Scaffold/AppBar.
  final bool embedded;

  /// Bumped by the host to request a refetch.
  final ValueNotifier<int>? refreshSignal;

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen> {
  List<TaskItem> tasks = const [];
  bool loading = true;
  String? error;

  /// Auto-refresh cadence. 25s sits inside the 20–30s window the board asked
  /// for; tune it here.
  static const _autoRefreshInterval = Duration(seconds: 25);

  Timer? _autoRefreshTimer;

  /// Guards against overlapping fetches: a background tick that lands while a
  /// request is already in flight is dropped rather than stacked.
  bool _fetching = false;

  /// Statuses to show. EMPTY means "every column" — the inverse of the old
  /// single nullable filter, and what makes multi-select work.
  Set<TaskStatus> filter = {};

  @override
  void initState() {
    super.initState();
    refresh();
    widget.refreshSignal?.addListener(refresh);
    _autoRefreshTimer =
        Timer.periodic(_autoRefreshInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    widget.refreshSignal?.removeListener(refresh);
    super.dispose();
  }

  /// User-initiated load: may show the full-screen spinner and may report
  /// errors. Pull-to-refresh and the first paint both go through here.
  Future<void> refresh() => _load(silent: false);

  /// Fetch tasks. [silent] is the background/auto-refresh path, and it differs
  /// from the user-initiated one in three ways that matter:
  ///  - it never touches [loading], so it cannot blank the list it updates;
  ///  - it swallows transient failures instead of replacing the board with an
  ///    error state every 25 seconds;
  ///  - it bails if a fetch is already running, so ticks cannot stack.
  Future<void> _load({required bool silent}) async {
    if (_fetching) return;
    _fetching = true;
    if (!silent && mounted) setState(() => loading = tasks.isEmpty);
    try {
      final fetched = await widget.client.tasks();
      if (!mounted) return;
      setState(() {
        tasks = fetched;
        error = null;
      });
    } catch (e) {
      // Background failures are dropped: a stale-but-visible board beats an
      // error screen the user never asked for. Only an explicit load reports.
      if (!silent && mounted) setState(() => error = '$e');
    } finally {
      _fetching = false;
      if (!silent && mounted) setState(() => loading = false);
    }
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context,
      title: 'New task',
      child: CreateTaskForm(client: widget.client),
    );
    if (created == true) await refresh();
  }

  Future<void> _open(TaskItem task) async {
    await presentScreen(
      context,
      style: PanelStyle.drawer,
      maxWidth: 720,
      maxHeight: 820,
      builder: (_, close) => TaskDetailScreen(
        client: widget.client,
        taskId: task.id,
        // The board may have changed while the detail was open, so the list is
        // refetched on close rather than trusting a local edit.
        onClose: () {
          close();
          refresh();
        },
      ),
    );
    if (mounted) await refresh();
  }

  /// Empty [filter] means every column; otherwise only the selected statuses.
  List<TaskItem> get _visible => filter.isEmpty
      ? tasks
      : tasks.where((t) => filter.contains(t.status)).toList();

  /// Counts per column across ALL tasks, so the panel beside a label always
  /// shows the column's true size rather than the filtered subset.
  Map<TaskStatus, int> get _counts => {
        for (final s in TaskStatus.values)
          s: tasks.where((t) => t.status == s).length,
      };

  Future<void> _openFilter() async {
    final picked = await showAppSheet<Set<TaskStatus>>(
      context,
      title: 'Filter by status',
      child: _FilterPanel(selected: filter, counts: _counts),
    );
    if (picked != null && mounted) setState(() => filter = {...picked});
  }

  /// The filter affordance, defined once for both hosts. The standalone route
  /// puts it in `SnAppBar.actions`; the embedded pane, which has no bar of its
  /// own, renders it in a slim band so the control is not lost when embedded.
  ///
  /// `active` is a surface STEP, not the accent hue: the doc reserves the accent
  /// for state, and "a filter is applied" is selection, not state.
  Widget _filterButton() => IconBtn('sliders',
      // 16px glyph in a 24px slot — the doc's icon relationship.
      size: kMobile ? M.minTarget : 24,
      iconSize: 16,
      active: filter.isNotEmpty,
      tooltip:
          filter.isEmpty ? 'Filter' : 'Filter (${filter.length} selected)',
      onTap: _openFilter);

  @override
  Widget build(BuildContext context) {
    // The list belongs to the reading plane; the filter lives in the bar above
    // it, so exactly one surface step separates the two and no hairline is
    // needed. Painted explicitly rather than inherited: the embedded host is a
    // canvas pane and the standalone route is a bg scaffold, and the two must
    // still read the same.
    final list = ColoredBox(
      color: AppColors.canvas,
      child: _content(),
    );

    if (widget.embedded) {
      // The pane host draws its own strip, so there is no `SnAppBar` to hang the
      // filter on. A slim chrome band keeps the control reachable — otherwise
      // embedding would silently drop the page's only filter affordance.
      return ColoredBox(
        color: AppColors.bg,
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: _filterButton(),
            ),
          ),
          Expanded(child: list),
        ]),
      );
    }

    return Scaffold(
      // bg, not canvas: the notch/status-bar strip sits on the BAR's plane, so
      // there is no third rung above the list.
      backgroundColor: AppColors.bg,
      // REQUIRED, not cosmetic: the Material `AppBar` this replaced reserved the
      // status bar's height for us. A bare `Column` started at y=0, so Android's
      // clock and carrier icons drew straight over the title.
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SnAppBar(
            title: 'Tasks',
            // The doc's page title is 20px; SnAppBar defaults to 17. Its WEIGHT
            // stays at the app's `display()` 500 rather than the doc's 600 —
            // forcing 600 would mean either changing SnAppBar for every screen
            // or bypassing the shared helper, and both reach outside this page.
            titleSize: 20,
            background: AppColors.bg,
            bordered: false,
            actions: [
              // The filter lives IN the bar rather than as a row of pills above
              // the list: one control that opens a panel replaces the scrolling
              // chip row entirely. There is deliberately no refresh icon —
              // pull-to-refresh and the 25s auto-refresh cover it.
              _filterButton(),
              const SizedBox(width: 6),
              // The action sits IN the bar rather than floating over the list: a
              // Material FAB carried an elevation shadow (the doc has none) and
              // the accent fill, which this app reserves for state.
              Btn('New task',
                  small: true,
                  icon: 'plus',
                  variant: BtnVariant.surface,
                  onTap: _create),
              const SizedBox(width: 2),
            ],
          ),
          Expanded(child: list),
        ]),
      ),
    );
  }

  /// The list area: spinner, error, or the grouped rows.
  ///
  /// Split out of `build` so the embedded and standalone hosts share ONE
  /// definition of the content — the two had to agree about the filter bar's
  /// plane, and duplicating it is how they drift.
  Widget _content() => loading
      ? const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)))
      : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error!,
                      textAlign: TextAlign.center,
                      // 13, not 12.5: the doc's scale is 11-13 with no half
                      // steps.
                      style: sans(13, color: AppColors.danger)),
                  const SizedBox(height: 12),
                  Btn('Retry', small: true, onTap: refresh),
                ]),
              ),
            )
          : _list();

  /// Empty-state title for a filtered board: names the single column when one
  /// is selected, and counts when several are.
  String _nothingTitle() {
    if (filter.length == 1) return 'Nothing in ${filter.first.label}';
    return 'Nothing in ${filter.length} columns';
  }

  Widget _list() {
    final visible = _visible;
    if (visible.isEmpty) {
      // Two different empties: a board with nothing on it is a prompt to start,
      // a filter with nothing is a prompt to widen. Saying "no tasks" for both
      // hides which one you are looking at. With multi-select the filtered case
      // has to name zero, one, or several columns.
      return EmptyState(
        icon: 'layers',
        title: filter.isEmpty ? 'No tasks yet' : _nothingTitle(),
        body: filter.isEmpty
            ? 'Create a task and Mission Control picks it up.'
            : 'Try another column, or clear the filter.',
      );
    }
    // Grouped even when filtered, so the section header still tells you which
    // column you are reading.
    final groups = <TaskStatus, List<TaskItem>>{};
    for (final s in TaskStatus.values) {
      final inGroup = visible.where((t) => t.status == s).toList();
      if (inGroup.isNotEmpty) groups[s] = inGroup;
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        // The 96 bottom inset was clearance for the floating button; with the
        // action in the bar it is just dead space under the last row.
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final entry in groups.entries) ...[
            _StatusHeader(status: entry.key, count: entry.value.length),
            for (final task in entry.value)
              _TaskRow(task: task, onTap: () => _open(task)),
          ],
        ],
      ),
    );
  }
}

/// Multi-select status filter, presented as a panel.
///
/// Replaces the scrolling chip row: one icon in the bar opens this, and the
/// categories the row used to scatter are now visible together with their live
/// counts. Selection is a `Set`, so several columns can be read at once — an
/// empty set means "every column".
class _FilterPanel extends StatefulWidget {
  const _FilterPanel({required this.selected, required this.counts});

  final Set<TaskStatus> selected;
  final Map<TaskStatus, int> counts;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final Set<TaskStatus> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "All" lives INSIDE the panel rather than as a pill beside the
          // categories. Clearing the set IS selecting every column, so this row
          // is selected exactly when nothing is filtered.
          _row(
            label: 'All statuses',
            selected: _selected.isEmpty,
            onTap: () => setState(() => _selected.clear()),
          ),
          const SizedBox(height: 2),
          for (final s in TaskStatus.values)
            _row(
              label: s.label,
              count: widget.counts[s] ?? 0,
              // State stays visible, but as a MARK rather than by tinting the
              // label — colour is state here, not decoration.
              dot: statusColor(s),
              selected: _selected.contains(s),
              onTap: () => setState(() {
                if (!_selected.remove(s)) _selected.add(s);
              }),
            ),
          const SizedBox(height: 14),
          // Labelled "Apply", not "Done": the panel already has a `Done` status
          // row, and two identical labels would be ambiguous to both a reader
          // and a widget test.
          Btn('Apply',
              full: true,
              onTap: () => Navigator.pop<Set<TaskStatus>>(context, _selected)),
        ],
      );

  Widget _row({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    Color? dot,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          // A phone touch target; compact on desktop.
          height: kMobile ? M.minTarget : 34,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            // Separation by surface STEP, never a hairline and never the accent
            // hue — the doc reserves the accent for state, and the selected row
            // is the ladder's "active row" rung.
            color: selected ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            // The dot slot is reserved even when there is no dot, so every
            // label shares one left edge whether or not it carries a mark.
            SizedBox(
              width: 6,
              child: dot == null
                  ? null
                  : Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: selected ? W.label : W.body,
                      // The normal text ramp: white is the selected/active row,
                      // and the rest default to the doc's light grey.
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              // A count is information, not a placeholder: the muted ramp.
              Text('$count', style: sans(11, color: AppColors.fg3)),
            ],
            // Selection is carried by the surface step AND a mark, so the state
            // is unambiguous where the step alone is subtle. 16px glyph in a
            // 24px slot — the doc's icon relationship.
            SizedBox(
              width: 24,
              child: selected
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: AppIcon('check', size: 16),
                    )
                  : null,
            ),
          ]),
        ),
      );
}

/// The colour a column is drawn in. `in_progress` is amber and `blocked` is the
/// danger hue because those are the two a person needs to notice.
Color statusColor(TaskStatus status) => switch (status) {
      TaskStatus.todo => AppColors.fg3,
      TaskStatus.inProgress => AppColors.run,
      TaskStatus.blocked => AppColors.danger,
      TaskStatus.done => AppColors.ok,
      TaskStatus.cancelled => AppColors.fg4,
    };

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status, required this.count});
  final TaskStatus status;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        // 12 left, so the status DOT sits at the same x as the row TITLES below
        // it (list inset 12 + row padding 12) — the doc's rule that a header and
        // its rows share one left edge.
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: Row(children: [
          // State stays a MARK. The doc's section marker slot is its own thing;
          // a 6px dot is the app's existing status mark.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: statusColor(status), shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(status.label.toUpperCase(),
              // The doc's 11px label is INTER 500 at #C1C1C1, not Geist and not
              // the muted grey: `fg2` IS #C1C1C1 in this theme. Tracking comes
              // from `_tracking`, which already gives -0.05 at 11px — the
              // measured value. The previous +0.5 was tracked OUT, the opposite
              // direction, and tightens small caps.
              style: inter(11, weight: W.label, color: AppColors.fg2)),
          const SizedBox(width: 6),
          // A count is information, not a placeholder: the muted tone (`fg3`),
          // never `fg4` which is the disabled/placeholder ramp.
          Text('$count', style: sans(11, color: AppColors.fg3)),
        ]),
      );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});
  final TaskItem task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        // The doc's row gap is 8; between 26px rows a hair more reads as a list
        // rather than a stack of cards.
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          // The doc puts CARDS on the chrome rung, and separation comes from
          // that step rather than a hairline — this row had the fill right and
          // the border was never there.
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(R.card),
            child: Container(
              // The doc's row metric: 26px tall, radius 8, `5px 12px`. Phone
              // keeps its own touch height — 26 is a desktop measurement and
              // sits well under the 44px minimum target.
              height: kMobile ? M.rowHeight : kNavRowHeight,
              padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
              child: Row(children: [
                // Priority is a mark, not a badge: at 0 (the default) it draws
                // nothing, so an ordinary task stays quiet and a raised one
                // stands out without every row carrying an empty chip.
                if (task.priority > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(R.xs)),
                    child: Text('P${task.priority}',
                        // 11 is the doc's type floor; 10 was below it.
                        style:
                            sans(11, weight: W.label, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The doc's row title: 13 / 500 / #C1C1C1 (`fg2`).
                      // 13.5 was off the scale, and white is reserved for the
                      // active row and the page title — a resting row is not it.
                      style: sans(13, weight: W.label, color: AppColors.fg2)),
                ),
                const SizedBox(width: 8),
                // 16px glyph, never filling its slot.
                AppIcon('chevron-right', size: 16, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
      );
}

/// Describe a task in prose; the daemon owns id, thread and initial column.
///
/// Shared shape with the agent form: one field that matters, the rest derived.
class CreateTaskForm extends StatefulWidget {
  const CreateTaskForm({super.key, required this.client});
  final DaemonClient client;

  @override
  State<CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends State<CreateTaskForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    // Validated on submit, not by a disabled button: `AppField` exposes no
    // `onChanged`, so a length-gated button could never re-enable as you type.
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.createTask(
        title: title,
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What needs doing? Mission Control reads this and works out which agents it needs.',
              style: sans(13, color: AppColors.fg3, height: 1.45),
            ),
            const SizedBox(height: 18),
            AppField(
              controller: _title,
              label: 'Title',
              hint: 'Ship the coordinator panel',
              autofocus: true,
            ),
            const SizedBox(height: 12),
            AppField(
              controller: _description,
              label: 'Details',
              hint:
                  'What does done look like? Anything an agent would need to know.',
              minLines: 4,
              maxLines: 8,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            Btn(
              _busy ? 'Creating…' : 'Create task',
              full: true,
              disabled: _busy,
              icon: 'plus',
              onTap: _submit,
            ),
          ],
        ),
      );
}
