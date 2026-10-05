import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:re_editor/re_editor.dart';

import 'coordination_tool_views.dart';
import 'highlight.dart';
import 'media_views.dart';
import 'theme.dart';
import 'tool_activity.dart';
import 'widgets.dart';
import 'platform.dart';

// The daemon can evolve independently of the client. Keep malformed or newer
// result items visible only as far as they can be safely rendered; one bad item
// must not make the entire tool panel fail to build.
List<Map> _mapItems(dynamic value) =>
    value is List ? value.whereType<Map>().toList() : const <Map>[];

/// Per-tool rendering: a glyph + one-line summary for the inline tool row, and
// a rich, tool-specific body for the detail drawer (never raw JSON unless unknown).

/// Lucide-ish glyph name for a tool (resolved via [iconFor]).
String toolIcon(String tool) => switch (tool) {
      'change_files' => 'edit',
      'view_image' => 'image',
      'bash' => 'terminal',
      'web_search' || 'web_read' => 'globe',
      'set_session_title' => 'edit',
      'search_skills' || 'skill' => 'zap',
      'monitor' => 'activity',
      'present_file' => 'file',
      _ => 'code',
    };

/// One-line, tool-aware summary for the inline activity line.
String toolArgSummary(String tool, dynamic args) {
  if (args is! Map) return '';
  String s(String k) => args[k]?.toString() ?? '';
  String first(String v) => v.split('\n').first.trim();
  final v = switch (tool) {
    // The command itself, not a placeholder. Showing "shell command" for every
    // bash call made the transcript unreadable: `cargo test`, `rm -rf build` and
    // `git push` all rendered identically, so a person watching the agent work
    // could not tell what it was doing without expanding every row.
    'bash' => s('label').isNotEmpty ? s('label') : s('command'),
    'manage_process' => [
        switch (s('action')) {
          'kill' => 'Stop',
          'log' => 'Read log of',
          _ => 'List processes',
        },
        if (s('action') != 'list' && s('id').isNotEmpty) s('id'),
      ].join(' '),
    'web_search' => s('query'),
    'web_read' => s('url'),
    'change_files' => _changesSummary(args['changes']),
    'view_image' => s('path'),
    'set_session_title' => s('title'),
    'search_skills' => s('query'),
    'skill' => s('name'),
    'monitor' => s('path').isNotEmpty ? s('path') : s('action'),
    'present_file' => s('path'),
    'read_file' => s('path'),
    'ping_user' => s('title'),
    'schedule_followup' => s('note'),
    _ => '',
  };
  if (v.isNotEmpty) return first(v);
  for (final k in const [
    'title',
    'id',
    'name',
    'command',
    'path',
    'query',
    'pattern',
    'url',
    'file',
    'content'
  ]) {
    if (args[k] is String) return first(args[k] as String);
  }
  return '';
}

/// Whether a step has anything behind its row — the one rule the transcript
/// rows and the tool sheet share.
bool toolHasDetail(ToolStep step) {
  final tool = step.tool;
  final args = step.args;
  final result = step.result;
  String arg(String key) {
    if (args is! Map) return '';
    return (args[key] ?? '').toString();
  }

  bool resultHasBody() {
    if (result == null) return false;
    if (result is! Map) return result.toString().trim().isNotEmpty;
    if ((result['status'] ?? '').toString() == 'error') return true;
    final data = result['data'] is Map ? result['data'] as Map : result;
    for (final key in const ['stdout', 'stderr', 'content', 'text', 'output']) {
      if ((data[key] ?? '').toString().trim().isNotEmpty) return true;
    }
    for (final key in const ['entries', 'matches', 'results']) {
      final list = data[key];
      if (list is List && list.isNotEmpty) return true;
    }
    return false;
  }

  // A failure always has something to show: the error.
  if (result is Map && (result['status'] ?? '').toString() == 'error') {
    return true;
  }
  // A running step can still have content in its arguments (a diff, a long
  // command); each check below looks only where its content lives.
  if (ackTools.contains(tool)) return false;
  final data = result is Map && result['data'] is Map
      ? result['data'] as Map
      : (result is Map ? result : null);
  final coordination =
      coordinationHasDetail(tool, args is Map ? args : null, data);
  if (coordination != null) return coordination;

  switch (tool) {
    case 'change_files':
      final changes = args is Map ? args['changes'] : null;
      return changes is List && changes.isNotEmpty;
    case 'view_image':
    case 'present_file':
      return arg('path').trim().isNotEmpty ||
          (data?['path'] ?? '').toString().trim().isNotEmpty;
    case 'bash':
      final cmd = arg('command');
      return arg('label').trim().isNotEmpty ||
          cmd.split('\n').length > 1 ||
          cmd.length > 80 ||
          resultHasBody();
    case 'web_search':
    case 'web_read':
      return resultHasBody();
    case 'read_file':
      return true;
    default:
      final shown = toolArgSummary(tool, args);
      return shown.contains('…') || resultHasBody();
  }
}

