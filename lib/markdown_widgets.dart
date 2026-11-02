import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'highlight.dart';
import 'screens/artifact_viewer.dart' show MermaidDiagram, canRenderMermaid;
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class ThinkingMarkdown extends StatelessWidget {
  final String data;
  const ThinkingMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final text = data.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: unwrapCodedLinks(text),
      selectable: false,
      styleSheet: thinkingMarkdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context, txt),
    );
  }
}

/// A compact, clipped text preview for summaries shown in lane cards and notices.
/// MarkdownBody uses a Column internally, so constraining it to a fixed preview
/// height can overflow for long lists or code blocks. A native Text preview keeps
/// its line limit under the parent constraints.
class MarkdownPreview extends StatelessWidget {
  final String data;
  final int maxLines;
  final TextStyle? style;

  const MarkdownPreview({
    super.key,
    required this.data,
    this.maxLines = 2,
    this.style,
  });

  static String plain(String md) {
    var t = md.replaceAll(RegExp(r'```[a-zA-Z0-9_-]*'), '');
    t = t.replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    t = t.replaceAllMapped(RegExp(r'^\s{0,3}#{1,6}\s+(.*)$', multiLine: true),
        (m) => '${m.group(1)!.trim()} · ');
    t = t.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*([-*+]|\d+\.)\s+', multiLine: true), '• ');
    t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!);
    t = t.replaceAllMapped(
        RegExp(r'(?<![\w*])[*_]([^*_\n]+)[*_](?![\w*])'), (m) => m.group(1)!);
    t = t.replaceAll('`', '');
    return t
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s*·$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      plain(data),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style ?? sans(12, height: 1.35, color: AppColors.fg3),
    );
  }
}

/// Inline `code` only. Fenced blocks are handled by [PreBlockBuilder] on `pre`
/// so we don't nest a second chrome box or paint the accent pill on whole blocks.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final raw = element.textContent;
    final isBlock = raw.contains('\n') ||
        (element.attributes['class'] ?? '').startsWith('language-');
    if (isBlock) {
      // Nested under <pre> — PreBlockBuilder owns the chrome; return plain text.
      final code = raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
      return Text(code, style: mono(13, height: 1.5, color: AppColors.fg1));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(R.xs),
      ),
      child: Text(raw, style: mono(13, color: AppColors.accent)),
    );
  }
}

/// Fenced ``` blocks — highlighted text only, no boxed chrome.
class PreBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    var lang = '';
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        if (cls.startsWith('language-')) lang = cls.substring(9);
        break;
      }
    }
    final lower = lang.trim().toLowerCase();
    if (lower == 'mermaid' && canRenderMermaid) {
      return MermaidDiagram(code: code);
    }
    if (lower == 'diff' ||
        lower == 'patch' ||
        (lower.isEmpty &&
            (code.startsWith('diff --git ') ||
                (code.startsWith('--- ') && code.contains('\n+++ '))))) {
      return _MdDiffBlock(code: code);
    }
    return _MdCodeBlock(code: code, language: lang);
  }
}

enum _MdDiffKind { hunk, meta, add, del, ctx }

class _MdDiffLine {
  final _MdDiffKind kind;
  final int? oldNum;
  final int? newNum;
  final String text;
  const _MdDiffLine(this.kind, this.text, {this.oldNum, this.newNum});
}

class _MdDiffBlock extends StatefulWidget {
  final String code;
  const _MdDiffBlock({required this.code});

  @override
  State<_MdDiffBlock> createState() => _MdDiffBlockState();
}

