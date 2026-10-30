import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'crew_status.dart';
import 'models.dart';
import 'notifications.dart' show onNotifTap;
import 'platform.dart';
import 'screens/tasks/task_common.dart' show openTaskInTab;
import 'session_quick_send.dart';

/// Feeds the resident notch pill and its hover overview. The native side
/// only draws; everything shown here is derived from daemon state.
class NotchHome {
  NotchHome._();

  static const _channel = MethodChannel('snippet/macos_notch');
  static DaemonClient? _client;
  static Timer? _timer;
  static String _last = '';
  static final Map<String, NotchTarget> _targets = {};
  static final List<NotchNote> _recent = [];
  static bool _loaded = false;
  static const _prefsKey = 'notch_recent_notifications';

  static Future<void> _loadRecent() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _recent
        ..clear()
        ..addAll(list
            .whereType<Map>()
            .map((m) => NotchNote.fromJson(Map<String, dynamic>.from(m))));
    } catch (_) {}
  }

  /// Keeps the last few notifications so the overview can show what was missed.
  static Future<void> remember({
    required String title,
    required String subtitle,
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    if (!kMacOS) return;
    await _loadRecent();
    _recent.removeWhere((n) => n.title == title && n.subtitle == subtitle);
    _recent.insert(
        0,
        NotchNote(
            title: title,
            subtitle: subtitle,
            kind: kind,
            payload: payload,
            at: DateTime.now().millisecondsSinceEpoch ~/ 1000));
    if (_recent.length > 5) _recent.removeRange(5, _recent.length);
    try {
      (await SharedPreferences.getInstance()).setString(
          _prefsKey, jsonEncode(_recent.map((n) => n.toJson()).toList()));
    } catch (_) {}
    _push();
  }

  static void bind(DaemonClient? client) {
    if (!kMacOS) return;
    if (_client?.baseUrl == client?.baseUrl &&
        _client?.token == client?.token) {
      return;
    }
    _timer?.cancel();
    _client = client;
    _last = '';
    if (client == null) return;
    _push();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _push());
  }

  static Future<void> _push() async {
    final client = _client;
    if (client == null) return;
    try {
      await _loadRecent();
      final results = await Future.wait([
        client.sessions(),
        client.coordinationAgents(),
        client.recurringJobs().catchError((_) => <RecurringJob>[]),
        client
            .tasks(status: 'in_progress', limit: 20)
            .catchError((_) => <TaskItem>[]),
        client
            .tasks(status: 'blocked', limit: 20)
            .catchError((_) => <TaskItem>[]),
      ]);
      final json = buildModel(
        sessions: results[0] as List<SessionInfo>,
        agents: results[1] as List<CoordinationAgent>,
        jobs: results[2] as List<RecurringJob>,
        tasks: [
          ...(results[3] as List<TaskItem>),
          ...(results[4] as List<TaskItem>)
        ],
        now: DateTime.now(),
        targets: _targets,
        recent: _recent,
      );
      final encoded = jsonEncode(json);
      if (encoded == _last) return;
      _last = encoded;
      await _channel.invokeMethod('homeUpdate', encoded);
    } catch (_) {}
  }

  static Future<void> handleAction(Map args) async {
    final client = _client;
    final target = _targets['${args['id']}'];
    if (client == null || target == null) return;
    switch ('${args['action']}') {
      case 'approve':
        await quickSend(
            client: client,
            session: target.session,
            action: const QuickApprove());
        _push();
      case 'deny':
        await quickSend(
            client: client, session: target.session, action: const QuickDeny());
        _push();
      case final a when a.startsWith('choice:'):
        final value = a.substring(7);
        final q = target.question;
        await quickSend(
            client: client,
            session: target.session,
            action: QuickAnswer(q.isEmpty || target.more > 0 ? value : '$q\n→ $value'));
        _push();
      case 'open':
        if (target.payload != null) {
          onNotifTap?.call(target.payload!);
        } else if (target.taskId != null) {
          openTaskInTab?.call(client, target.taskId!);
        } else {
          onNotifTap?.call({
            'kind': 'waiting',
            'url': client.baseUrl,
            'session': target.session,
          });
        }
    }
  }
}

class NotchTarget {
  const NotchTarget({
    this.session = '',
    this.taskId,
    this.payload,
    this.question = '',
    this.more = 0,
  });
  final String session;
  final String question;
  final int more;
  final String? taskId;
  final Map<String, dynamic>? payload;
}

