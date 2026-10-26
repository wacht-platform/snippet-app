import 'dart:convert';

import 'coordination_tool_views.dart';
import 'tool_views.dart';

List<Map<String, dynamic>> normalizeChanges(dynamic args) {
  if (args is! Map) return const [];
  dynamic raw = args['changes'];
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      raw = null;
    }
  }
  if (raw == null && args['path'] != null) raw = [args];
  if (raw is! List) return const [];
  final shared = args['path'];
  dynamic pick(Map m, List<String> keys) {
    for (final k in keys) {
      if (m[k] != null) return m[k];
    }
    return null;
  }

  const actions = {'create', 'replace', 'delete', 'move'};
  return [
    for (final c in raw.whereType<Map>())
      () {
        final find = pick(c, const ['find', 'old_string', 'old', 'search']);
        final to = pick(c, const ['to', 'new_path', 'destination']);
        final content = pick(c, const ['content', 'text']);
        final declared = (c['action'] ?? c['type'])?.toString();
        final action = actions.contains(declared)
            ? declared!
            : find != null
                ? 'replace'
                : to != null
                    ? 'move'
                    : content != null
                        ? 'create'
                        : declared ?? '';
        return <String, dynamic>{
          'path': (c['path'] ?? shared ?? '').toString(),
          'action': action,
          if (find != null) 'find': find.toString(),
          'with': (pick(c, const ['with', 'new_string', 'new', 'replace', 'replacement']) ?? '').toString(),
          if (c['all'] != null) 'all': c['all'],
          if (content != null) 'content': content.toString(),
          if (c['overwrite'] != null) 'overwrite': c['overwrite'],
          if (to != null) 'to': to.toString(),
        };
      }(),
  ];
}

class ToolStep {
  const ToolStep({required this.tool, this.args, this.result});

  final String tool;
  final dynamic args;
  final dynamic result;

  bool get running => result == null;

  Map? get data {
    final r = result;
    if (r is! Map) return null;
    return r['data'] is Map ? r['data'] as Map : r;
  }

  int? get exitCode {
    final v = data?['exit_code'];
    return v is num ? v.toInt() : null;
  }

  bool get failed {
    final r = result;
    if (r is Map && (r['status'] ?? '').toString() == 'error') return true;
    final code = exitCode;
    return toolBaseName(tool) == 'bash' && code != null && code != 0;
  }

  List<Map> get changes => normalizeChanges(args);
}

String toolBaseName(String tool) =>
    tool.startsWith('mcp__') ? tool.substring(tool.lastIndexOf('__') + 2) : tool;

enum ToolKind { change, run, web, other }

ToolKind toolKind(String tool) => switch (toolBaseName(tool)) {
      'change_files' => ToolKind.change,
      'bash' || 'manage_process' => ToolKind.run,
      'web_search' || 'web_read' => ToolKind.web,
      _ => ToolKind.other,
    };

String toolVerb(String tool, {required bool running}) {
  tool = toolBaseName(tool);
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
    'view_file' => ('Read', 'Reading'),
    'monitor' => ('Watched', 'Watching'),
    'present_file' => ('Shared', 'Sharing'),
    'set_session_title' => ('Titled the chat', 'Titling the chat'),
    'ping_user' => ('Pinged you', 'Pinging you'),
    'update_brief' => ('Updated its brief', 'Updating its brief'),
    'schedule_wake' || 'schedule_followup' => ('Scheduled a wake-up', 'Scheduling a wake-up'),
    'search_content' => ('Searched', 'Searching'),
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
  final failed = !running && step.failed;
  if (paths.length > 1 || actions.length > 1) {
    final n = paths.length;
    return (
      running ? 'Changing' : (failed ? "Couldn't change" : 'Changed'),
      '$n ${n == 1 ? 'file' : 'files'}'
    );
  }
  final first = changes.first;
  final name = _fileName(first['path']?.toString() ?? '');
  final (done, doing, tried) = switch (actions.first) {
    'create' => ('Created', 'Creating', "Couldn't create"),
    'delete' => ('Deleted', 'Deleting', "Couldn't delete"),
    'move' => ('Moved', 'Moving', "Couldn't move"),
    _ => ('Edited', 'Editing', "Couldn't edit"),
  };
  final target =
      actions.first == 'move' ? '$name → ${first['to'] ?? ''}' : name;
  return (running ? doing : (failed ? tried : done), target);
}

String toolObject(ToolStep step) {
  final summary = toolArgSummary(step.tool, step.args);
  if (summary.isEmpty) return '';
  if (toolBaseName(step.tool) == 'view_image') return _fileName(summary);
  return summary;
}

(String, String) toolSentenceParts(ToolStep step, {bool? running}) {
  final isRunning = running ?? step.running;
  final name = toolBaseName(step.tool);
  if (name == 'change_files') return _changeParts(step, isRunning);
  // A labelled command already reads as a sentence ("Run the network tests"),
  // so it stands alone; "Ran" is only for a bare command line.
  final coordination = coordinationSentence(name,
      step.args is Map ? step.args as Map : null, step.data,
      running: isRunning);
  if (coordination != null) return coordination;
  final label = name == 'bash' && step.args is Map
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
    if (toolBaseName(step.tool) != 'change_files' || step.failed) continue;
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
          final (added, removed) =
              diffCounts(c['find']?.toString() ?? '', c['with']?.toString() ?? '');
          change.added += added;
          change.removed += removed;
        case 'create':
          change.added += _lineCount(c['content']);
      }
    }
  }
  return byPath.values.toList();
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

String _joinPhrases(List<String> parts) {
  if (parts.length < 2) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

String activitySummary(List<ToolStep> steps) {
  if (steps.length == 1) return toolSentence(steps.first);
  final edited = fileChanges(steps).length;
  var ran = 0, read = 0, searched = 0, pages = 0, other = 0;
  for (final s in steps) {
    switch (toolBaseName(s.tool)) {
      case 'change_files':
        break;
      case 'bash':
      case 'manage_process':
        ran++;
      case 'read_file':
      case 'view_file':
      case 'view_image':
        read++;
      case 'search_content':
      case 'web_search':
        searched++;
      case 'web_read':
        pages++;
      default:
        other++;
    }
  }
  final changeSteps = steps.where((s) => toolBaseName(s.tool) == 'change_files').length;
  final parts = [
    if (ran > 0) 'ran $ran ${_plural(ran, 'command', 'commands')}',
    if (changeSteps > 0)
      edited > 0
          ? 'edited $edited ${_plural(edited, 'file', 'files')}'
          : 'made $changeSteps ${_plural(changeSteps, 'change', 'changes')}',
    if (read > 0) 'read $read ${_plural(read, 'file', 'files')}',
    if (searched > 0)
      'searched $searched ${_plural(searched, 'time', 'times')}',
    if (pages > 0) 'read $pages ${_plural(pages, 'page', 'pages')}',
    if (other > 0)
      _otherPhrase(other, hasOthers: ran + changeSteps + read + searched + pages > 0),
  ];
  final sentence = _joinPhrases(parts);
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
}

String _otherPhrase(int n, {required bool hasOthers}) =>
    '$n ${hasOthers ? 'other ' : ''}${_plural(n, 'step', 'steps')}';
