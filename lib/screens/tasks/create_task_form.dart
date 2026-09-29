import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../mission_control/mission_control_state.dart' show isDedicatedMcSession;

/// Describe a task in prose and pick the session that will do it.
///
/// The session is part of filing, not an afterthought: a task with no target can
/// never be dispatched, so the daemon refuses one. Picking here is what makes
/// the row real work rather than a note on the board.
class CreateTaskForm extends StatefulWidget {
  const CreateTaskForm({super.key, required this.client});
  final DaemonClient client;

  @override
  State<CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends State<CreateTaskForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<SessionInfo> _sessions = const [];
  String? _sessionId;
  String? _sessionLabel;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  /// Sessions to route into. Mission Control is excluded: it coordinates, so
  /// naming it as the worker would file work onto the coordinator itself.
  Future<void> _loadSessions() async {
    try {
      final all = await widget.client.sessions();
      if (!mounted) return;
      final usable = all
          .where((s) =>
              !isDedicatedMcSession(s.id) && s.id != 'mission-control')
          .toList()
        ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
      setState(() => _sessions = usable);
    } catch (_) {
      // A failed list is not fatal: the form still opens and the picker will be
      // empty, which the submit check reports.
    }
  }

  Future<void> _pickSession(BuildContext anchor) async {
    if (_sessions.isEmpty) {
      setState(() => _error = 'No sessions to route into');
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 280,
      maxWidth: 400,
      items: [
        appMenuHeading<String>('Send this work to'),
        for (final s in _sessions)
          appMenuRow<String>(
            value: s.id,
            icon: 'chat',
            label: s.title.trim().isEmpty ? s.id : s.title,
            description: s.projectFolder.trim().isEmpty
                ? s.id
                : s.inWorktree
                    ? '${s.projectFolder} · ${s.branch ?? 'worktree'}'
                    : s.projectFolder,
            selected: s.id == _sessionId,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    for (final s in _sessions) {
      if (s.id == picked) {
        setState(() {
          _sessionId = s.id;
          _sessionLabel = s.title.trim().isEmpty ? s.id : s.title;
          _error = null;
        });
        return;
      }
    }
  }

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
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      setState(() => _error = 'Choose the session that should do this.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.createTask(
        title: title,
        sessionId: sessionId,
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
              'What needs doing, and which session should do it? The task is routed there and reports back.',
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
            Text('session', style: mono(10, color: AppColors.fg3)),
            const SizedBox(height: 4),
            Material(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              child: Builder(
                builder: (ctx) => InkWell(
                  onTap: _busy ? null : () => _pickSession(ctx),
                  borderRadius: BorderRadius.circular(R.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 11),
                    child: Row(children: [
                      AppIcon('chat', size: 15, color: AppColors.fg3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_sessionLabel ?? 'Choose a session',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                color: _sessionLabel == null
                                    ? AppColors.fg4
                                    : AppColors.fg1)),
                      ),
                      AppIcon('chevron-down', size: 13, color: AppColors.fg4),
                    ]),
                  ),
                ),
              ),
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
