import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Tools whose result is only an acknowledgement: the row's sentence already
/// says everything, so there is nothing to open.
const ackTools = {
  'assign_task_agent',
  'transfer_mission_task_lease',
  'transfer_task_session_lease',
  'claim_and_dispatch_task',
  'archive_mission_session',
  'create_mission_session',
  'register_agent',
  'set_session_title',
};

/// Whether a coordination tool's detail would show anything, or null when
/// [tool] is not one of them. Empty lists and blank messages count as nothing.
bool? coordinationHasDetail(String tool, Map? a, Map? d) {
  bool text(dynamic v) => v != null && v.toString().trim().isNotEmpty;
  bool list(dynamic v) => v is List ? v.isNotEmpty : v is Map && v.isNotEmpty;
  switch (tool) {
    case 'list_mission_tasks':
      return list(d?['tasks']);
    case 'list_sessions':
      return list(d?['sessions']);
    case 'list_coordination_agents':
      return list(d?['agents']);
    case 'list_profiles':
      return list(d?['profiles']);
    case 'read_coordination_board':
      return list(d?['outstanding']) || list(d?['entries']);
    case 'read_coordination_thread':
    case 'read_agent_thread':
      return list(d?['messages']);
    case 'read_agent_inbox':
      return list(d?['threads']);
    case 'create_mission_task':
    case 'update_mission_task':
    case 'retry_mission_task':
    case 'cancel_mission_task':
      return d?['task'] is Map;
    case 'report_mission_task':
      return d?['task'] is Map || text(a?['summary']);
    case 'inspect_task':
    case 'inspect_session':
      return d != null && d.isNotEmpty;
    case 'send_agent_message':
    case 'post_coordination_message':
    case 'post_task_coordination':
      return text(a?['body']);
    case 'message_mission_control':
      return text(a?['message']);
    case 'record_coordination_note':
      return text(a?['summary']);
    case 'create_recurring_job':
      return text(a?['prompt']) || text(a?['schedule']);
  }
  return null;
}

/// The detail body for Mission Control and coordination tools, or null when
/// [tool] is not one of them.
List<Widget>? coordinationToolBody(
    BuildContext context, String tool, Map? a, Map? d) {
  String arg(String k) => a?[k]?.toString().trim() ?? '';
  switch (tool) {
    case 'list_mission_tasks':
      return [
        _ItemList(
          items: _maps(d?['tasks']),
          empty: 'No tasks on the board.',
          title: (t) => _s(t['title']),
          status: (t) => _s(t['status']),
          meta: (t) => _short(_s(t['id'])),
        ),
      ];
    case 'create_mission_task':
    case 'update_mission_task':
    case 'retry_mission_task':
    case 'cancel_mission_task':
    case 'report_mission_task':
      final task = d?['task'];
      return [
        if (task is Map) _TaskSummary(task),
        if (tool == 'report_mission_task' && arg('summary').isNotEmpty)
          _Section('Report', _Markdown(arg('summary'))),
      ];
    case 'inspect_task':
      return d == null ? null : [_TaskSummary(d)];
    case 'list_sessions':
      return [
        _ItemList(
          items: _maps(d?['sessions']),
          empty: 'No sessions.',
          title: (s) => _s(s['title']).isEmpty ? _s(s['id']) : _s(s['title']),
          status: (s) => _s(s['status']),
          meta: (s) => lastPathSegment(_s(s['workspace']), ifEmpty: ''),
        ),
      ];
    case 'inspect_session':
      if (d == null) return null;
      final question = _s(d['pending_question']);
      return [
        _Header(
          title: _s(d['title']).isEmpty ? 'Session' : _s(d['title']),
          status: _s(d['status']),
          meta: _s(d['workspace']),
        ),
        if (question.isNotEmpty) _Section('Waiting on', _Markdown(question)),
      ];
    case 'list_coordination_agents':
      return [
        _ItemList(
          items: _maps(d?['agents']),
          empty: 'No agents registered.',
          title: (x) => _s(x['display_name']).isEmpty
              ? _s(x['id'])
              : _s(x['display_name']),
          status: (x) => _s(x['status']),
          meta: (x) => _s(x['role']).isEmpty ? _s(x['id']) : _s(x['role']),
        ),
      ];
    case 'list_profiles':
      final def = _s(d?['default']);
      final raw = d?['profiles'];
      final names = raw is List
          ? [for (final p in raw) p is Map ? _s(p['name']) : _s(p)]
          : raw is Map
              ? [for (final k in raw.keys) k.toString()]
              : const <String>[];
      return [
        _ItemList(
          items: [
            for (final n in names.where((n) => n.isNotEmpty)) {'name': n}
          ],
          empty: 'No profiles configured.',
          title: (p) => _s(p['name']),
          status: (p) => _s(p['name']) == def ? 'default' : '',
          meta: (_) => '',
        ),
      ];
    case 'read_coordination_board':
      final outstanding = d?['outstanding'];
      return [
        _ItemList(
          items: _maps(outstanding ?? d?['entries']),
          empty: outstanding != null
              ? 'Nothing outstanding.'
              : 'Nothing on the board yet.',
          title: (e) => _s(e['summary']),
          status: (e) => _s(e['kind']),
          meta: (e) => lastPathSegment(_s(e['workspace']), ifEmpty: ''),
          multiline: true,
        ),
      ];
    case 'read_coordination_thread':
    case 'read_agent_thread':
      return [_Messages(_maps(d?['messages']))];
    case 'read_agent_inbox':
      return [
        _ItemList(
          items: _maps(d?['threads']),
          empty: 'Inbox is empty.',
          title: (t) =>
              _s(t['peer']).isNotEmpty ? _s(t['peer']) : _s(t['thread_id']),
          status: (t) => _s(t['unread']).isEmpty || _s(t['unread']) == '0'
              ? ''
              : '${_s(t['unread'])} unread',
          meta: (t) => _s(t['last_body'] ?? t['preview']),
        ),
      ];
    case 'send_agent_message':
    case 'post_coordination_message':
    case 'post_task_coordination':
      return [_Markdown(arg('body'))];
    case 'message_mission_control':
      return [_Markdown(arg('message'))];
    case 'record_coordination_note':
      return [_Markdown(arg('summary'))];
    case 'create_recurring_job':
      return [
        _Header(
            title: arg('title').isEmpty ? 'Recurring job' : arg('title'),
            status: '',
            meta: arg('schedule')),
        if (arg('prompt').isNotEmpty)
          _Section('Prompt', _Markdown(arg('prompt'))),
      ];
  }
  return null;
}

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
List<Map> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().toList() : const <Map>[];

