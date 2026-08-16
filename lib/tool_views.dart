import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'highlight.dart';
import 'theme.dart';
import 'widgets.dart';

// The daemon can evolve independently of the client. Keep malformed or newer
// result items visible only as far as they can be safely rendered; one bad item
// must not make the entire tool panel fail to build.
List<Map> _mapItems(dynamic value) =>
    value is List ? value.whereType<Map>().toList() : const <Map>[];

/// Per-tool rendering: a glyph + one-line summary for the inline ToolLine, and a
// rich, tool-specific body for the detail drawer (never raw JSON unless unknown).

/// Lucide-ish glyph name for a tool (resolved via [iconFor]).
String toolIcon(String tool) => switch (tool) {
      'edit_file' || 'replace_file_content' => 'edit',
      'write_file' || 'append_file' => 'file-plus',
      'read_file' => 'file',
      'read_image' => 'image',
      'bash' => 'terminal',
      'search_content' || 'search_files' => 'search',
      'list_files' => 'folder-open',
      'code_map' || 'view_outline' => 'map',
      'web_search' || 'web_read' => 'globe',
      _ => 'zap',
    };

/// One-line, tool-aware summary for the inline activity line.
String toolArgSummary(String tool, dynamic args) {
  if (args is! Map) return '';
  String s(String k) => args[k]?.toString() ?? '';
  String first(String v) => v.split('\n').first.trim();
  final v = switch (tool) {
    'bash' => s('command'),
    'search_content' || 'web_search' => s('query'),
    'search_files' => s('pattern'),
    'web_read' => s('url'),
    'code_map' => args['path']?.toString() ?? args['query']?.toString() ?? '.',
    'read_file' ||
    'write_file' ||
    'append_file' ||
    'read_image' ||
    'edit_file' ||
    'replace_file_content' ||
    'view_outline' ||
    'list_files' =>
      s('path'),
    _ => '',
  };
  if (v.isNotEmpty) return first(v);
  for (final k in const [
    'command',
    'path',
    'query',
    'pattern',
    'url',
    'file'
  ]) {
    if (args[k] is String) return first(args[k] as String);
  }
  return '';
}

/// Friendly title for the drawer header.
String toolTitle(String tool) => switch (tool) {
      'edit_file' => 'Edit file',
      'replace_file_content' => 'Replace lines',
      'write_file' => 'Write file',
      'append_file' => 'Append file',
      'read_file' => 'Read file',
      'read_image' => 'Read image',
      'bash' => 'Shell command',
      'search_content' => 'Search content',
      'search_files' => 'Find files',
      'list_files' => 'List files',
      'code_map' => 'Code map',
      'view_outline' => 'File outline',
      'web_search' => 'Web search',
      'web_read' => 'Read page',
      _ => tool,
    };

/// Tool detail rendering is isolated behind a small error boundary. A malformed
/// result must produce a useful panel message instead of taking down the sheet.
Widget safeToolDetailView(BuildContext context,
    {required String tool, dynamic args, dynamic result}) {
  return Builder(builder: (panelContext) {
    try {
      return toolDetailView(panelContext,
          tool: tool, args: args, result: result);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'snippet tool panel',
        context: ErrorDescription('building $tool details'),
      ));
      return const _ToolPanelError();
    }
  });
}

class _ToolPanelError extends StatelessWidget {
  const _ToolPanelError();
  @override
  Widget build(BuildContext context) {
    return const _ErrorBox('This tool panel could not render its result.');
  }
}

