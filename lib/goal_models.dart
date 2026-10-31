class GoalProgress {
  const GoalProgress({this.done = 0, this.total = 0});
  final int done;
  final int total;

  factory GoalProgress.fromJson(dynamic j) => j is Map
      ? GoalProgress(
          done:
              (j['done'] as num?)?.toInt() ?? (j['have'] as num?)?.toInt() ?? 0,
          total: (j['total'] as num?)?.toInt() ?? 0)
      : const GoalProgress();

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();
}

enum GoalAttention {
  stalled('stalled', 'Stalled'),
  readyToClose('ready_to_close', 'Ready to close');

  const GoalAttention(this.wire, this.label);
  final String wire;
  final String label;

  static GoalAttention? parse(dynamic v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return null;
  }
}

String _text(dynamic v) => v is String ? v : '';
String? _opt(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

class Goal {
  const Goal({
    required this.id,
    this.title = '',
    this.outcome = '',
    this.status = 'open',
    this.requester = '',
    this.createdAt = '',
    this.closedAt,
    this.progress = const GoalProgress(),
    this.evidence = const GoalProgress(),
    this.attention,
  });

  final String id;
  final String title;
  final String outcome;
  final String status;
  final String requester;
  final String createdAt;
  final String? closedAt;
  final GoalProgress progress;
  final GoalProgress evidence;
  final GoalAttention? attention;

  Goal.fromJson(Map<String, dynamic> j)
      : id = _text(j['id']),
        title = _text(j['title']),
        outcome = _text(j['outcome']),
        status = _opt(j['status']) ?? 'open',
        requester = _text(j['requester']),
        createdAt = _text(j['created_at']),
        closedAt = _opt(j['closed_at']),
        progress = GoalProgress.fromJson(j['progress']),
        evidence = GoalProgress.fromJson(j['evidence']),
        attention = GoalAttention.parse(j['attention']);

  bool get isOpen => status == 'open';
}

class GoalCriterion {
  const GoalCriterion({this.criterion = '', this.method = '', this.evidence});
  final String criterion;
  final String method;
  final String? evidence;

  GoalCriterion.fromJson(Map<String, dynamic> j)
      : criterion = _text(j['criterion']),
        method = _text(j['method']),
        evidence = _opt(j['evidence']);

  bool get hasEvidence => evidence != null;
}

class GoalPlanStep {
  const GoalPlanStep(
      {required this.n,
      this.taskId,
      this.title = '',
      this.dependsOn = const []});
  final int n;
  final String? taskId;
  final String title;
  final List<int> dependsOn;

  GoalPlanStep.fromJson(Map<String, dynamic> j)
      : n = (j['n'] as num?)?.toInt() ?? 0,
        taskId = _opt(j['task_id']),
        title = _text(j['title']),
        dependsOn = [
          if (j['depends_on'] is List)
            for (final d in j['depends_on'] as List)
              if (d is num) d.toInt()
        ];
}

class GoalTask {
  const GoalTask({
    required this.id,
    this.slice,
    this.title = '',
    this.status = 'todo',
    this.sessionId,
    this.agent,
    this.statusReason,
    this.waitingOn = const [],
    this.dependsOn = const [],
    this.updatedAt = '',
    this.result,
  });

  final String id;
  final int? slice;
  final String title;
  final String status;
  final String? sessionId;
  final String? agent;
  final String? statusReason;
  final List<String> waitingOn;
  final List<String> dependsOn;
  final String updatedAt;
  final String? result;

  GoalTask.fromJson(Map<String, dynamic> j)
      : id = _text(j['id']),
        slice = (j['slice'] as num?)?.toInt(),
        title = _text(j['title']),
        status = _opt(j['status']) ?? 'todo',
        sessionId = _opt(j['session_id']),
        agent = _opt(j['agent']),
        statusReason = _opt(j['status_reason']),
        waitingOn = _strings(j['waiting_on']),
        dependsOn = _strings(j['depends_on']),
        updatedAt = _text(j['updated_at']),
        result = _opt(j['result']);
}

List<String> _strings(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e != null && '$e'.isNotEmpty) '$e'
      ]
    : const [];

class GoalBlocker {
  const GoalBlocker(
      {required this.taskId,
      this.title = '',
      this.status = '',
      this.reason,
      this.waitingOn = const []});
  final String taskId;
  final String title;
  final String status;
  final String? reason;
  final List<String> waitingOn;

  GoalBlocker.fromJson(Map<String, dynamic> j)
      : taskId = _text(j['task_id']),
        title = _text(j['title']),
        status = _text(j['status']),
        reason = _opt(j['reason']),
        waitingOn = _strings(j['waiting_on']);
}

class GoalDetail {
  const GoalDetail({
    required this.goal,
    this.acceptance = const [],
    this.plan = const [],
    this.tasks = const [],
    this.blockers = const [],
  });

  final Goal goal;
  final List<GoalCriterion> acceptance;
  final List<GoalPlanStep> plan;
  final List<GoalTask> tasks;
  final List<GoalBlocker> blockers;

  GoalDetail.fromJson(Map<String, dynamic> j)
      : goal = Goal.fromJson(j),
        acceptance =
            _maps(j['acceptance']).map(GoalCriterion.fromJson).toList(),
        plan = _maps(j['plan']).map(GoalPlanStep.fromJson).toList()
          ..sort((a, b) => a.n.compareTo(b.n)),
        tasks = _maps(j['tasks']).map(GoalTask.fromJson).toList(),
        blockers = _maps(j['blockers']).map(GoalBlocker.fromJson).toList();

  GoalTask? taskFor(GoalPlanStep s) {
    for (final t in tasks) {
      if ((s.taskId != null && t.id == s.taskId) ||
          (t.slice != null && t.slice == s.n)) {
        return t;
      }
    }
    return null;
  }

  /// Titles of the slices this one depends on, resolved from plan indexes.
  List<String> dependencyTitles(GoalPlanStep s) => [
        for (final n in s.dependsOn)
          plan.where((p) => p.n == n).map((p) => p.title).firstOrNull ??
              'Slice $n'
      ];
}