Color _statusColor(String status) {
  final s = status.toLowerCase();
  if (const {'done', 'completed', 'complete', 'reported', 'default'}
      .contains(s)) {
    return AppColors.ok;
  }
  if (const {
    'running',
    'active',
    'working',
    'in_progress',
    'dispatched',
    'claimed'
  }.contains(s)) {
    return AppColors.run;
  }
  if (const {'failed', 'blocked', 'error', 'cancelled'}.contains(s)) {
    return AppColors.danger;
  }
  if (s.contains('unread') || s == 'waiting_for_input') return AppColors.accent;
  return AppColors.fg3;
}

String _statusLabel(String status) => status.replaceAll('_', ' ');

class _ItemList extends StatelessWidget {
  final List<Map> items;
  final String empty;
  final String Function(Map) title;
  final String Function(Map) status;
  final String Function(Map) meta;
  final bool multiline;
  const _ItemList({
    required this.items,
    required this.empty,
    required this.title,
    required this.status,
    required this.meta,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(empty, style: TS.meta());
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(height: 1, color: AppColors.border),
          _row(items[i]),
        ],
      ]),
    );
  }

  Widget _row(Map item) {
    final st = status(item);
    final m = meta(item);
    final t = title(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: multiline ? 6 : 0),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: _statusColor(st), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.isEmpty ? '(untitled)' : t,
                    maxLines: multiline ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, height: 1.4, color: AppColors.fg1)),
                if (m.isNotEmpty)
                  Text(m,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(10, color: AppColors.fg3)),
              ],
            ),
          ),
          if (st.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(_statusLabel(st), style: mono(10, color: _statusColor(st))),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String status;
  final String meta;
  const _Header(
      {required this.title, required this.status, required this.meta});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(title,
                  style: sans(14, weight: W.label, color: AppColors.fg1)),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(_statusLabel(status),
                    style: mono(10, color: _statusColor(status))),
              ),
            ],
          ]),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta, style: mono(10, color: AppColors.fg3)),
          ],
        ],
      );
}

class _TaskSummary extends StatelessWidget {
  final Map task;
  const _TaskSummary(this.task);

  @override
  Widget build(BuildContext context) {
    final id = _s(task['id'] ?? task['task_id']);
    final result = task['result'];
    final resultText =
        result is Map ? _s(result['summary'] ?? result['text']) : _s(result);
    final paths = task['owned_paths'] is List
        ? [for (final p in task['owned_paths'] as List) _s(p)]
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: _s(task['title']).isEmpty ? 'Task' : _s(task['title']),
          status: _s(task['status']),
          meta: id.isEmpty ? '' : 'task ${_short(id)}',
        ),
        if (_s(task['description']).isNotEmpty)
          _Section('Briefing', _Markdown(_s(task['description']))),
        if (paths.isNotEmpty)
          _Section(
              'Owned paths',
              Text(paths.join('\n'),
                  style: mono(11, height: 1.5, color: AppColors.fg2))),
        if (resultText.isNotEmpty) _Section('Result', _Markdown(resultText)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section(this.label, this.child);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: mono(10, color: AppColors.fg3)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}

class _Markdown extends StatelessWidget {
  final String data;
  const _Markdown(this.data);

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return Text('(empty)', style: TS.meta());
    final text = sans(13, height: 1.45, color: AppColors.fg2);
    return MarkdownBody(
      data: data.trim(),
      selectable: true,
      styleSheet: markdownStyle(context).copyWith(
        p: text,
        listBullet: text,
        strong: text.copyWith(color: AppColors.fg1, fontWeight: W.strong),
        em: text.copyWith(fontStyle: FontStyle.italic),
        a: text.copyWith(color: AppColors.accent),
      ),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (_, href, __) => openMarkdownLink(href),
    );
  }
}

class _Messages extends StatelessWidget {
  final List<Map> messages;
  const _Messages(this.messages);

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return Text('No messages.', style: TS.meta());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < messages.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    [
                      _s(messages[i]['from']).isEmpty
                          ? 'unknown'
                          : _s(messages[i]['from']),
                      if (_s(messages[i]['at']).isNotEmpty)
                        _s(messages[i]['at']),
                    ].join(' · '),
                    style: mono(10, color: AppColors.fg3)),
                const SizedBox(height: 4),
                _Markdown(_s(messages[i]['body'])),
              ],
            ),
          ),
      ],
    );
  }
}