/// The drawer body for a tool. [result] is the full ToolResult map
/// ({status, data, error}); null while the call is still pending.
Widget toolDetailView(BuildContext context,
    {required String tool, dynamic args, dynamic result}) {
  final Map? a = args is Map ? args : null;
  final Map? r = result is Map ? result : null;
  final status = r?['status']?.toString();
  final data = r?['data'];
  final Map? d = data is Map ? data : null;
  final err = r?['error'];
  final errMsg = err is Map ? err['message']?.toString() : null;

  final rows = <Widget>[];

  // Error banner first — applies to every tool.
  if (status == 'error' && errMsg != null) {
    rows.add(_ErrorBox(errMsg));
    rows.add(const SizedBox(height: 14));
  }

  // Spilled / oversized output (generic wrapper the harness may apply).
  if (d != null &&
      (d['data_omitted'] == true ||
          d['truncated'] == true && d['preview'] != null)) {
    final body = _toolBody(context, tool, a, d, status);
    rows.addAll(body);
    if (d['preview'] != null) {
      rows.add(const SizedBox(height: 14));
      rows.add(const SectionLabel('Preview'));
      rows.add(const SizedBox(height: 8));
      rows.add(_CodeBox(_displayText(d['preview'].toString())));
    }
    if (d['hint'] != null) {
      rows.add(const SizedBox(height: 10));
      rows.add(_Hint(d['hint'].toString()));
    }
    return _wrap(rows);
  }

  rows.addAll(_toolBody(context, tool, a, d, status));

  if (rows.isEmpty) {
    rows.add(Text('No details.', style: sans(12.5, color: AppColors.fg3)));
  }
  return _wrap(rows);
}

Widget _wrap(List<Widget> rows) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);

List<Widget> _toolBody(
    BuildContext context, String tool, Map? a, Map? d, String? status) {
  switch (tool) {
    case 'edit_file':
      return _editView(a, d, oldKey: 'old_string', newKey: 'new_string');
    case 'replace_file_content':
      return _editView(a, d,
          oldKey: 'target_content',
          newKey: 'replacement_content',
          range: a == null ? null : '${a['start_line']}–${a['end_line']}');
    case 'write_file':
      return _writeView(a, d, verb: 'Wrote');
    case 'append_file':
      return _appendView(a, d);
    case 'read_file':
      return _readView(a, d);
    case 'read_image':
      return _imageView(a, d);
    case 'bash':
      return _bashView(a, d);
    case 'search_content':
      return _grepView(a, d);
    case 'search_files':
      return _findView(a, d);
    case 'list_files':
      return _lsView(a, d);
    case 'view_outline':
      return _outlineView(a, d);
    case 'code_map':
      return _codeMapView(a, d);
    case 'web_search':
      return _webSearchView(a, d);
    case 'web_read':
      return _webReadView(a, d);
    default:
      return _jsonFallback(a, d, status);
  }
}

// ---- per-tool views ----

List<Widget> _editView(Map? a, Map? d,
    {required String oldKey, required String newKey, String? range}) {
  final out = <Widget>[];
  if (a != null) out.add(_PathChip(a['path']?.toString() ?? ''));
  if (range != null) {
    out.add(const SizedBox(height: 8));
    out.add(_meta([_chip('list', 'lines $range')]));
  }
  if (a != null && a[oldKey] != null && a[newKey] != null) {
    out.add(const SizedBox(height: 12));
    out.add(const SectionLabel('Diff'));
    out.add(const SizedBox(height: 8));
    out.add(_DiffBlock(a[oldKey].toString(), a[newKey].toString()));
  } else if (a == null) {
    out.add(_done(d?['edited'] == true || d?['replaced'] == true
        ? 'Applied'
        : 'Pending'));
  }
  if (d != null && d['note'] != null) {
    out.add(const SizedBox(height: 10));
    out.add(_Hint(d['note'].toString()));
  }
  return out;
}

List<Widget> _writeView(Map? a, Map? d, {required String verb}) {
  final out = <Widget>[];
  final path = a?['path']?.toString() ?? d?['path']?.toString() ?? '';
  out.add(_PathChip(path));
  final content = a?['content']?.toString();
  if (content != null) {
    out.add(const SizedBox(height: 8));
    out.add(
        _meta([_chip('list', '${'\n'.allMatches(content).length + 1} lines')]));
    out.add(const SizedBox(height: 12));
    out.add(const SectionLabel('Contents'));
    out.add(const SizedBox(height: 8));
    out.add(_HiCodeBlock(path, content));
  } else if (d?['written'] == true) {
    out.add(_done('$verb file'));
  }
  return out;
}

