import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'theme.dart';
import 'widgets.dart';

/// Session-shell view backed by xterm.dart so cursor, wrap, and CSI
/// come from a real emulator instead of the homemade VT parser.
class SessionTermView extends StatefulWidget {
  const SessionTermView({
    super.key,
    required this.alive,
    required this.terminal,
    required this.onInput,
    required this.onResize,
    required this.onClose,
    this.onNew,
    this.mobileKeys = false,
    this.showChrome = true,
  });

  final bool alive;
  final Terminal terminal;
  final ValueChanged<Uint8List> onInput;
  final void Function(int cols, int rows) onResize;
  final VoidCallback onClose;
  final VoidCallback? onNew;
  final bool mobileKeys;
  final bool showChrome;

  @override
  State<SessionTermView> createState() => _SessionTermViewState();
}

class _SessionTermViewState extends State<SessionTermView> {
  final _typeCtrl = TextEditingController();
  final _typeFocus = FocusNode();
  int _lastC = 0;
  int _lastR = 0;

  static final _theme = TerminalTheme(
    cursor: const Color(0xffffffff),
    selection: const Color(0x66ffffff),
    foreground: const Color(0xffe5e5e5),
    background: const Color(0xff0a0a0a),
    black: const Color(0xff000000),
    red: const Color(0xffcd3131),
    green: const Color(0xff0dbc79),
    yellow: const Color(0xffe5e510),
    blue: const Color(0xff2472c8),
    magenta: const Color(0xffbc3fbc),
    cyan: const Color(0xff11a8cd),
    white: const Color(0xffe5e5e5),
    brightBlack: const Color(0xff666666),
    brightRed: const Color(0xfff14c4c),
    brightGreen: const Color(0xff23d18b),
    brightYellow: const Color(0xfff5f543),
    brightBlue: const Color(0xff3b8eea),
    brightMagenta: const Color(0xffd670d6),
    brightCyan: const Color(0xff29b8db),
    brightWhite: const Color(0xffffffff),
    searchHitBackground: const Color(0xffe5e510),
    searchHitBackgroundCurrent: const Color(0xfff5f543),
    searchHitForeground: const Color(0xff000000),
  );

  @override
  void initState() {
    super.initState();
    widget.terminal.onOutput = _onOutput;
    widget.terminal.onResize = _onTermResize;
  }

  @override
  void didUpdateWidget(SessionTermView old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      old.terminal.onOutput = null;
      old.terminal.onResize = null;
      widget.terminal.onOutput = _onOutput;
      widget.terminal.onResize = _onTermResize;
    }
  }

  @override
  void dispose() {
    widget.terminal.onOutput = null;
    widget.terminal.onResize = null;
    _typeCtrl.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  void _onOutput(String data) {
    if (data.isEmpty) return;
    widget.onInput(Uint8List.fromList(utf8.encode(data)));
  }

  void _onTermResize(int w, int h, int pw, int ph) {
    if (w == _lastC && h == _lastR) return;
    _lastC = w;
    _lastR = h;
    widget.onResize(w, h);
  }

  void _flushTyped(String value) {
    if (value.isEmpty) return;
    widget.onInput(Uint8List.fromList(utf8.encode(value)));
    _typeCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (widget.showChrome)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(children: [
            Text(widget.alive ? 'Shell' : 'Shell · starting',
                style: sans(13, weight: FontWeight.w600, color: AppColors.fg1)),
            const Spacer(),
            if (widget.onNew != null)
              IconBtn('plus',
                  size: 28,
                  iconSize: 14,
                  tooltip: 'New shell',
                  onTap: widget.onNew),
            IconBtn('x',
                size: 28,
                iconSize: 14,
                tooltip: 'Close',
                onTap: widget.onClose),
          ]),
        ),
      Expanded(
        child: TerminalView(
          widget.terminal,
          theme: _theme,
          backgroundOpacity: 1,
          autofocus: !widget.mobileKeys,
          readOnly: widget.mobileKeys,
          hardwareKeyboardOnly: widget.mobileKeys,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          textStyle: const TerminalStyle(
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
      ),
      if (widget.mobileKeys) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in const [
              ('Esc', [0x1b]),
              ('Tab', [0x09]),
              ('^C', [0x03]),
              ('^D', [0x04]),
              ('^Z', [0x1a]),
              ('↑', [0x1b, 0x5b, 0x41]),
              ('↓', [0x1b, 0x5b, 0x42]),
              ('←', [0x1b, 0x5b, 0x44]),
              ('→', [0x1b, 0x5b, 0x43]),
            ])
              InkWell(
                onTap: () => widget.onInput(Uint8List.fromList(e.$2)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border2),
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Text(e.$1, style: mono(11, color: AppColors.fg2)),
                ),
              ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              8, 0, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: TextField(
            controller: _typeCtrl,
            focusNode: _typeFocus,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.send,
            style: mono(13, color: AppColors.fg1),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'type…',
              hintStyle: mono(13, color: AppColors.fg4),
              filled: true,
              fillColor: AppColors.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
            onChanged: (v) {
              if (v.isEmpty) return;
              _flushTyped(v);
            },
            onSubmitted: (v) {
              if (v.isNotEmpty) _flushTyped(v);
              widget.onInput(Uint8List.fromList([0x0d]));
              _typeFocus.requestFocus();
            },
          ),
        ),
      ],
    ]);
  }
}