class NotchNote {
  const NotchNote({
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.payload,
    required this.at,
  });
  final String title;
  final String subtitle;
  final String kind;
  final Map<String, dynamic> payload;
  final int at;

  factory NotchNote.fromJson(Map<String, dynamic> j) => NotchNote(
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        payload: Map<String, dynamic>.from(j['payload'] as Map? ?? const {}),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'kind': kind,
        'payload': payload,
        'at': at,
      };
}

List<Map<String, dynamic>> _askActions(Map? attn) {
  final type = attn?['type'];
  if (type == 'approval') {
    return [
      {'label': 'Approve', 'action': 'approve', 'primary': true},
      {'label': 'Deny', 'action': 'deny', 'primary': false},
    ];
  }
  if (type == 'question' && (attn?['more'] is! int || attn?['more'] == 0)) {
    final choices = attn?['choices'];
    if (choices is List && choices.isNotEmpty) {
      return [
        for (final (i, c) in choices.whereType<Map>().take(3).indexed)
          {
            'label': '${c['label'] ?? c['value'] ?? ''}',
            'action': 'choice:${c['value'] ?? c['label'] ?? ''}',
            'primary': i == 0,
          },
      ];
    }
  }
  return [
    {'label': 'Answer', 'action': 'open', 'primary': true},
  ];
}

NotchTarget _askTarget(String session, Map? attn) => NotchTarget(
      session: session,
      question: '${attn?['text'] ?? ''}'.trim(),
      more: attn?['more'] is int ? attn!['more'] as int : 0,
    );

