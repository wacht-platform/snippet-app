import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

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
      case 'open':
        if (target.taskId != null) {
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
  const NotchTarget({this.session = '', this.taskId});
  final String session;
  final String? taskId;
}

String _when(int unix, DateTime now) {
  if (unix <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000).difference(now);
  if (d.isNegative) return 'due';
  if (d.inMinutes < 1) return 'in <1m';
  if (d.inHours < 1) return 'in ${d.inMinutes}m';
  if (d.inDays < 1) return 'in ${d.inHours}h';
  return 'in ${d.inDays}d';
}

/// Pure so it can be tested: the same session-derived crew rule as the sidebar.
Map<String, dynamic> buildModel({
  required List<SessionInfo> sessions,
  required List<CoordinationAgent> agents,
  required List<RecurringJob> jobs,
  required List<TaskItem> tasks,
  required DateTime now,
  required Map<String, NotchTarget> targets,
}) {
  targets.clear();
  final crew = deriveCrew(
      agents
          .where((a) => !a.isMissionControl && a.status != 'archived')
          .toList(),
      sessions);
  final needs = crewCount(crew, CrewState.needsYou);
  final working = crewCount(crew, CrewState.working);
  final failedJobs = jobs.where((j) => (j.lastError ?? '').isNotEmpty).length;
  final state = needs > 0 || failedJobs > 0
      ? 'needs'
      : working > 0
          ? 'working'
          : 'idle';
  final items = <Map<String, dynamic>>[];

  for (final e in crew.where((e) => e.state != CrewState.standingBy)) {
    final id = 'crew:${e.agent.id}';
    final session = e.lead?.id ?? '';
    targets[id] = NotchTarget(session: session);
    final asking = e.state == CrewState.needsYou;
    items.add({
      'id': id,
      'section': asking ? 'Needs you' : 'Working',
      'title': e.agent.displayName,
      'line': e.line,
      'tone': asking ? 'run' : 'accent',
      'actions': [
        if (asking && e.isApproval) ...[
          {'label': 'Approve', 'action': 'approve', 'primary': true},
          {'label': 'Deny', 'action': 'deny', 'primary': false},
        ] else if (asking)
          {'label': 'Answer', 'action': 'open', 'primary': true}
        else
          {'label': 'Open', 'action': 'open', 'primary': false},
      ],
      'details': [
        if (e.agent.role.trim().isNotEmpty) e.agent.role.trim(),
        '${e.sessions.length} session${e.sessions.length == 1 ? '' : 's'}',
        if (e.agent.profile != null) 'Model: ${e.agent.profile}',
      ],
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
      'line': failed
          ? 'Last run failed'
          : '${j.scheduleLabel} · next ${_when(j.nextRunAt, now)}',
      'tone': failed ? 'danger' : 'idle',
      'actions': [
        {'label': 'Open', 'action': 'open', 'primary': false},
      ],
      'details': [
        j.scheduleLabel,
        'Next run ${_when(j.nextRunAt, now)}',
        if (failed) j.lastError!,
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
      'tone': blocked ? 'run' : 'accent',
      'actions': [
        {'label': 'Open', 'action': 'open', 'primary': false},
      ],
      'details': [t.status.label],
    });
  }

  final title = needs > 0
      ? '$needs need${needs == 1 ? 's' : ''} you'
      : failedJobs > 0
          ? '$failedJobs job${failedJobs == 1 ? '' : 's'} failed'
          : working > 0
              ? '$working working'
              : 'All good';
  return {
    'state': state,
    'title': title,
    'subtitle':
        '$working working · ${crewCount(crew, CrewState.standingBy)} standing by',
    'badge': needs + failedJobs,
    'items': items,
  };
}
