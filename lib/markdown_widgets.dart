import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'highlight.dart';
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
      data: text,
      selectable: false,
      styleSheet: thinkingMarkdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href),
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
    t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^\s*([-*+]|\d+\.)\s+', multiLine: true), '• ');
    t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!);
    t = t.replaceAllMapped(
        RegExp(r'(?<![\w*])[*_]([^*_\n]+)[*_](?![\w*])'), (m) => m.group(1)!);
    t = t.replaceAll('`', '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
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
    return _MdCodeBlock(code: code, language: lang);
  }
}

class _MdCodeBlock extends StatelessWidget {
  final String code;
  final String language;
  const _MdCodeBlock({required this.code, this.language = ''});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final lines = code.split('\n');
    final lang = language.trim().isEmpty ? 'code' : language.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(children: [
                Text(lang, style: mono(11, color: AppColors.fg3)),
                const Spacer(),
                IconBtn(
                  'clipboard',
                  size: 28,
                  iconSize: 13,
                  tooltip: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    toast(context, 'Copied');
                  },
                ),
              ]),
            ),
            Divider(height: 1, color: AppColors.border),
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
                          language: language),
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