String _ago(int unix, DateTime now) {
  final d = now.difference(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

String _when(int unix, DateTime now) {
  if (unix <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000).difference(now);
  if (d.isNegative) return 'overdue';
  if (d.inMinutes < 1) return 'in <1m';
  if (d.inHours < 1) return 'in ${d.inMinutes}m';
  if (d.inDays < 1) return 'in ${d.inHours}h';
  return 'in ${d.inDays}d';
}

String _short(int unix, DateTime now) {
  final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000).difference(now);
  if (d.isNegative) return '';
  if (d.inMinutes < 1) return '<1m';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Pure so it can be tested: the same session-derived crew rule as the sidebar.
Map<String, dynamic> buildModel({
  required List<SessionInfo> sessions,
  required List<CoordinationAgent> agents,
  required List<RecurringJob> jobs,
  required List<TaskItem> tasks,
  required DateTime now,
  required Map<String, NotchTarget> targets,
  List<NotchNote> recent = const [],
}) {
  targets.clear();
  final crew = deriveCrew(
      agents
          .where((a) => !a.isMissionControl && a.status != 'archived')
          .toList(),
      sessions);
  final asked = {
    for (final e in crew.where((e) => e.state == CrewState.needsYou))
      if (e.lead != null) e.lead!.id
  };
  final loose = sessions.where((s) => s.needsInput && !asked.contains(s.id)).toList();
  final needs = crewCount(crew, CrewState.needsYou) + loose.length;
  final working = crewCount(crew, CrewState.working);
  final failedJobs = jobs.where((j) => (j.lastError ?? '').isNotEmpty).length;
  final state = needs > 0
      ? 'needs'
      : failedJobs > 0
          ? 'failed'
          : working > 0
              ? 'working'
              : 'idle';
  final items = <Map<String, dynamic>>[];

  for (final e in crew.where((e) => e.state != CrewState.standingBy)) {
    final id = 'crew:${e.agent.id}';
    final session = e.lead?.id ?? '';
    targets[id] = _askTarget(session, e.attention);
    final asking = e.state == CrewState.needsYou;
    items.add({
      'id': id,
      'section': asking ? 'Needs you' : 'Working',
      'title': e.agent.displayName,
      'line': e.line,
      'tone': asking ? 'run' : 'accent',
      'tag': e.agent.role.trim(),
      'meta': e.sessions.length > 1 ? '${e.sessions.length} sessions' : '',
      'actions': asking
          ? _askActions(e.attention)
          : [
              {'label': 'Open', 'action': 'open', 'primary': false},
            ],
      'details': [
        if (e.agent.role.trim().isNotEmpty) 'Role\t${e.agent.role.trim()}',
        'Sessions\t${e.sessions.length}',
        if (e.agent.profile != null) 'Model\t${e.agent.profile}',
      ],
    });
  }

  for (final s in loose) {
    final id = 'ask:${s.id}';
    targets[id] = _askTarget(s.id, s.attention);
    final text = '${s.attention?['text'] ?? ''}'.trim();
    items.add({
      'id': id,
      'section': 'Needs you',
      'title': s.title.trim().isEmpty ? 'Untitled session' : s.title.trim(),
      'line': text.isEmpty ? 'Waiting for you' : text,
      'tone': 'run',
      'tag': '',
      'meta': '',
      'actions': _askActions(s.attention),
      'details': [],
    });
  }

  final sortedJobs = [...jobs.where((j) => j.enabled)]..sort((a, b) {
      final fa = (a.lastError ?? '').isNotEmpty ? 0 : 1;
      final fb = (b.lastError ?? '').isNotEmpty ? 0 : 1;
      return fa != fb ? fa.compareTo(fb) : a.nextRunAt.compareTo(b.nextRunAt);
    });
  for (final j in sortedJobs.take(4)) {
    final id = 'job:${j.id}';
    targets[id] = NotchTarget(session: j.sessionId);
    final failed = (j.lastError ?? '').isNotEmpty;
    items.add({
      'id': id,
      'section': 'Recurring',
      'title': j.title,
      'line': j.scheduleLabel,
      'tone': failed ? 'danger' : 'idle',
      'tag': '',
      'status': failed ? 'Failed' : '',
      'meta': failed ? '' : _when(j.nextRunAt, now),
      'actions': [
        {'label': 'Open', 'action': 'open', 'primary': false},
      ],
      'details': [
        'Schedule\t${j.scheduleLabel}',
        'Next run\t${_when(j.nextRunAt, now)}',
        if (failed) 'Last error\t${j.lastError!}',
      ],
    });
  }

  for (final t in tasks.take(4)) {
    final id = 'task:${t.id}';
    targets[id] = NotchTarget(taskId: t.id);
    final blocked = t.status == TaskStatus.blocked;
    items.add({
      'id': id,
      'section': 'Tasks',
      'title': t.title.trim().isEmpty ? 'Task' : t.title.trim(),
      'line': t.status.label,
      'tag': '',
      'meta': '',
      'tone': blocked ? 'run' : 'accent',
      'actions': [
        {'label': 'Open', 'action': 'open', 'primary': false},
      ],
      'details': ['Status\t${t.status.label}'],
    });
  }

  for (var i = 0; i < recent.length; i++) {
    final n = recent[i];
    final id = 'note:$i';
    final noteAttn = n.payload['attention'];
    final live = noteAttn is Map
        ? sessions
            .where((s) =>
                s.id == '${n.payload['session']}' &&
                s.needsInput &&
                s.attention?['id'] == noteAttn['id'])
            .firstOrNull
        : null;
    targets[id] = live == null
        ? NotchTarget(payload: n.payload)
        : NotchTarget(
            session: live.id,
            payload: n.payload,
            question: '${noteAttn?['text'] ?? ''}'.trim(),
            more: noteAttn?['more'] is int ? noteAttn!['more'] as int : 0);
    items.add({
      'id': id,
      'section': 'Recent',
      'title': n.title.trim().isEmpty ? 'Notification' : n.title.trim(),
      'line': n.subtitle.trim(),
      'tag': '',
      'meta': _ago(n.at, now),
      'tone': live == null ? 'idle' : 'run',
      'actions': live == null
          ? [
              {'label': 'Open', 'action': 'open', 'primary': false},
            ]
          : _askActions(noteAttn as Map),
      'details': [],
    });
  }

  final summary = [
    if (needs > 0) '$needs need${needs == 1 ? 's' : ''} you',
    if (failedJobs > 0) '$failedJobs job${failedJobs == 1 ? '' : 's'} failed',
    '$working active task${working == 1 ? '' : 's'}',
    '${crewCount(crew, CrewState.standingBy)} standing by',
  ].join(' · ');
  final upNext = sortedJobs
      .where((j) => (j.lastError ?? '').isEmpty && j.nextRunAt > 0)
      .firstOrNull;
  final featured = items.where((i) => i['section'] == 'Needs you').firstOrNull;
  return {
    'featuredId': featured?['id'] ?? '',
    'pill': upNext == null ? '' : _short(upNext.nextRunAt, now),
    'state': state,
    'title': 'Team status',
    'subtitle': summary,
    'badge': needs + failedJobs,
    'items': items,
  };
}