List<Widget> _appendView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_PathChip(a?['path']?.toString() ?? d?['path']?.toString() ?? ''));
  final chips = <Widget>[];
  if (d?['lines_written'] != null)
    chips.add(_chip('file-plus', '+${d?['lines_written']} lines'));
  if (d?['total_lines'] != null)
    chips.add(_chip('list', '${d?['total_lines']} total'));
  if (chips.isNotEmpty) {
    out.add(const SizedBox(height: 8));
    out.add(_meta(chips));
  }
  final content = a?['content']?.toString();
  if (content != null && content.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(const SectionLabel('Appended'));
    out.add(const SizedBox(height: 8));
    out.add(_CodeBox(content, addTint: true));
  }
  return out;
}

List<Widget> _readView(Map? a, Map? d) {
  final out = <Widget>[];
  final path = a?['path']?.toString() ?? d?['path']?.toString() ?? '';
  out.add(_PathChip(path));
  final chips = <Widget>[];
  final sl = d?['start_line'], el = d?['end_line'];
  if (sl != null || el != null) chips.add(_chip('list', 'lines $sl–$el'));
  if (d?['total_lines'] != null)
    chips.add(_chip('file', '${d?['total_lines']} lines'));
  if (d?['total_chars'] != null)
    chips.add(_chip('grip', '${d?['total_chars']} chars'));
  if (chips.isNotEmpty) {
    out.add(const SizedBox(height: 8));
    out.add(_meta(chips));
  }
  final content = d?['content']?.toString();
  if (content != null && content.trim().isNotEmpty) {
    final preview = content.split('\n').take(8).join('\n');
    out.add(const SizedBox(height: 6));
    out.add(_CodeBox(preview));
  }
  if (d?['truncated'] == true && d?['hint'] != null) {
    out.add(const SizedBox(height: 10));
    out.add(_Hint(d?['hint']?.toString() ?? ''));
  }
  return out;
}

List<Widget> _imageView(Map? a, Map? d) {
  return [
    _PathChip(a?['path']?.toString() ?? d?['path']?.toString() ?? ''),
    if (d?['mime'] != null || d?['size_bytes'] != null) ...[
      const SizedBox(height: 4),
      _meta([
        if (d?['mime'] != null) _chip('image', d!['mime'].toString()),
        if (d?['size_bytes'] != null)
          _chip('grip', formatBytes(d!['size_bytes'])),
      ]),
    ],
  ];
}

List<Widget> _bashView(Map? a, Map? d) {
  final out = <Widget>[];
  final cmd = a?['command']?.toString() ?? d?['command']?.toString() ?? '';
  out.add(const SectionLabel('Command'));
  out.add(const SizedBox(height: 8));
  out.add(_CommandBox(cmd));
  if (d != null) {
    final code = d['exit_code'];
    final ok = d['success'] == true || code == 0;
    out.add(const SizedBox(height: 12));
    out.add(_meta([
      _statusChip(ok, ok ? 'exit 0' : 'exit ${code ?? '?'}'),
    ]));
    final stdout = d['stdout']?.toString() ?? '';
    final stderr = d['stderr']?.toString() ?? '';
    if (stdout.trim().isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(const SectionLabel('stdout'));
      out.add(const SizedBox(height: 8));
      out.add(_CodeBox(stdout));
    }
    if (stderr.trim().isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(const SectionLabel('stderr'));
      out.add(const SizedBox(height: 8));
      out.add(_CodeBox(stderr, delTint: true));
    }
    if (stdout.trim().isEmpty && stderr.trim().isEmpty) {
      out.add(const SizedBox(height: 10));
      out.add(Text('(no output)', style: mono(11.5, color: AppColors.fg4)));
    }
  }
  return out;
}

