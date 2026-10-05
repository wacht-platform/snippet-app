import 'tool_views.dart';

class ToolStep {
  const ToolStep({required this.tool, this.args, this.result});

  final String tool;
  final dynamic args;
  final dynamic result;

  bool get running => result == null;

  bool get failed =>
      result is Map && (result['status'] ?? '').toString() == 'error';

  List<Map> get changes {
    final raw = args is Map ? (args as Map)['changes'] : null;
    return raw is List ? raw.whereType<Map>().toList() : const [];
  }
}

enum ToolKind { change, run, web, other }

ToolKind toolKind(String tool) => switch (tool) {
      'change_files' => ToolKind.change,
      'bash' || 'manage_process' => ToolKind.run,
      'web_search' || 'web_read' => ToolKind.web,
      _ => ToolKind.other,
    };

String toolVerb(String tool, {required bool running}) {
  final (done, doing) = switch (tool) {
    'change_files' => ('Changed', 'Changing'),
    'view_image' => ('Viewed', 'Viewing'),
    'bash' => ('Ran', 'Running'),
    'manage_process' => ('Managed', 'Managing'),
    'search_skills' => ('Looked up skills', 'Looking up skills'),
    'skill' => ('Used skill', 'Using skill'),
    'web_search' => ('Searched the web for', 'Searching the web for'),
    'web_read' => ('Read', 'Reading'),
    'read_file' => ('Read', 'Reading'),
    'monitor' => ('Watched', 'Watching'),
    'present_file' => ('Shared', 'Sharing'),
    'set_session_title' => ('Titled the chat', 'Titling the chat'),
    'ping_user' => ('Pinged you', 'Pinging you'),
    'update_brief' => ('Updated its brief', 'Updating its brief'),
    'schedule_followup' => ('Scheduled a check', 'Scheduling a check'),
    _ => (
        'Used ${toolTitle(tool).toLowerCase()}',
        'Using ${toolTitle(tool).toLowerCase()}'
      ),
  };
  return running ? doing : done;
}

String _fileName(String path) => path.split('/').last;

/// A change_files step as (verb, object): what it did to which file, or how
/// many files a mixed batch touched.
(String, String) _changeParts(ToolStep step, bool running) {
  final changes = step.changes;
  if (changes.isEmpty) return (toolVerb(step.tool, running: running), '');
  final paths = {for (final c in changes) c['path']?.toString() ?? ''};
  final actions = {for (final c in changes) c['action']?.toString() ?? ''};
  if (paths.length > 1 || actions.length > 1) {
    final n = paths.length;
    return (
      running ? 'Changing' : 'Changed',
      '$n ${n == 1 ? 'file' : 'files'}'
    );
  }
  final first = changes.first;
  final name = _fileName(first['path']?.toString() ?? '');
  final (done, doing) = switch (actions.first) {
    'create' => ('Created', 'Creating'),
    'delete' => ('Deleted', 'Deleting'),
    'move' => ('Moved', 'Moving'),
    _ => ('Edited', 'Editing'),
  };
  final target =
      actions.first == 'move' ? '$name → ${first['to'] ?? ''}' : name;
  return (running ? doing : done, target);
}

String toolObject(ToolStep step) {
  final summary = toolArgSummary(step.tool, step.args);
  if (summary.isEmpty) return '';
  if (step.tool == 'view_image') return _fileName(summary);
  return summary;
}

(String, String) toolSentenceParts(ToolStep step, {bool? running}) {
  final isRunning = running ?? step.running;
  if (step.tool == 'change_files') return _changeParts(step, isRunning);
  // A labelled command already reads as a sentence ("Run the network tests"),
  // so it stands alone; "Ran" is only for a bare command line.
  final label = step.tool == 'bash' && step.args is Map
      ? ((step.args as Map)['label']?.toString().trim() ?? '')
      : '';
  if (label.isNotEmpty) return (label, '');
  return (toolVerb(step.tool, running: isRunning), toolObject(step));
}

String toolSentence(ToolStep step, {bool? running}) {
  final (verb, object) = toolSentenceParts(step, running: running);
  return object.isEmpty ? verb : '$verb $object';
}

enum FileChangeKind { created, edited, deleted, moved }

class FileChange {
  FileChange(this.path, this.kind);

  final String path;
  FileChangeKind kind;
  int added = 0;
  int removed = 0;

  String get name => kind == FileChangeKind.moved ? path : _fileName(path);
}

int _lineCount(dynamic text) {
  final s = text?.toString() ?? '';
  return s.isEmpty ? 0 : '\n'.allMatches(s.trimRight()).length + 1;
}

/// Every file the successful change_files steps touched, with net line counts.
List<FileChange> fileChanges(Iterable<ToolStep> steps) {
  final byPath = <String, FileChange>{};
  for (final step in steps) {
    if (step.tool != 'change_files' || step.failed) continue;
    for (final c in step.changes) {
      final action = c['action']?.toString() ?? '';
      final path = action == 'move'
          ? '${c['path']} → ${c['to']}'
          : c['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      final kind = switch (action) {
        'create' => FileChangeKind.created,
        'delete' => FileChangeKind.deleted,
        'move' => FileChangeKind.moved,
        _ => FileChangeKind.edited,
      };
      final change = byPath.putIfAbsent(path, () => FileChange(path, kind));
      if (kind == FileChangeKind.deleted) change.kind = kind;
      switch (action) {
        case 'replace':
          change.added += _lineCount(c['with']);
          change.removed += _lineCount(c['find']);
        case 'create':
          change.added += _lineCount(c['content']);
      }
    }
  }
  return byPath.values.toList();
}

String activitySummary(List<ToolStep> steps) {
  if (steps.length == 1) return toolSentence(steps.first);
  String plural(int n, String one, String many) => n == 1 ? one : many;
  int count(ToolKind kind) =>
      steps.where((s) => toolKind(s.tool) == kind).length;
  final changeSteps = count(ToolKind.change);
  final changed = fileChanges(steps).length;
  final runs = count(ToolKind.run);
  final searches = count(ToolKind.web);
  final groups = <(int, String)>[
    if (changeSteps > 0)
      (changeSteps, 'changed $changed ${plural(changed, 'file', 'files')}'),
    if (runs > 0) (runs, 'ran $runs ${plural(runs, 'command', 'commands')}'),
    if (searches > 0)
      (searches, '$searches web ${plural(searches, 'search', 'searches')}'),
  ];
  if (groups.isEmpty) return '${steps.length} steps';
  final rest = steps.length - groups.fold<int>(0, (sum, g) => sum + g.$1);
  final sentence = [
    for (final g in groups) g.$2,
    if (rest > 0) '$rest more',
  ].join(', ');
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
}
