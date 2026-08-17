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
  late Terminal _host;
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
    _host = widget.terminal;
    _bind(_host);
  }

  @override
  void didUpdateWidget(SessionTermView old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      _unbind(old.terminal);
      _host = widget.terminal;
      _bind(_host);
    }
  }

  @override
  void dispose() {
    _unbind(_host);
    super.dispose();
  }

  void _bind(Terminal t) {
    t.onOutput = _onOutput;
    t.onResize = _onTermResize;
  }

  void _unbind(Terminal t) {
    t.onOutput = null;
    t.onResize = null;
  }

  void _onOutput(String data) {
    if (data.isEmpty) return;
    var out = data;
    if (widget.mobileKeys && (_ctrl || _alt) && _isPrintableInsert(data)) {
      out = _applyStickyMods(data);
      setState(() => _ctrl = _alt = false);
    }
    if (out.isEmpty) return;
    widget.onInput(Uint8List.fromList(utf8.encode(out)));
  }

  bool _isPrintableInsert(String data) {
    if (data.isEmpty) return false;
    for (final u in data.runes) {
      if (u < 0x20 || u == 0x7f) return false;
    }
    return true;
  }

  String _applyStickyMods(String data) {
    final buf = StringBuffer();
    for (final u in data.runes) {
      var code = u;
      if (_ctrl) {
        final lower = code >= 0x41 && code <= 0x5a ? code + 32 : code;
        if (lower >= 0x61 && lower <= 0x7a) {
          code = lower - 0x60;
        } else if (code >= 0x40 && code <= 0x5f) {
          code = code & 0x1f;
        }
      }
      if (_alt) buf.writeCharCode(0x1b);
      buf.writeCharCode(code);
    }
    return buf.toString();
  }

  void _onTermResize(int w, int h, int pw, int ph) {
    if (w == _lastC && h == _lastR) return;
    _lastC = w;
    _lastR = h;
    widget.onResize(w, h);
  }

  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(key, ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt) setState(() => _ctrl = _alt = false);
    _termView.currentState?.requestKeyboard();
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

  Widget _keyChip(String label, VoidCallback tap, {double minWidth = 0}) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: 32),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border2),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(label, style: mono(11, color: AppColors.fg2)),
      ),
    );
  }

  Widget _arrowPad() {
    Widget row(List<Widget> kids) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < kids.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              kids[i],
            ],
          ],
        );
    const w = 36.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          _keyChip('↑', () => _sendKey(TerminalKey.arrowUp), minWidth: w),
        ]),
        const SizedBox(height: 4),
        row([
          _keyChip('←', () => _sendKey(TerminalKey.arrowLeft), minWidth: w),
          _keyChip('↓', () => _sendKey(TerminalKey.arrowDown), minWidth: w),
          _keyChip('→', () => _sendKey(TerminalKey.arrowRight), minWidth: w),
        ]),
      ],
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _modChip(
                          'Ctrl', _ctrl, () => setState(() => _ctrl = !_ctrl)),
                      const SizedBox(width: 6),
                      _modChip('Alt', _alt, () => setState(() => _alt = !_alt)),
                      const SizedBox(width: 6),
                      _keyChip('Esc', () => _sendKey(TerminalKey.escape)),
                      const SizedBox(width: 6),
                      _keyChip('Tab', () => _sendKey(TerminalKey.tab)),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _keyChip('Home', () => _sendKey(TerminalKey.home)),
                      _keyChip('End', () => _sendKey(TerminalKey.end)),
                      _keyChip('PgUp', () => _sendKey(TerminalKey.pageUp)),
                      _keyChip('PgDn', () => _sendKey(TerminalKey.pageDown)),
                      _keyChip('Ins', () => _sendKey(TerminalKey.insert)),
                      _keyChip('Del', () => _sendKey(TerminalKey.delete)),
                      _keyChip('F1', () => _sendKey(TerminalKey.f1)),
                      _keyChip('F2', () => _sendKey(TerminalKey.f2)),
                      _keyChip('F5', () => _sendKey(TerminalKey.f5)),
                      _keyChip('F10', () => _sendKey(TerminalKey.f10)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _arrowPad(),
            ],
          ),
        ),
    ]);
  }
}