List<Widget> _grepView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_meta([
    _chip('search', '"${a?['query'] ?? d?['query'] ?? ''}"'),
    if (d?['count'] != null) _chip('list', '${d?['count']} matches'),
  ]));
  final results = _mapItems(d?['results']);
  if (results.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(_Card(
      children: [
        for (final m in results)
          _MatchRow(
            path: m['path']?.toString() ?? '',
            line: m['line_number']?.toString(),
            text: m['content']?.toString() ?? '',
          ),
      ],
    ));
  } else if (d != null) {
    out.add(const SizedBox(height: 10));
    out.add(_empty('No matches'));
  }
  if (d?['truncated'] == true && d?['hint'] != null) {
    out.add(const SizedBox(height: 10));
    out.add(_Hint(d?['hint']?.toString() ?? ''));
  }
  return out;
}

List<Widget> _findView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_meta([
    _chip('search',
        a?['pattern']?.toString() ?? d?['pattern']?.toString() ?? '*'),
    if (d?['count'] != null) _chip('file', '${d?['count']} files'),
  ]));
  final results = _mapItems(d?['results']);
  if (results.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(_Card(children: [
      for (final f in results)
        _FileRow(
            icon: 'file',
            name: f['path']?.toString() ?? f['name']?.toString() ?? ''),
    ]));
  } else if (d != null) {
    out.add(const SizedBox(height: 10));
    out.add(_empty('No files found'));
  }
  return out;
}

List<Widget> _lsView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_PathChip(a?['path']?.toString() ?? d?['path']?.toString() ?? '.'));
  final entries = _mapItems(d?['entries'])
    ..sort((x, y) {
      final dx = x['kind'] == 'dir' ? 0 : 1, dy = y['kind'] == 'dir' ? 0 : 1;
      if (dx != dy) return dx - dy;
      return (x['name']?.toString() ?? '')
          .compareTo(y['name']?.toString() ?? '');
    });
  if (entries.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(_Card(children: [
      for (final e in entries)
        _FileRow(
          icon: e['kind'] == 'dir' ? 'folder' : 'file',
          name: e['name']?.toString() ?? '',
          dir: e['kind'] == 'dir',
        ),
    ]));
  } else if (d != null) {
    out.add(const SizedBox(height: 10));
    out.add(_empty('Empty directory'));
  }
  return out;
}

List<Widget> _outlineView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_PathChip(a?['path']?.toString() ?? d?['path']?.toString() ?? ''));
  if (d?['is_directory'] == true) {
    return [...out, const SizedBox(height: 10), ..._lsView(a, d).skip(1)];
  }
  if (d?['supported'] == false) {
    out.add(const SizedBox(height: 10));
    out.add(_Hint(d?['note']?.toString() ?? 'No outline available.'));
    return out;
  }
  out.add(const SizedBox(height: 8));
  out.add(_meta([
    if (d?['language'] != null) _chip('cpu', '${d?['language']}'),
    if (d?['symbol_count'] != null)
      _chip('list', '${d?['symbol_count']} symbols'),
  ]));
  final outline = _mapItems(d?['outline']);
  if (outline.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(_Card(children: [
      for (final s in outline)
        _SymbolRow(
          kind: s['kind']?.toString() ?? '',
          signature: s['signature']?.toString() ?? '',
          line: s['line_number']?.toString(),
          depth: (s['depth'] is int) ? s['depth'] as int : 0,
        ),
    ]));
  }
  return out;
}

List<Widget> _codeMapView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_meta([
    _chip('map', (d?['root'] ?? a?['path'] ?? '.').toString()),
    if (d?['file_count'] != null) _chip('file', '${d?['file_count']} files'),
    if (d?['symbol_count'] != null)
      _chip('list', '${d?['symbol_count']} symbols'),
  ]));
  final files = _mapItems(d?['files']);
  for (final f in files) {
    out.add(const SizedBox(height: 12));
    out.add(_FileRow(icon: 'file', name: f['path']?.toString() ?? ''));
    final syms = f['symbols'] is List ? (f['symbols'] as List) : const [];
    out.add(const SizedBox(height: 4));
    out.add(_Card(children: [
      for (final s in syms)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(s.toString(),
              style: mono(11.5, height: 1.4, color: AppColors.fg2)),
        ),
    ]));
  }
  if (d?['truncated'] == true && d?['hint'] != null) {
    out.add(const SizedBox(height: 10));
    out.add(_Hint(d?['hint']?.toString() ?? ''));
  }
  return out;
}

