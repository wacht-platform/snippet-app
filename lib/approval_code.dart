import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'highlight.dart';
import 'theme.dart';

const _heredocLanguages = {
  'python': 'python',
  'python3': 'python',
  'node': 'javascript',
  'bash': 'bash',
  'sh': 'bash',
  'zsh': 'bash',
  'ruby': 'ruby',
  'perl': 'perl',
  'sqlite3': 'sql',
  'psql': 'sql',
};
final _heredoc = RegExp(r"""<<-?\s*['"]?(\w+)['"]?""");

/// Highlights a shell command, and a heredoc's body in the language it feeds.
TextSpan approvalCodeSpan(String code, {required bool shell}) {
  const size = 12.0;
  const height = 1.5;
  TextSpan part(String text, String language) => highlightedCodeSpan(text,
      language: language, fontSize: size, height: height);
  if (!shell) return part(code, '');
  final lines = code.split('\n');
  final open = _heredoc.firstMatch(lines.first);
  final terminator = open == null ? -1 : lines.lastIndexOf(open[1]!);
  if (open == null || terminator < 1) return part(code, 'bash');
  final program = RegExp(r'[\w.-]+').firstMatch(lines.first)?[0] ?? '';
  final language = _heredocLanguages[program] ?? '';
  return TextSpan(children: [
    part(lines.first, 'bash'),
    const TextSpan(text: '\n'),
    if (terminator > 1) ...[
      part(lines.sublist(1, terminator).join('\n'), language),
      const TextSpan(text: '\n'),
    ],
    part(lines.sublist(terminator).join('\n'), 'bash'),
  ]);
}

class ApprovalCode extends StatefulWidget {
  const ApprovalCode({
    super.key,
    required this.code,
    this.shell = true,
    this.collapsedLines = 6,
    this.selectable = true,
  });

  final String code;
  final bool shell;
  final int collapsedLines;
  final bool selectable;

  @override
  State<ApprovalCode> createState() => _ApprovalCodeState();
}

class _ApprovalCodeState extends State<ApprovalCode> {
  var _open = false;
  var _copied = false;

  Widget _link(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(label,
              style: sans(12, weight: W.label, color: AppColors.fg3)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final span = approvalCodeSpan(widget.code, shell: widget.shell);
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: box.maxWidth);
      final lineHeight = MediaQuery.textScalerOf(context).scale(12) * 1.5;
      final limit = lineHeight * widget.collapsedLines;
      final overflows = painter.height > limit + 1;
      painter.dispose();
      final text =
          widget.selectable ? SelectableText.rich(span) : Text.rich(span);
      final code = ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: !overflows
                ? double.infinity
                : _open
                    ? lineHeight * 16
                    : limit),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: text,
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A tight composer must shrink the code, never push the buttons off.
          if (box.hasBoundedHeight) Flexible(child: code) else code,
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Transform.translate(
              offset: const Offset(-4, 0),
              child: Row(children: [
                if (overflows)
                  _link(
                      _open
                          ? 'Show less'
                          : lineCount > 1
                              ? 'Show all $lineCount lines'
                              : 'Show all',
                      () => setState(() => _open = !_open)),
                if (overflows) const SizedBox(width: 8),
                _link(_copied ? 'Copied' : 'Copy', () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  setState(() => _copied = true);
                }),
              ]),
            ),
          ),
        ],
      );
    });
  }
}