class _MdDiffBlockState extends State<_MdDiffBlock> {
  static const int _initialCap = 42;
  static const _headers = [
    'diff --git ',
    'index ',
    '--- ',
    '+++ ',
    'new file mode',
    'deleted file mode',
    'similarity index',
    'rename from ',
    'rename to ',
  ];
  static final _hunkRe = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)');

  bool _wrap = true;
  bool _expanded = false;

  ({
    String? file,
    List<_MdDiffLine> lines,
    int adds,
    int dels,
    int maxLineNum,
  }) _parse() {
    String? file;
    final out = <_MdDiffLine>[];
    var oldN = 0;
    var newN = 0;
    var adds = 0;
    var dels = 0;
    var maxNum = 0;
    var inHunk = false;
    var rawNum = 1;

    for (final raw in widget.code.split('\n')) {
      if (raw.startsWith('\\')) continue;
      if (file == null && raw.startsWith('diff --git ')) {
        final parts = raw.split(' b/');
        if (parts.length > 1) file = parts.last.trim();
      } else if (file == null && raw.startsWith('+++ b/')) {
        file = raw.substring(6).trim();
      }
      final m = _hunkRe.firstMatch(raw);
      if (m != null) {
        oldN = int.parse(m.group(1)!);
        newN = int.parse(m.group(2)!);
        final ctx = m.group(3)!.trim();
        out.add(_MdDiffLine(
          _MdDiffKind.hunk,
          ctx.isEmpty ? raw : '@@ -${m.group(1)} +${m.group(2)} @@  $ctx',
        ));
        inHunk = true;
        continue;
      }
      if (raw.startsWith('diff --git ')) {
        inHunk = false;
        final nextFile = raw.split(' b/').last.trim();
        if (out.isNotEmpty && nextFile.isNotEmpty) {
          out.add(_MdDiffLine(_MdDiffKind.meta, nextFile));
        }
        continue;
      }
      if (!inHunk && _headers.any(raw.startsWith)) continue;
      if (raw.startsWith('+')) {
        adds++;
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.add, raw.substring(1), newNum: n));
      } else if (raw.startsWith('-')) {
        dels++;
        final n = inHunk ? oldN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.del, raw.substring(1), oldNum: n));
      } else if (raw.startsWith(' ')) {
        final o = inHunk ? oldN++ : null;
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.ctx, raw.substring(1),
            oldNum: o, newNum: n));
      } else {
        final n = inHunk ? newN++ : rawNum++;
        if (n > maxNum) maxNum = n;
        out.add(_MdDiffLine(_MdDiffKind.ctx, raw, newNum: n));
      }
    }
    return (
      file: file,
      lines: out,
      adds: adds,
      dels: dels,
      maxLineNum: maxNum,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final parsed = _parse();
    final all = parsed.lines;
    final canCollapse = all.length > _initialCap + 8;
    final shown =
        canCollapse && !_expanded ? all.take(_initialCap).toList() : all;
    final hiddenCount = all.length - shown.length;
    final gutterW =
        (parsed.maxLineNum.toString().length.clamp(2, 5) * 7.5) + 6.0;
    final label = parsed.file == null || parsed.file!.isEmpty
        ? 'diff'
        : parsed.file!.split('/').last;

    Widget buildRows({required bool wrapped}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in shown) _buildLine(l, gutterW, wrapped: wrapped),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: kMobile
              ? Color.lerp(AppColors.bg, Colors.black, 0.35)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(kMobile ? 14 : R.sm),
          border: Border.all(
            color: kMobile
                ? AppColors.fg1.withValues(alpha: 0.08)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(12, 6, 6, 6)
                  : const EdgeInsets.fromLTRB(12, 7, 6, 7),
              child: Row(children: [
                AppIcon('file-code', size: 13, color: AppColors.fg3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(11.5, color: AppColors.fg2),
                  ),
                ),
                if (parsed.adds > 0) ...[
                  const SizedBox(width: 6),
                  Text('+${parsed.adds}',
                      style: mono(11,
                          weight: FontWeight.w600, color: AppColors.diffAddFg)),
                ],
                if (parsed.dels > 0) ...[
                  const SizedBox(width: 6),
                  Text('-${parsed.dels}',
                      style: mono(11,
                          weight: FontWeight.w600, color: AppColors.diffDelFg)),
                ],
                const SizedBox(width: 6),
                IconBtn(
                  'wrap',
                  size: 28,
                  iconSize: 13,
                  active: _wrap,
                  tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                const SizedBox(width: 2),
                IconBtn(
                  'clipboard',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Copy diff',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    toast(context, 'Diff copied');
                  },
                ),
              ]),
            ),
            Divider(
                height: 1, color: kMobile ? AppColors.line : AppColors.border),
            if (_wrap)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: buildRows(wrapped: true),
              )
            else
              NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: IntrinsicWidth(child: buildRows(wrapped: false)),
                ),
              ),
            if (canCollapse) ...[
              Divider(
                  height: 1,
                  color: kMobile ? AppColors.line : AppColors.border),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(_expanded ? 'chevron-up' : 'chevron-down',
                          size: 13, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        _expanded
                            ? 'Show less'
                            : 'Show $hiddenCount more lines',
                        style: sans(12,
                            weight: FontWeight.w500, color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLine(_MdDiffLine l, double gutterW, {required bool wrapped}) {
    if (l.kind == _MdDiffKind.hunk || l.kind == _MdDiffKind.meta) {
      return Container(
        color: AppColors.surface1.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          l.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(11, height: 1.4, color: AppColors.fg4),
        ),
      );
    }
    final (Color? bg, Color fg, Color numColor, String sign) = switch (l.kind) {
      _MdDiffKind.add => (
          AppColors.diffAddBg,
          AppColors.diffAddFg,
          AppColors.diffAddFg.withValues(alpha: 0.6),
          '+'
        ),
      _MdDiffKind.del => (
          AppColors.diffDelBg,
          AppColors.diffDelFg,
          AppColors.diffDelFg.withValues(alpha: 0.6),
          '-'
        ),
      _ => (null, AppColors.fg2, AppColors.fg4, ' '),
    };
    final numStr = (l.newNum ?? l.oldNum)?.toString() ?? '';
    final textWidget = Text(
      l.text.isEmpty ? ' ' : l.text,
      softWrap: wrapped,
      style: mono(12, height: 1.45, color: fg),
    );
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(6, 1.5, 10, 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterW,
            child: Text(
              numStr,
              textAlign: TextAlign.right,
              style: mono(10.5, height: 1.55, color: numColor),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(
              sign,
              textAlign: TextAlign.center,
              style: mono(12,
                  height: 1.45, weight: FontWeight.w600, color: fg),
            ),
          ),
          if (wrapped) Expanded(child: textWidget) else textWidget,
        ],
      ),
    );
  }
}