List<Widget> _webSearchView(Map? a, Map? d) {
  final out = <Widget>[];
  out.add(_meta([
    _chip('globe', '"${a?['query'] ?? d?['query'] ?? ''}"'),
    if (d?['count'] != null) _chip('list', '${d?['count']} results'),
  ]));
  final results = _mapItems(d?['results']);
  for (final res in results) {
    out.add(const SizedBox(height: 12));
    out.add(_ResultCard(
      title: res['title']?.toString() ?? '',
      url: res['url']?.toString() ?? '',
      date: res['published_date']?.toString(),
      snippet: res['snippet']?.toString(),
    ));
  }
  return out;
}

List<Widget> _webReadView(Map? a, Map? d) {
  final out = <Widget>[];
  final title = d?['title']?.toString() ?? '';
  final url = d?['url']?.toString() ?? a?['url']?.toString() ?? '';
  if (title.isNotEmpty) {
    out.add(Text(title,
        style: sans(14.5, weight: FontWeight.w600, color: AppColors.fg1)));
    out.add(const SizedBox(height: 4));
  }
  out.add(_LinkText(url));
  if (d?['published_date'] != null) {
    out.add(const SizedBox(height: 6));
    out.add(_meta([
      _chip('history', '${d?['published_date']}'),
    ]));
  }
  final text = d?['text']?.toString();
  if (text != null && text.isNotEmpty) {
    out.add(const SizedBox(height: 12));
    out.add(const SectionLabel('Page text'));
    out.add(const SizedBox(height: 8));
    out.add(_CodeBox(text, useSans: true));
  }
  return out;
}

List<Widget> _jsonFallback(Map? a, Map? d, String? status) {
  final out = <Widget>[];
  if (a != null) {
    out.add(const SectionLabel('Arguments'));
    out.add(const SizedBox(height: 8));
    out.add(_CodeBox(_pretty(a)));
  }
  if (d != null) {
    if (a != null) out.add(const SizedBox(height: 16));
    out.add(const SectionLabel('Result'));
    out.add(const SizedBox(height: 8));
    out.add(_CodeBox(_pretty(d)));
  }
  return out;
}

// ---- shared pieces ----

String _pretty(dynamic v) {
  String s;
  try {
    s = const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    s = v.toString();
  }
  return s.length > 6000 ? '${s.substring(0, 6000)}\n…(truncated)' : s;
}

Widget _meta(List<Widget> chips) =>
    Wrap(spacing: 7, runSpacing: 7, children: chips);

Widget _chip(String icon, String label) => Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(icon, size: 11, color: AppColors.fg4),
        const SizedBox(width: 5),
        Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg3))),
      ]),
    );

Widget _statusChip(bool ok, String label) => Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: ok ? AppColors.okBg : AppColors.dangerBg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(ok ? 'check' : 'alert-triangle',
            size: 11, color: ok ? AppColors.ok : AppColors.danger),
        const SizedBox(width: 5),
        Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(10.5,
                    weight: FontWeight.w500,
                    color: ok ? AppColors.ok : AppColors.danger))),
      ]),
    );

Widget _done(String label) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _meta([_statusChip(true, label)]),
    );

Widget _empty(String label) =>
    Text(label, style: sans(12.5, color: AppColors.fg3));

