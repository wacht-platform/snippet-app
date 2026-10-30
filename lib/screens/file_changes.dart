import 'package:flutter/material.dart';

import '../file_icons.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';

List<ToolStep> sessionChangeSteps(List<Map<String, dynamic>> events) {
  final out = <ToolStep>[];
  Map<String, dynamic>? pending;
  for (final e in events) {
    final k = e['kind'];
    if (k == 'tool_call') {
      pending = e;
    } else if (k == 'tool_result') {
      final p = pending;
      pending = null;
      final tool = (p?['tool_name'] ?? e['tool_name'])?.toString() ?? '';
      if (toolBaseName(tool) != 'change_files') continue;
      out.add(ToolStep(tool: tool, args: p?['arguments'], result: e['result']));
    }
  }
  return out;
}

(String, String) _split(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? (path, '') : (path.substring(i + 1), path.substring(0, i));
}

class FileChangesScreen extends StatelessWidget {
  const FileChangesScreen({super.key, required this.steps});

  final List<ToolStep> steps;

  @override
  Widget build(BuildContext context) {
    final changes = fileChanges(steps);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MobileBackBar(
            title: 'File changes',
            subtitle:
                '${changes.length} file${changes.length == 1 ? '' : 's'} in this session',
            onTitleTap: () {},
          ),
          Expanded(
            child: changes.isEmpty
                ? const EmptyState(
                    icon: 'file',
                    title: 'No file changes yet',
                    body: 'Files this session edits show up here.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                    itemCount: changes.length,
                    itemBuilder: (_, i) {
                      final c = changes[i];
                      final (name, dir) = _split(c.path);
                      return InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                FileChangeDetail(path: c.path, steps: steps),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: i + 1 < changes.length
                                      ? AppColors.line
                                      : Colors.transparent),
                            ),
                          ),
                          child: Row(children: [
                            FileGlyph(name, size: 18),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sans(15.5, color: AppColors.fg1)),
                                  if (dir.isNotEmpty)
                                    Text(dir,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            sans(12.5, color: AppColors.fg4)),
                                ],
                              ),
                            ),
                            if (c.kind == FileChangeKind.deleted)
                              Text('deleted',
                                  style: sans(13, color: AppColors.danger))
                            else ...[
                              Text('+${c.added}',
                                  style: mono(12.5, color: AppColors.ok)),
                              const SizedBox(width: 6),
                              Text('−${c.removed}',
                                  style: mono(12.5, color: AppColors.danger)),
                            ],
                            const SizedBox(width: 8),
                            AppIcon('chevron-right',
                                size: 14, color: AppColors.fg4),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class FileChangeDetail extends StatelessWidget {
  const FileChangeDetail({super.key, required this.path, required this.steps});

  final String path;
  final List<ToolStep> steps;

  List<Map> get _edits => [
        for (final s in steps)
          if (!s.failed)
            for (final c in s.changes)
              if ((c['action'] == 'move'
                      ? '${c['path']} → ${c['to']}'
                      : c['path']?.toString()) ==
                  path)
                c,
      ];

  Widget _lines(String text, Color fg, Color bg, String sign) {
    final lines = text.trimRight().split('\n');
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('$sign $l', style: mono(12, height: 1.55, color: fg)),
          ),
      ]),
    );
  }

  Widget _edit(Map c) {
    final action = c['action']?.toString() ?? '';
    final add = Color.lerp(AppColors.ok, AppColors.fg1, 0.55)!;
    final del = Color.lerp(AppColors.danger, AppColors.fg1, 0.55)!;
    final addBg = AppColors.ok.withValues(alpha: 0.10);
    final delBg = AppColors.danger.withValues(alpha: 0.10);
    final Widget body = switch (action) {
      'create' => _lines(c['content']?.toString() ?? '', add, addBg, '+'),
      'replace' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((c['find']?.toString() ?? '').isNotEmpty)
              _lines(c['find'].toString(), del, delBg, '−'),
            if ((c['with']?.toString() ?? '').isNotEmpty)
              _lines(c['with'].toString(), add, addBg, '+'),
          ],
        ),
      'delete' => Padding(
          padding: const EdgeInsets.all(14),
          child: Text('File deleted', style: sans(14, color: AppColors.danger)),
        ),
      'move' => Padding(
          padding: const EdgeInsets.all(14),
          child: Text('Moved to ${c['to']}',
              style: sans(14, color: AppColors.fg2)),
        ),
      _ => const SizedBox.shrink(),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.bg, Colors.black, 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fg1.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (name, dir) = _split(path);
    final edits = _edits;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MobileBackBar(
            title: name,
            subtitle: dir.isEmpty
                ? '${edits.length} edit${edits.length == 1 ? '' : 's'}'
                : dir,
            onTitleTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [for (final c in edits) _edit(c)],
            ),
          ),
        ]),
      ),
    );
  }
}