/// Friendly title for the drawer header.
String toolTitle(String tool) => switch (tool) {
      'change_files' => 'Change',
      'view_image' => 'Image',
      'bash' => 'Run',
      'web_search' => 'Search',
      'web_read' => 'Page',
      'set_session_title' => 'Title',
      'search_skills' => 'Skills',
      'skill' => 'Skill',
      'monitor' => 'Watch',
      'present_file' => 'Present',
      'read_file' => 'Read',
      _ => _humanizeTool(tool),
    };

String _humanizeTool(String tool) {
  final parts = tool.split(RegExp(r'[_\-]+')).where((p) => p.isNotEmpty);
  return parts
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

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

  if (status == 'error' && errMsg != null && tool == 'bash') {
    final cmd = _displayText(a?['command']?.toString() ?? '').trimRight();
    return _wrap([
      _ShellPanel(
          command: cmd,
          stdout: '',
          stderr: errMsg,
          exitCode: null,
          failed: true),
    ]);
  }

  // Error banner first — applies to every tool.
  if (status == 'error' && errMsg != null) {
    rows.add(_ErrorBox(errMsg));
    rows.add(const SizedBox(height: S.s8));
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
    rows.add(Text('No details.', style: TS.meta()));
  }
  return _wrap(rows);
}

Widget _wrap(List<Widget> rows) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);

List<Widget> _toolBody(
    BuildContext context, String tool, Map? a, Map? d, String? status) {
  switch (tool) {
    case 'change_files':
      return _changeFilesView(a, d);
    case 'view_image':
      return _imageView(context, a, d);
    case 'bash':
      return _bashView(a, d);
    case 'web_search':
      return _webSearchView(a, d);
    case 'web_read':
      return _webReadView(a, d);
    case 'set_session_title':
      return _titleView(a, d);
    case 'search_skills':
    case 'skill':
      return _skillView(tool, a, d);
    case 'monitor':
      return _monitorView(a, d);
    case 'present_file':
      return _presentView(context, a, d);
    case 'read_file':
      return _readFileView(a, d);
    default:
      if (d?['custom_tool'] != null) {
        return _bashView({'command': d?['command'], 'label': tool}, d);
      }
      return coordinationToolBody(context, tool, a, d) ?? _simpleFallback(a, d);
  }
}

// ---- per-tool views ----

String _changesSummary(dynamic changes) {
  if (changes is! List || changes.isEmpty) return '';
  final first = changes.first is Map
      ? (changes.first as Map)['path']?.toString() ?? ''
      : '';
  return changes.length == 1 ? first : '$first (+${changes.length - 1} more)';
}

List<Widget> _changeFilesView(Map? a, Map? d) {
  final changes = a?['changes'];
  if (changes is! List) return const [];
  final out = <Widget>[];
  for (final raw in changes.whereType<Map>()) {
    String field(String key) => raw[key]?.toString() ?? '';
    final path = field('path');
    if (out.isNotEmpty) out.add(const SizedBox(height: S.s8));
    switch (field('action')) {
      case 'replace':
        final lines = _diff(field('find'), field('with'));
        final adds = lines.where((l) => l.kind == _DKind.add).length;
        final dels = lines.where((l) => l.kind == _DKind.del).length;
        out.add(_ToolPanel(
          header: _PanelPath(path),
          trailing: [
            if (raw['all'] == true) const Tag('All matches', mono: true),
            if (adds > 0) Tag('+$adds', tone: Tone.ok, mono: true),
            if (dels > 0) Tag('-$dels', tone: Tone.danger, mono: true),
          ],
          copyText: field('with'),
          padBody: false,
          body: _DiffBlock.lines(lines),
        ));
      case 'create':
        final content = field('content');
        final n = content.isEmpty
            ? 0
            : '\n'.allMatches(content.trimRight()).length + 1;
        out.add(_ToolPanel(
          header: _PanelPath(path),
          trailing: [
            if (raw['overwrite'] == true)
              const Tag('Overwrite', tone: Tone.run),
            Tag('$n ${n == 1 ? 'line' : 'lines'}', mono: true),
          ],
          copyText: content,
          padBody: false,
          body: _HiCodeBlock(path, content.replaceFirst(RegExp(r'\n$'), '')),
        ));
      case 'delete':
        out.add(_ToolPanel(
          header: _PanelPath(path),
          trailing: const [Tag('Deleted', tone: Tone.danger)],
        ));
      case 'move':
        out.add(_ToolPanel(
          header: _PanelPath('$path → ${field('to')}'),
          trailing: const [Tag('Moved')],
        ));
    }
  }
  final notes = d?['notes']?.toString();
  if (notes != null && notes.isNotEmpty) {
    out.add(const SizedBox(height: S.s8));
    out.add(_Hint(notes));
  }
  return out;
}

