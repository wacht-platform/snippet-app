/// Plain-English notes a task carries beside its status: why it is where it
/// is, what it is doing now, and what replaced it.
library;

class TaskNote {
  const TaskNote(this.reason, this.step, this.replacedBy);
  final String? reason;
  final String? step;
  final String? replacedBy;

  bool get isEmpty => reason == null && step == null && replacedBy == null;

  /// One line for dense rows: the most useful note first.
  String? get line => step ?? reason ?? replacedBy;
}

String _humanise(String raw) {
  final s = raw.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Builds the notes for a task. [titleOf] resolves a task id to its title and
/// returns null when the task is not in the loaded list.
TaskNote taskNote({
  required String status,
  String? statusReason,
  List<String> waitingOn = const [],
  String? currentStep,
  String? supersededBy,
  required String? Function(String id) titleOf,
}) {
  String name(String id) {
    final t = titleOf(id)?.trim();
    return t == null || t.isEmpty ? 'another task' : t;
  }

  String? reason;
  final raw = statusReason?.trim();
  if (raw != null && raw.isNotEmpty) {
    final dep = RegExp(r'^awaiting_dependency\((.*)\)$').firstMatch(raw);
    if (dep != null || raw == 'awaiting_dependency') {
      final ids = waitingOn.isNotEmpty
          ? waitingOn
          : [if (dep != null && dep.group(1)!.isNotEmpty) dep.group(1)!];
      reason = ids.isEmpty
          ? 'Waiting on another task'
          : 'Waiting on ${ids.map(name).join(', ')}';
    } else {
      reason = switch (raw) {
        'offered' => 'Offered, not yet accepted',
        'awaiting_paths' => 'Waiting for files to be free',
        'awaiting_agent' => 'Waiting for an agent',
        'stalled' => 'Stalled, no recent activity',
        _ => _humanise(raw),
      };
    }
  } else if (waitingOn.isNotEmpty && status != 'done') {
    reason = 'Waiting on ${waitingOn.map(name).join(', ')}';
  }

  final open = status != 'done' && status != 'cancelled' && status != 'failed';
  final step = open && status == 'in_progress' ? currentStep?.trim() : null;
  final next = supersededBy?.trim();
  return TaskNote(
    reason,
    step == null || step.isEmpty ? null : step,
    next == null || next.isEmpty ? null : 'Replaced by ${name(next)}',
  );
}