class _PathChip extends StatelessWidget {
  final String path;
  const _PathChip(this.path);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        AppIcon('file', size: 13, color: AppColors.fg4),
        const SizedBox(width: 7),
        Expanded(
            child: SelectableText(path, style: mono(12, color: AppColors.fg2))),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) children[i],
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final String icon;
  final String name;
  final bool dir;
  const _FileRow({required this.icon, required this.name, this.dir = false});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(children: [
        AppIcon(icon, size: 14, color: dir ? AppColors.accent : AppColors.fg3),
        const SizedBox(width: 9),
        Expanded(
            child: Text(name,
                style: mono(12, color: dir ? AppColors.fg1 : AppColors.fg2))),
      ]),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final String path;
  final String? line;
  final String text;
  const _MatchRow({required this.path, this.line, required this.text});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
              child: Text(path,
                  overflow: TextOverflow.ellipsis,
                  style: mono(11, color: AppColors.accent))),
          if (line != null)
            Text(':$line', style: mono(11, color: AppColors.fg4)),
        ]),
        const SizedBox(height: 3),
        Text(text, style: mono(11.5, height: 1.4, color: AppColors.fg2)),
      ]),
    );
  }
}

class _SymbolRow extends StatelessWidget {
  final String kind;
  final String signature;
  final String? line;
  final int depth;
  const _SymbolRow(
      {required this.kind, required this.signature, this.line, this.depth = 0});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: EdgeInsets.fromLTRB(10.0 + depth * 14, 7, 10, 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              color: AppColors.accentBg,
              borderRadius: BorderRadius.circular(4)),
          child: Text(kind, style: mono(9.5, color: AppColors.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(signature,
                style: mono(11.5, height: 1.4, color: AppColors.fg1))),
        if (line != null) ...[
          const SizedBox(width: 6),
          Text(':$line', style: mono(10.5, color: AppColors.fg4)),
        ],
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String url;
  final String? date;
  final String? snippet;
  const _ResultCard(
      {required this.title, required this.url, this.date, this.snippet});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final snippetText = snippet ?? '';
    final dateText = date ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title,
              style: sans(13.5, weight: FontWeight.w600, color: AppColors.fg1)),
        if (title.isNotEmpty) const SizedBox(height: 4),
        _LinkText(url),
        if (snippetText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(snippetText,
              style: sans(12, height: 1.45, color: AppColors.fg2)),
        ],
        if (dateText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(dateText, style: mono(10, color: AppColors.fg4)),
        ],
      ]),
    );
  }
}

class _LinkText extends StatelessWidget {
  final String url;
  const _LinkText(this.url);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Row(children: [
      AppIcon('globe', size: 11, color: AppColors.fg4),
      const SizedBox(width: 5),
      Expanded(
          child: Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(11, color: AppColors.accent))),
    ]);
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: EdgeInsets.only(top: 1),
            child:
                AppIcon('alert-triangle', size: 14, color: AppColors.danger)),
        const SizedBox(width: 9),
        Expanded(
            child: SelectableText(message,
                style: mono(11.5, height: 1.45, color: AppColors.danger))),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border(left: BorderSide(color: AppColors.accentLine, width: 3)),
      ),
      child: Text(text, style: sans(12, height: 1.45, color: AppColors.fg2)),
    );
  }
}

// Tool previews may be JSON strings that were encoded once for the result
// envelope. Restore escaped control characters for display without changing the
// underlying command/file data.
String _displayText(String text) => text
    .replaceAll(r'\r\n', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\r');

/// Plain monospace block (selectable). Optional add/del tint or sans font.
class _CodeBox extends StatelessWidget {
  final String text;
  final bool addTint;
  final bool delTint;
  final bool useSans;
  const _CodeBox(this.text,
      {this.addTint = false, this.delTint = false, this.useSans = false});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final bg = addTint
        ? AppColors.diffAddBg
        : delTint
            ? AppColors.diffDelBg
            : AppColors.surface2;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: addTint || delTint ? bg : Colors.transparent,
      child: SelectableText(
        text,
        style: useSans
            ? sans(12, height: 1.5, color: AppColors.fg1)
            : mono(11.5, height: 1.5, color: AppColors.fg1),
      ),
    );
  }
}