class _MdCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  const _MdCodeBlock({required this.code, this.language = ''});

  @override
  State<_MdCodeBlock> createState() => _MdCodeBlockState();
}

class _MdCodeBlockState extends State<_MdCodeBlock> {
  late bool _wrap = const {'md', 'markdown', 'mdx', 'text', 'txt'}
      .contains(widget.language.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lines = widget.code.split('\n');
    final lang =
        widget.language.trim().isEmpty ? 'code' : widget.language.trim();
    final gutterW = (lines.length.toString().length.clamp(2, 5) * 7.5) + 4.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: kMobile
              ? Color.lerp(AppColors.bg, Colors.black, 0.35)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(kMobile ? 14 : R.sm),
          border: kMobile
              ? Border.all(color: AppColors.fg1.withValues(alpha: 0.07))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(14, 6, 6, 6)
                  : const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(children: [
                Text(lang, style: mono(11, color: AppColors.fg3)),
                const Spacer(),
                IconBtn(
                  'wrap',
                  size: 28,
                  iconSize: 13,
                  active: _wrap,
                  tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                const SizedBox(width: 2),
                IconBtn(
                  'clipboard',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    toast(context, 'Copied');
                  },
                ),
              ]),
            ),
            Divider(
                height: 1, color: kMobile ? AppColors.line : AppColors.border),
            if (_wrap)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: gutterW,
                            child: Text(
                              '${i + 1}',
                              textAlign: TextAlign.right,
                              style: mono(11, height: 1.55, color: AppColors.fg4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              highlightedCodeSpan(
                                  lines[i].isEmpty ? ' ' : lines[i],
                                  language: widget.language),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              )
            else
              NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                  child: SelectableText.rich(
                    TextSpan(children: [
                      for (var i = 0; i < lines.length; i++) ...[
                        TextSpan(
                          text: '${i + 1}'.padLeft(3),
                          style: mono(12, height: 1.55, color: AppColors.fg3),
                        ),
                        const TextSpan(text: '  '),
                        highlightedCodeSpan(
                            i == lines.length - 1 ? lines[i] : '${lines[i]}\n',
                            language: widget.language),
                      ],
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
