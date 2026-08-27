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

class DesktopMissionControl extends StatefulWidget {
  const DesktopMissionControl({super.key});

  @override
  State<DesktopMissionControl> createState() => _DesktopMissionControlState();
}

class _DesktopMissionControlState extends State<DesktopMissionControl> {
  dynamic _task;
  QuestionItem? _question;
  dynamic _session;
  String? _kind;

  void _showTask(dynamic task) {
    setState(() {
      _task = task;
      _question = null;
      _session = null;
      _kind = 'task';
    });
  }

  void _showQuestion(QuestionItem q) {
    setState(() {
      _task = null;
      _question = q;
      _session = null;
      _kind = 'question';
    });
  }

  void _showSession(dynamic session) {
    setState(() {
      _task = null;
      _question = null;
      _session = session;
      _kind = 'session';
    });
  }

  void _clearInspector() {
    setState(() {
      _task = null;
      _question = null;
      _session = null;
      _kind = null;
    });
  }

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
                  _LeftRail(
                    state: state,
                    onTapTask: _showTask,
                    onTapSession: _showSession,
                  ),
                  VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ActivityFeed(
                            state: state,
                            onTapTask: _showTask,
                            onTapQuestion: _showQuestion,
                          ),
                        ),
                        Divider(height: 1, color: AppColors.border),
                        MissionComposer(state: state),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: AppColors.border),
                  _InspectorPane(
                    state: state,
                    kind: _kind,
                    task: _task,
                    question: _question,
                    session: _session,
                    onClear: _clearInspector,
                  ),
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
  const _LeftRail({
    required this.state,
    required this.onTapTask,
    required this.onTapSession,
  });
  final MissionControlState state;
  final void Function(dynamic task) onTapTask;
  final void Function(dynamic session) onTapSession;

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
            for (final t in state.activeTasks)
              _TaskRow(task: t, onTap: () => onTapTask(t)),
          const SizedBox(height: 24),
          const SectionLabel('Sessions'),
          const SizedBox(height: 8),
          if (state.sessions.isEmpty)
            _emptyHint('No sessions')
          else
            for (final s in state.sessions)
              _SessionRow(session: s, onTap: () => onTapSession(s)),
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
  const _TaskRow({required this.task, required this.onTap});
  final dynamic task;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
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
  const _SessionRow({required this.session, required this.onTap});
  final dynamic session;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
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

class _InspectorPane extends StatelessWidget {
  const _InspectorPane({
    required this.state,
    required this.kind,
    required this.task,
    required this.question,
    required this.session,
    required this.onClear,
  });
  final MissionControlState state;
  final String? kind;
  final dynamic task;
  final QuestionItem? question;
  final dynamic session;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: AppColors.surface1,
      child: switch (kind) {
        'task' => TaskInspector(task: task, state: state),
        'question' => _QuestionInspector(
            question: question!,
            state: state,
            onSent: onClear,
          ),
        'session' => _SessionInspector(session: session),
        _ => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Select a task, session, or question to inspect.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
      },
    );
  }
}

class _QuestionInspector extends StatefulWidget {
  const _QuestionInspector({
    required this.question,
    required this.state,
    required this.onSent,
  });
  final QuestionItem question;
  final MissionControlState state;
  final VoidCallback onSent;

  @override
  State<_QuestionInspector> createState() => _QuestionInspectorState();
}

class _QuestionInspectorState extends State<_QuestionInspector> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reply = _controller.text.trim();
    if (reply.isEmpty) return;
    widget.onSent();
    await widget.state.sendMessage(reply);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Agent is asking'),
          const SizedBox(height: 12),
          Text(widget.question.question, style: sans(14, color: AppColors.fg1)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
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
              onPressed: _send,
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