/// Shell command box with a `$` prompt.
class _CommandBox extends StatelessWidget {
  final String command;
  const _CommandBox(this.command);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('\$ ', style: mono(11.5, height: 1.5, color: AppColors.accent)),
        Expanded(
            child: SelectableText(command,
                style: mono(11.5, height: 1.5, color: AppColors.fg1))),
      ]),
    );
  }
}

/// Read-only code block with syntax highlighting (by filename) + line numbers,
/// matching the file viewer. Bounded height with its own scroll for the drawer.
class _HiCodeBlock extends StatefulWidget {
  final String filename;
  final String text;
  const _HiCodeBlock(this.filename, this.text);
  @override
  State<_HiCodeBlock> createState() => _HiCodeBlockState();
}

class _HiCodeBlockState extends State<_HiCodeBlock> {
  final CodeLineEditingController _c = CodeLineEditingController();

  @override
  void initState() {
    super.initState();
    _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final lineCount = '\n'.allMatches(widget.text).length + 1;
    // Snug height for short files; cap + internal scroll for long ones.
    final h = (lineCount * 20.0 + 16).clamp(44.0, 360.0);
    return SizedBox(
      width: double.infinity,
      height: h,
      child: CodeEditor(
        controller: _c,
        readOnly: true,
        wordWrap: false,
        style: codeEditorStyle(widget.filename, background: AppColors.bg),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
          return Row(children: [
            DefaultCodeLineNumber(
                controller: editingController, notifier: notifier),
            DefaultCodeChunkIndicator(
                width: 20, controller: chunkController, notifier: notifier),
          ]);
        },
      ),
    );
  }
}

// ---- diff ----

enum _DKind { ctx, add, del }

class _DLine {
  final _DKind kind;
  final String text;
  const _DLine(this.kind, this.text);
}

/// Line-level unified diff via LCS. Falls back to remove-all/add-all for very
/// large inputs (keeps it O(1) instead of O(n·m)).
List<_DLine> _diff(String aStr, String bStr) {
  final a = aStr.split('\n');
  final b = bStr.split('\n');
  final n = a.length, m = b.length;
  if (n * m > 250000) {
    return [
      for (final l in a) _DLine(_DKind.del, l),
      for (final l in b) _DLine(_DKind.add, l),
    ];
  }
  // LCS dp table (suffix form).
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <_DLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(_DLine(_DKind.ctx, a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(_DLine(_DKind.del, a[i]));
      i++;
    } else {
      out.add(_DLine(_DKind.add, b[j]));
      j++;
    }
  }
  while (i < n) {
    out.add(_DLine(_DKind.del, a[i++]));
  }
  while (j < m) {
    out.add(_DLine(_DKind.add, b[j++]));
  }
  return out;
}

class _DiffBlock extends StatelessWidget {
  final String before;
  final String after;
  const _DiffBlock(this.before, this.after);
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final lines = _diff(before, after);
    final added = lines.where((l) => l.kind == _DKind.add).length;
    final removed = lines.where((l) => l.kind == _DKind.del).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text('diff', style: mono(11, color: AppColors.fg4)),
            const Spacer(),
            if (added > 0)
              Text('+$added', style: mono(11, color: AppColors.diffAddFg)),
            if (added > 0 && removed > 0) const SizedBox(width: 8),
            if (removed > 0)
              Text('−$removed', style: mono(11, color: AppColors.diffDelFg)),
          ]),
        ),
        for (final l in lines) _row(l),
      ],
    );
  }

  Widget _row(_DLine l) {
    final (Color bg, Color fg, String sign) = switch (l.kind) {
      _DKind.add => (AppColors.diffAddBg, AppColors.diffAddFg, '+'),
      _DKind.del => (AppColors.diffDelBg, AppColors.diffDelFg, '-'),
      _DKind.ctx => (AppColors.surface2, AppColors.fg3, ' '),
    };
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1.5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 12,
            child: Text(sign, style: mono(11.5, height: 1.45, color: fg))),
        Expanded(
            child: Text(l.text.isEmpty ? ' ' : l.text,
                style: mono(11.5, height: 1.45, color: fg))),
      ]),
    );
  }
}
