import 'tool_views.dart';

class ToolStep {
  const ToolStep({required this.tool, this.args, this.result});

  final String tool;
  final dynamic args;
  final dynamic result;

  bool get running => result == null;

  bool get failed =>
      result is Map && (result['status'] ?? '').toString() == 'error';
}

enum ToolKind { read, edit, run, search, web, memory, other }

ToolKind toolKind(String tool) => switch (tool) {
      'read_file' || 'read_image' || 'list_files' || 'view_outline' ||
      'code_map' =>
        ToolKind.read,
      'edit_file' || 'replace_file_content' || 'write_file' || 'append_file' =>
        ToolKind.edit,
      'bash' || 'manage_process' => ToolKind.run,
      'search_content' || 'search_files' || 'search_skills' => ToolKind.search,
      'web_search' || 'web_read' => ToolKind.web,
      'memory_read' ||
      'memory_write' ||
      'memory_index' ||
      'memory_delete' ||
      'memory_pattern' ||
      'memory_rule' =>
        ToolKind.memory,
      _ => ToolKind.other,
    };

String toolVerb(String tool, {required bool running}) {
  final (done, doing) = switch (tool) {
    'read_file' => ('Read', 'Reading'),
    'read_image' => ('Viewed', 'Viewing'),
    'list_files' => ('Listed', 'Listing'),
    'view_outline' || 'code_map' => ('Mapped', 'Mapping'),
    'edit_file' || 'replace_file_content' => ('Edited', 'Editing'),
    'write_file' => ('Wrote', 'Writing'),
    'append_file' => ('Appended to', 'Appending to'),
    'bash' => ('Ran', 'Running'),
    'manage_process' => ('Managed', 'Managing'),
    'search_content' => ('Searched for', 'Searching for'),
    'search_files' => ('Found files', 'Finding files'),
    'search_skills' => ('Looked up skills', 'Looking up skills'),
    'skill' => ('Used skill', 'Using skill'),
    'web_search' => ('Searched the web for', 'Searching the web for'),
    'web_read' => ('Read', 'Reading'),
    'memory_read' => ('Recalled', 'Recalling'),
    'memory_write' => ('Remembered', 'Remembering'),
    'memory_delete' => ('Forgot', 'Forgetting'),
    'memory_index' || 'memory_pattern' || 'memory_rule' =>
      ('Updated memory', 'Updating memory'),
    'monitor' => ('Watched', 'Watching'),
    'present_file' => ('Shared', 'Sharing'),
    'set_session_title' => ('Titled the chat', 'Titling the chat'),
    _ => ('Used ${toolTitle(tool).toLowerCase()}',
        'Using ${toolTitle(tool).toLowerCase()}'),
  };
  return running ? doing : done;
}

bool _isPathTool(String tool) =>
    toolKind(tool) == ToolKind.read || toolKind(tool) == ToolKind.edit;

String toolObject(ToolStep step) {
  final summary = toolArgSummary(step.tool, step.args);
  if (summary.isEmpty) return '';
  if (_isPathTool(step.tool)) return summary.split('/').last;
  return summary;
}

String toolSentence(ToolStep step, {bool? running}) {
  final verb = toolVerb(step.tool, running: running ?? step.running);
  final object = toolObject(step);
  return object.isEmpty ? verb : '$verb $object';
}

class FileChange {
  FileChange(this.path, this.created);

  final String path;
  bool created;
  int added = 0;
  int removed = 0;

  String get name => path.split('/').last;
}

List<FileChange> fileChanges(Iterable<ToolStep> steps) {
  final byPath = <String, FileChange>{};
  for (final step in steps) {
    if (toolKind(step.tool) != ToolKind.edit || step.failed) continue;
    final a = step.args;
    if (a is! Map) continue;
    final path = (a['path'] ?? a['file_path'] ?? '').toString();
    if (path.isEmpty) continue;
    final change =
        byPath.putIfAbsent(path, () => FileChange(path, step.tool == 'write_file'));
    final added = (a['new_string'] ?? a['content'] ?? '').toString();
    final removed = a['old_string']?.toString();
    change.added += added.isEmpty ? 0 : added.split('\n').length;
    change.removed +=
        removed == null || removed.isEmpty ? 0 : removed.split('\n').length;
  }
  return byPath.values.toList();
}

String activitySummary(List<ToolStep> steps) {
  if (steps.length == 1) return toolSentence(steps.first);
  int count(ToolKind k) => steps.where((s) => toolKind(s.tool) == k).length;
  final reads = count(ToolKind.read);
  final edits = fileChanges(steps).length;
  final runs = count(ToolKind.run);
  final searches = count(ToolKind.search) + count(ToolKind.web);
  String plural(int n, String one, String many) => n == 1 ? one : many;
  final parts = <String>[
    if (reads > 0) 'read $reads ${plural(reads, 'file', 'files')}',
    if (edits > 0) 'edited $edits ${plural(edits, 'file', 'files')}',
    if (runs > 0) 'ran $runs ${plural(runs, 'command', 'commands')}',
    if (searches > 0) 'searched $searches ${plural(searches, 'time', 'times')}',
  ];
  final covered = reads +
      steps.where((s) => toolKind(s.tool) == ToolKind.edit).length +
      runs +
      searches;
  final other = steps.length - covered;
  if (parts.isEmpty) return '${steps.length} steps';
  if (other > 0) parts.add('$other more');
  final sentence = parts.join(', ');
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
}