List<Widget> _imageView(BuildContext context, Map? a, Map? d) {
  final path = (d?['path'] ?? a?['path'])?.toString() ?? '';
  final client = DaemonScope.maybeOf(context);
  if (path.isEmpty) return const [];
  if (client == null) return [Text(path, style: TS.label(AppColors.fg2))];
  return [
    LayoutBuilder(
      builder: (_, c) => ImageThumb(
        client: client,
        path: path,
        width: c.maxWidth.clamp(0, 420),
        height: 220,
        fit: BoxFit.contain,
      ),
    ),
  ];
}

String _previewLines(String text, {int maxLines = 6}) {
  final lines = text.split('\n');
  if (lines.length <= maxLines) return text;
  return '${lines.take(maxLines).join('\n')}\n…';
}

List<Widget> _bashView(Map? a, Map? d) {
  final cmd = _displayText(a?['command']?.toString() ?? '').trimRight();
  final stdout =
      _previewLines(_displayText(d?['stdout']?.toString() ?? '').trimRight());
  final stderr =
      _previewLines(_displayText(d?['stderr']?.toString() ?? '').trimRight());
  final exit = (d?['exit_code'] as num?)?.toInt();
  final labelled = (a?['label']?.toString() ?? '').trim().isNotEmpty;
  if (cmd.isEmpty && stdout.isEmpty && stderr.isEmpty) {
    return [Text('No output', style: TS.meta())];
  }
  return [
    _ShellPanel(
        command: cmd,
        stdout: stdout,
        stderr: stderr,
        exitCode: exit,
        showCommand: labelled)
  ];
}

List<Widget> _readFileView(Map? a, Map? d) {
  final path = (d?['path'] ?? a?['path'] ?? '').toString();
  final entries = d?['entries'];
  if (entries is List) {
    final total = (d?['total'] as num?)?.toInt() ?? entries.length;
    final lines = entries.map((e) {
      final parts = e.toString().split('\t');
      return parts.length == 2
          ? '${parts[0].padRight(36)} ${parts[1]}'
          : e.toString();
    }).join('\n');
    return [
      _ToolPanel(
        header: _PanelPath(path, icon: 'folder'),
        trailing: [
          Tag('$total ${total == 1 ? 'entry' : 'entries'}', mono: true)
        ],
        copyText: lines,
        body: _PanelText(lines.isEmpty ? '(empty folder)' : lines),
      ),
    ];
  }
  if (d?['binary'] == true) {
    return [
      _ToolPanel(
        header: _PanelPath(path),
        body:
            Text('Binary file, ${d?['bytes'] ?? '?'} bytes', style: TS.meta()),
      ),
    ];
  }
  final content = (d?['content'] ?? '').toString();
  final total = (d?['total_lines'] as num?)?.toInt();
  if (content.isEmpty && path.isEmpty) return const [];
  return [
    _ToolPanel(
      header: _PanelPath(path),
      trailing: [
        if (total != null)
          Tag('$total ${total == 1 ? 'line' : 'lines'}', mono: true),
      ],
      copyText: content,
      body: _PanelText(content.isEmpty
          ? '(empty file)'
          : _previewLines(content, maxLines: 400)),
    ),
  ];
}

