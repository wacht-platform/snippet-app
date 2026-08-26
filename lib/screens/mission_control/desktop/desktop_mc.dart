/// Desktop Mission Control — three-pane layout: a left rail with the
/// task/session lists, a center pane with the live activity feed + composer,
/// and a right inspector that opens when a task is selected.
library;

import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets.dart';
import '../mission_control_screen.dart' show ChangeNotifierProvider;
import '../mission_control_state.dart';
import '../widgets/mission_control_header.dart';
import '../widgets/activity_feed.dart';
import '../widgets/mission_composer.dart';
import '../widgets/task_inspector.dart';

class DesktopMissionControl extends StatelessWidget {
  const DesktopMissionControl({super.key});

  @override
  Widget build(BuildContext context) {
    final state = ChangeNotifierProvider.of<MissionControlState>(context);
    return Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        child: Column(
          children: [
            MissionControlHeader.full(state: state),
            Expanded(
              child: Row(
                children: [
                  _LeftRail(state: state),
                  VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ActivityFeed(
                            state: state,
                            onTapTask: (task) =>
                                _DesktopInspectorHost.of(context).show(task),
                            onTapQuestion: (q) =>
                                _DesktopInspectorHost.of(context)
                                    .showQuestion(q),
                          ),
                        ),
                        Divider(height: 1, color: AppColors.border),
                        MissionComposer(state: state),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: AppColors.border),
                  _DesktopInspectorHost(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeftRail extends StatelessWidget {
  const _LeftRail({required this.state});
  final MissionControlState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: AppColors.surface1,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          const SectionLabel('Active tasks'),
          const SizedBox(height: 8),
          if (state.activeTasks.isEmpty)
            _emptyHint('No active tasks')
          else
            for (final t in state.activeTasks) _TaskRow(task: t),
          const SizedBox(height: 24),
          const SectionLabel('Sessions'),
          const SizedBox(height: 8),
          if (state.sessions.isEmpty)
            _emptyHint('No sessions')
          else
            for (final s in state.sessions) _SessionRow(session: s),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(text, style: sans(12, color: AppColors.fg4)),
      );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final dynamic task;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _DesktopInspectorHost.of(context).show(task),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor(task.status as String),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'in_progress':
        return AppColors.run;
      case 'done':
      case 'completed':
        return AppColors.ok;
      case 'blocked':
      case 'failed':
      case 'cancelled':
        return AppColors.danger;
      default:
        return AppColors.fg4;
    }
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final dynamic session;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _DesktopInspectorHost.of(context).showSession(session),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.ok,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (session.title as String).isEmpty
                        ? session.folder as String
                        : session.title as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Host for the right-hand inspector. Lives below the screen in a
/// [InheritedNotifierProvider] so any child can read/write the current
/// selection.
class _DesktopInspectorHost extends StatefulWidget {
  const _DesktopInspectorHost({this.state});
  final MissionControlState? state;

  /// Walk the widget tree to find a host; create one if missing. Cheaper than
  /// a full inherited-widget dance for this single use site.
  static _DesktopInspectorController of(BuildContext context) =>
      _ControllerProvider.of(context);

  @override
  State<_DesktopInspectorHost> createState() => _DesktopInspectorHostState();
}

class _DesktopInspectorHostState extends State<_DesktopInspectorHost> {
  dynamic _selected;
  QuestionItem? _question;
  dynamic _session;
  String? _kind;

  void show(dynamic task) {
    setState(() {
      _selected = task;
      _question = null;
      _session = null;
      _kind = 'task';
    });
  }

  void showQuestion(QuestionItem q) {
    setState(() {
      _selected = null;
      _question = q;
      _session = null;
      _kind = 'question';
    });
  }

  void showSession(dynamic session) {
    setState(() {
      _selected = null;
      _question = null;
      _session = session;
      _kind = 'session';
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _DesktopInspectorController(
      show: show,
      showQuestion: showQuestion,
      showSession: showSession,
    );
    return _ControllerProvider(
      controller: controller,
      child: Container(
        width: 320,
        color: AppColors.surface1,
        child: () {
          switch (_kind) {
            case 'task':
              return TaskInspector(task: _selected, state: widget.state);
            case 'question':
              return _QuestionInspector(
                  question: _question!, state: widget.state);
            case 'session':
              return _SessionInspector(session: _session);
            default:
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Select a task, session, or question to inspect.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
          }
        }(),
      ),
    );
  }
}

class _QuestionInspector extends StatelessWidget {
  const _QuestionInspector({required this.question, required this.state});
  final QuestionItem question;
  final MissionControlState? state;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Agent is asking'),
          const SizedBox(height: 12),
          Text(question.question, style: sans(14, color: AppColors.fg1)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: 'Type your reply…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final reply = controller.text.trim();
                if (reply.isEmpty) return;
                Navigator.of(context).maybePop();
                if (state != null) await state!.sendMessage(reply);
              },
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionInspector extends StatelessWidget {
  const _SessionInspector({required this.session});
  final dynamic session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Session'),
          const SizedBox(height: 12),
          Text(
            (session.title as String).isEmpty
                ? session.folder as String
                : session.title as String,
            style: sans(15, weight: FontWeight.w600, color: AppColors.fg1),
          ),
          const SizedBox(height: 4),
          Text(session.folder as String, style: mono(11, color: AppColors.fg3)),
          const SizedBox(height: 12),
          Text('Status: ${session.status}',
              style: sans(13, color: AppColors.fg2)),
          if ((session.taskCount as int) > 0)
            Text('${session.taskCount} active task(s)',
                style: sans(13, color: AppColors.fg2)),
        ],
      ),
    );
  }
}

class _DesktopInspectorController {
  _DesktopInspectorController({
    required this.show,
    required this.showQuestion,
    required this.showSession,
  });
  final void Function(dynamic task) show;
  final void Function(QuestionItem q) showQuestion;
  final void Function(dynamic session) showSession;
}

class _ControllerProvider extends InheritedWidget {
  const _ControllerProvider({required this.controller, required super.child});
  final _DesktopInspectorController controller;

  static _DesktopInspectorController of(BuildContext context) {
    final inh =
        context.dependOnInheritedWidgetOfExactType<_ControllerProvider>();
    assert(inh != null, 'No _ControllerProvider in context');
    return inh!.controller;
  }

  @override
  bool updateShouldNotify(_ControllerProvider oldWidget) => false;
}
