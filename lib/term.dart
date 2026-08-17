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
  final _termView = GlobalKey<TerminalViewState>();
  int _lastC = 0;
  int _lastR = 0;
  bool _ctrl = false;
  bool _alt = false;

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

  void _sendBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    widget.onInput(Uint8List.fromList(bytes));
  }

  void _sendKey(TerminalKey key, {bool ctrl = false, bool alt = false}) {
    widget.terminal.keyInput(key, ctrl: ctrl || _ctrl, alt: alt || _alt);
    if (_ctrl || _alt) setState(() => _ctrl = _alt = false);
    _termView.currentState?.requestKeyboard();
  }

  void _sendCtrlLetter(String letter) {
    final c = letter.toLowerCase().codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7a) {
      widget.terminal.charInput(c, ctrl: true, alt: _alt);
    }
    if (_ctrl || _alt) setState(() => _ctrl = _alt = false);
    _termView.currentState?.requestKeyboard();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_ctrl && !_alt) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      final unit = ch.runes.first;
      widget.terminal.charInput(unit, ctrl: _ctrl, alt: _alt);
      setState(() => _ctrl = _alt = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _modChip(String label, bool on, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.accent.withValues(alpha: 0.18) : null,
          border: Border.all(color: on ? AppColors.accent : AppColors.border2),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(label,
            style: mono(11, color: on ? AppColors.accent : AppColors.fg2)),
      ),
    );
  }

  Widget _keyChip(String label, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border2),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(label, style: mono(11, color: AppColors.fg2)),
      ),
    );
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
          key: _termView,
          theme: _theme,
          backgroundOpacity: 1,
          autofocus: true,
          readOnly: false,
          hardwareKeyboardOnly: false,
          deleteDetection: widget.mobileKeys,
          keyboardType: TextInputType.visiblePassword,
          onKeyEvent: widget.mobileKeys ? _onKeyEvent : null,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          textStyle: const TerminalStyle(
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
      ),
      if (widget.mobileKeys)
        Padding(
          padding: EdgeInsets.fromLTRB(
              8, 4, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            _modChip('Ctrl', _ctrl, () => setState(() => _ctrl = !_ctrl)),
            _modChip('Alt', _alt, () => setState(() => _alt = !_alt)),
            _keyChip('Esc', () => _sendKey(TerminalKey.escape)),
            _keyChip('Tab', () => _sendKey(TerminalKey.tab)),
            _keyChip('⌫', () => _sendBytes(const [0x7f])),
            _keyChip('^C', () => _sendCtrlLetter('c')),
            _keyChip('^D', () => _sendCtrlLetter('d')),
            _keyChip('^Z', () => _sendCtrlLetter('z')),
            _keyChip('^L', () => _sendCtrlLetter('l')),
            _keyChip('^W', () => _sendCtrlLetter('w')),
            _keyChip('^U', () => _sendCtrlLetter('u')),
            _keyChip('^A', () => _sendCtrlLetter('a')),
            _keyChip('^E', () => _sendCtrlLetter('e')),
            _keyChip('^K', () => _sendCtrlLetter('k')),
            _keyChip('^R', () => _sendCtrlLetter('r')),
            _keyChip('↑', () => _sendKey(TerminalKey.arrowUp)),
            _keyChip('↓', () => _sendKey(TerminalKey.arrowDown)),
            _keyChip('←', () => _sendKey(TerminalKey.arrowLeft)),
            _keyChip('→', () => _sendKey(TerminalKey.arrowRight)),
            _keyChip('Home', () => _sendKey(TerminalKey.home)),
            _keyChip('End', () => _sendKey(TerminalKey.end)),
          ]),
        ),
    ]);
  }
}
