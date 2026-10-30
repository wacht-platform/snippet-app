import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../mission_control/mission_control_state.dart'
    show isDedicatedMcSession;

class CreateTaskForm extends StatefulWidget {
  const CreateTaskForm({
    super.key,
    required this.client,
    this.onCreated,
  });
  final DaemonClient client;
  final VoidCallback? onCreated;

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

  Future<void> _loadSessions() async {
    try {
      final all = await widget.client.sessions();
      if (!mounted) return;
      final usable = all
          .where(
              (s) => !isDedicatedMcSession(s.id) && s.id != 'mission-control')
          .toList()
        ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
      setState(() => _sessions = usable);
    } catch (_) {}
  }

  Future<void> _pickSession(BuildContext anchor) async {
    if (_sessions.isEmpty) {
      setState(() => _error = 'No sessions to route into');
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: kMobile ? 280 : 240,
      maxWidth: 380,
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
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a title.');
      return;
    }
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      setState(() => _error = 'Choose the session that should do this.');
      return;
    }
    final description = _description.text.trim();
    final now = DateTime.now().toUtc().toIso8601String();
    final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final pending = TaskItem.fromJson({
      'id': pendingId,
      'title': title,
      'description': description,
      'status': 'todo',
      'created_by_kind': 'human',
      'created_at': now,
      'updated_at': now,
      'session_id': sessionId,
    });
    final client = widget.client;
    final feed = client.swr.entry<List<TaskItem>>('coordination:tasks');
    feed.mutate([...?feed.data, pending]);
    final root = Navigator.of(context, rootNavigator: true).context;
    if (widget.onCreated != null) {
      widget.onCreated!();
    } else {
      Navigator.of(context).pop(false);
    }
    try {
      final created = await client.createTask(
        title: title,
        sessionId: sessionId,
        description: description,
      );
      feed.mutate([
        for (final t in feed.data ?? const <TaskItem>[])
          t.id == pendingId ? created : t
      ]);
    } catch (e) {
      feed.mutate([
        for (final t in feed.data ?? const <TaskItem>[])
          if (t.id != pendingId) t
      ]);
      if (root.mounted) {
        toast(root, "Couldn't create “$title”: $e", danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding:
            EdgeInsets.fromLTRB(kMobile ? 16 : 12, 4, kMobile ? 16 : 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What needs doing, and which session should do it? The task is routed there and reports back.',
              style:
                  sans(kMobile ? 13 : 12, color: AppColors.fg3, height: 1.45),
            ),
            const SizedBox(height: 14),
            AppField(
              controller: _title,
              label: 'Title',
              hint: 'Ship the coordinator panel',
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text('Session',
                style: sans(12, weight: W.label, color: AppColors.fg3)),
            const SizedBox(height: 5),
            Material(
              color: AppColors.surface1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: AppColors.line),
              ),
              child: Builder(
                builder: (ctx) => InkWell(
                  onTap: _busy ? null : () => _pickSession(ctx),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Row(children: [
                      AppIcon('chat', size: 14, color: AppColors.fg3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_sessionLabel ?? 'Choose a session',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5,
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
              label: 'Briefing',
              hint:
                  'Goal, what done looks like, and the context the agent needs.',
              minLines: 4,
              maxLines: 8,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: sans(12, color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
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