List<Widget> _webSearchView(Map? a, Map? d) {
  final results = _mapItems(d?['results']);
  if (results.isEmpty) return const [];
  final query = a?['query']?.toString() ?? '';
  return [
    _ToolPanel(
      header: _PanelPath(query, icon: 'globe'),
      trailing: [
        Tag('${results.length} ${results.length == 1 ? 'result' : 'results'}',
            mono: true),
      ],
      body: _SearchHitList(children: [
        for (final res in results)
          _ResultCard(
            title: res['title']?.toString() ?? '',
            url: res['url']?.toString() ?? '',
            date: res['published_date']?.toString(),
            snippet: res['snippet']?.toString(),
            query: query,
          ),
      ]),
    ),
  ];
}

List<Widget> _webReadView(Map? a, Map? d) {
  final out = <Widget>[];
  final title = d?['title']?.toString() ?? '';
  if (title.isNotEmpty) {
    out.add(Text(title,
        style: sans(kMobile ? 14 : 13, weight: W.label, color: AppColors.fg1)));
    out.add(const SizedBox(height: 4));
  }
  if (d?['published_date'] != null) {
    out.add(
        Text('${d?['published_date']}', style: mono(10, color: AppColors.fg3)));
  }
  final text = d?['text']?.toString();
  if (text != null && text.isNotEmpty) {
    if (out.isNotEmpty) out.add(const SizedBox(height: 8));
    out.add(_CodeBox(text, useSans: true));
  }
  return out;
}

List<Widget> _titleView(Map? a, Map? d) {
  final title = (d?['title'] ?? a?['title'])?.toString() ?? '';
  if (title.trim().isEmpty) {
    return [Text('Cleared title', style: sans(13, color: AppColors.fg3))];
  }
  return [
    Text(title,
        style: sans(kMobile ? 14 : 13, weight: W.label, color: AppColors.fg1)),
  ];
}

List<Widget> _skillView(String tool, Map? a, Map? d) {
  final name = (d?['name'] ?? a?['name'] ?? a?['query'])?.toString() ?? '';
  final text =
      (d?['content'] ?? d?['description'] ?? d?['text'])?.toString() ?? '';
  final out = <Widget>[];
  if (name.isNotEmpty) {
    out.add(Text(name, style: TS.label(AppColors.fg1)));
  }
  if (text.trim().isNotEmpty) {
    if (out.isNotEmpty) out.add(const SizedBox(height: 6));
    out.add(_ToolMarkdown(_displayText(text).trimRight()));
  }
  if (out.isEmpty) {
    out.add(Text(toolTitle(tool), style: sans(13, color: AppColors.fg3)));
  }
  return out;
}

List<Widget> _monitorView(Map? a, Map? d) {
  final action = (a?['action'] ?? d?['action'] ?? 'add').toString();
  final path = (a?['path'] ?? d?['path'])?.toString() ?? '';
  final filter = (a?['filter'] ?? d?['filter'])?.toString() ?? '';
  final out = <Widget>[
    Text(action, style: TS.label(AppColors.fg1)),
  ];
  if (path.isNotEmpty) {
    out.add(const SizedBox(height: 4));
    out.add(Text(path, style: mono(12, color: AppColors.fg2)));
  }
  if (filter.isNotEmpty) {
    out.add(const SizedBox(height: 4));
    out.add(Text(filter, style: mono(11, color: AppColors.fg3)));
  }
  return out;
}

List<Widget> _presentView(BuildContext context, Map? a, Map? d) {
  final path = (a?['path'] ?? d?['path'])?.toString() ?? '';
  final caption = (a?['caption'] ?? d?['caption'])?.toString() ?? '';
  final client = DaemonScope.maybeOf(context);
  return [
    if (path.isNotEmpty)
      client == null
          ? Text(path, style: TS.label(AppColors.fg1))
          : FileChip(client: client, path: path),
    if (caption.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(caption, style: sans(13, color: AppColors.fg3)),
    ],
  ];
}

List<Widget> _simpleFallback(Map? a, Map? d) {
  final bits = <String>[];
  void take(dynamic v) {
    if (v is String && v.trim().isNotEmpty) bits.add(v.trim());
  }

  if (a != null) {
    for (final k in const [
      'title',
      'id',
      'name',
      'path',
      'query',
      'content',
      'text'
    ]) {
      take(a[k]);
    }
  }
  if (d != null) {
    for (final k in const [
      'title',
      'id',
      'name',
      'path',
      'content',
      'text',
      'message'
    ]) {
      take(d[k]);
    }
  }
  if (bits.isEmpty) {
    return [Text('Done', style: sans(13, color: AppColors.fg3))];
  }
  return [
    _CodeBox(_previewLines(_displayText(bits.first).trimRight(), maxLines: 8),
        useSans: true)
  ];
}

// ---- shared pieces ----

class _SearchHitList extends StatelessWidget {
  final List<Widget> children;
  const _SearchHitList({required this.children});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.border),
          children[i],
        ],
      ],
    );
  }
}

Widget _highlightedLine(String text, String query) {
  final base = mono(11, height: 1.45, color: AppColors.fg2);
  final q = query.trim();
  if (q.isEmpty) return Text(text, style: base);
  final lower = text.toLowerCase();
  final needle = q.toLowerCase();
  final spans = <InlineSpan>[];
  var i = 0;
  while (i < text.length) {
    final at = lower.indexOf(needle, i);
    if (at < 0) {
      spans.add(TextSpan(text: text.substring(i)));
      break;
    }
    if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
    spans.add(TextSpan(
      text: text.substring(at, at + needle.length),
      style: mono(11, height: 1.45, color: AppColors.accent, weight: W.label)
          .copyWith(backgroundColor: AppColors.accentBg),
    ));
    i = at + needle.length;
  }
  return Text.rich(TextSpan(style: base, children: spans));
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String url;
  final String? date;
  final String? snippet;
  final String query;
  const _ResultCard(
      {required this.title,
      required this.url,
      this.date,
      this.snippet,
      this.query = ''});
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final snippetText = snippet ?? '';
    final dateText = date ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: W.label, color: AppColors.accent)),
        if (url.isNotEmpty) ...[
          if (title.isNotEmpty) const SizedBox(height: 2),
          Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(11, color: AppColors.fg3)),
        ],
        if (snippetText.isNotEmpty) ...[
          const SizedBox(height: 4),
          _highlightedLine(snippetText, query),
        ],
        if (dateText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(dateText, style: mono(10, color: AppColors.fg3)),
        ],
      ]),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);
  @override
  Widget build(BuildContext context) {
    return InsetPanel(
      tone: Tone.danger,
      padding: const EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: S.s2),
            child:
                AppIcon('alert-triangle', size: 14, color: AppColors.danger)),
        const SizedBox(width: S.s8),
        Expanded(
            child:
                SelectableText(message, style: _panelCode(AppColors.danger))),
      ]),
    );
  }
}

class _ToolMarkdown extends StatelessWidget {
  final String data;
  const _ToolMarkdown(this.data);
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: false,
      styleSheet: markdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => InsetPanel(
        padding: const EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: S.s2),
              child: AppIcon('alert-circle', size: 14, color: AppColors.fg3)),
          const SizedBox(width: S.s8),
          Expanded(child: Text(text, style: TS.meta(AppColors.fg2))),
        ]),
      );
}

// Tool previews may be JSON strings that were encoded once for the result
// envelope. Restore escaped control characters for display without changing the
// underlying command/file data.
String _displayText(String text) => text
    .replaceAll(r'\r\n', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\r');

class _ShellPanel extends StatelessWidget {
  final String command;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool failed;
  final bool showCommand;
  const _ShellPanel(
      {required this.command,
      required this.stdout,
      required this.stderr,
      this.exitCode,
      this.failed = false,
      this.showCommand = false});

  @override
  Widget build(BuildContext context) {
    final copyText = [
      if (command.isNotEmpty) command,
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ].join('\n');
    final multiLine = command.contains('\n');
    // The command appears once: in the body when it would not fit the header
    // (labelled, multi-line or long), otherwise in the header alone.
    final withCommand =
        (showCommand || multiLine || command.length > 60) && command.isNotEmpty;
    final hasOutput = stdout.isNotEmpty || stderr.isNotEmpty || withCommand;
    return _ToolPanel(
      header: withCommand
          ? Text('shell', style: _panelCode(AppColors.fg3))
          : Text.rich(
              TextSpan(children: [
                TextSpan(text: '\$ ', style: _panelCode(AppColors.accent)),
                TextSpan(text: command, style: _panelCode(AppColors.fg1)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: [
        if (exitCode != null)
          Tag('exit $exitCode',
              tone: exitCode == 0 ? Tone.ok : Tone.danger, mono: true)
        else if (failed)
          const Tag('Failed', tone: Tone.danger, dot: true),
      ],
      copyText: copyText,
      body: hasOutput
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (withCommand) ...[
                  _PanelCommand(command),
                  if (stdout.isNotEmpty || stderr.isNotEmpty)
                    const SizedBox(height: S.s8),
                ],
                if (stdout.isNotEmpty) _PanelText(stdout),
                if (stdout.isNotEmpty && stderr.isNotEmpty)
                  const SizedBox(height: S.s6),
                if (stderr.isNotEmpty)
                  _PanelText(stderr, color: AppColors.danger),
              ],
            )
          : null,
    );
  }
}

TextStyle _panelCode([Color? color]) =>
    mono(12, height: 1.4, color: color ?? AppColors.fg2);

class _PanelCommand extends StatelessWidget {
  const _PanelCommand(this.command);

  final String command;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText.rich(TextSpan(children: [
            TextSpan(text: '\$ ', style: _panelCode(AppColors.accent)),
            TextSpan(text: command, style: _panelCode(AppColors.fg1)),
          ])),
        ),
      );
}

class _PanelText extends StatelessWidget {
  const _PanelText(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(text, style: _panelCode(color)),
        ),
      );
}

class _PanelPath extends StatelessWidget {
  const _PanelPath(this.text, {this.icon = 'file'});

  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      AppIcon(icon, size: 14, color: AppColors.fg3),
      const SizedBox(width: S.s6),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _panelCode(AppColors.fg1)),
      ),
    ]);
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    this.header,
    this.trailing = const [],
    this.body,
    this.copyText,
    this.padBody = true,
  });

  final Widget? header;
  final List<Widget> trailing;
  final Widget? body;
  final String? copyText;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final copy = copyText;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null ||
              trailing.isNotEmpty ||
              (copy != null && copy.isNotEmpty))
            Container(
              constraints: const BoxConstraints(minHeight: 28),
              color: AppColors.overlay,
              padding: const EdgeInsets.fromLTRB(S.s8, S.s2, S.s2, S.s2),
              child: Row(children: [
                if (header != null)
                  Expanded(child: header!)
                else
                  const Spacer(),
                const SizedBox(width: S.s6),
                for (final t in trailing) ...[t, const SizedBox(width: S.s6)],
                if (copy != null && copy.isNotEmpty)
                  Tooltip(
                    message: 'Copy',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.sm),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Clipboard.setData(ClipboardData(text: copy));
                        toast(context, 'Copied');
                      },
                      child: SizedBox.square(
                        dimension: 28,
                        child: Center(
                            child: AppIcon('copy',
                                size: 13, color: AppColors.fg3)),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: S.s8),
              ]),
            ),
          if (body != null)
            padBody
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s8),
                    child: body)
                : body!,
        ],
      ),
    );
  }
}

/// Plain monospace block (selectable). Optional add tint or sans font.
class _CodeBox extends StatelessWidget {
  final String text;
  final bool useSans;
  const _CodeBox(this.text, {this.useSans = false});
  @override
  Widget build(BuildContext context) {
    return _ToolPanel(
      copyText: text,
      body: useSans
          ? SelectableText(text, style: TS.ui(AppColors.fg2))
          : _PanelText(text),
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
    final h = (lineCount * 20.0 + 10).clamp(32.0, 320.0);
    return SizedBox(
      width: double.infinity,
      height: h,
      child: CodeEditor(
        controller: _c,
        readOnly: true,
        showCursorWhenReadOnly: false,
        wordWrap: false,
        style: codeEditorStyle(widget.filename, background: AppColors.raised),
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
  final List<_DLine> diffLines;
  const _DiffBlock.lines(this.diffLines);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in diffLines) _row(l)],
      ),
    );
  }

  Widget _row(_DLine l) {
    final (Color bg, Color fg, String sign) = switch (l.kind) {
      _DKind.add => (AppColors.diffAddBg, AppColors.diffAddFg, '+'),
      _DKind.del => (AppColors.diffDelBg, AppColors.diffDelFg, '-'),
      _DKind.ctx => (Colors.transparent, AppColors.fg3, ' '),
    };
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: S.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 16, child: Text(sign, style: _panelCode(fg))),
        Expanded(
            child: Text(l.text.isEmpty ? ' ' : l.text, style: _panelCode(fg))),
      ]),
    );
  }
}
