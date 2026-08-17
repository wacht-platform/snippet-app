import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

/// Enough of xterm for bash/vim/htop/less over the daemon PTY.
class VtScreen {
  VtScreen(this.cols, this.rows)
      : cells = List<VtCell>.filled(cols * rows, const VtCell());

  int cols;
  int rows;
  List<VtCell> cells;
  int cx = 0;
  int cy = 0;
  int _savedX = 0;
  int _savedY = 0;
  int fg = 7;
  int bg = 0;
  bool bold = false;
  bool inverse = false;
  int scrollTop = 0;
  late int scrollBot = rows - 1;
  bool alt = false;
  List<VtCell> _main = const [];
  int _mainCx = 0;
  int _mainCy = 0;
  final List<int> _utf8 = [];
  _Esc _esc = _Esc.ground;
  String _csi = '';
  String _osc = '';

  VtCell cell(int x, int y) {
    final i = y * cols + x;
    if (i < 0 || i >= cells.length) return const VtCell();
    return cells[i];
  }

  void resize(int c, int r) {
    c = c.clamp(2, 400);
    r = r.clamp(2, 200);
    if (c == cols && r == rows) return;
    final next = List<VtCell>.filled(c * r, const VtCell());
    final cc = cols < c ? cols : c;
    final rr = rows < r ? rows : r;
    for (var y = 0; y < rr; y++) {
      for (var x = 0; x < cc; x++) {
        next[y * c + x] = cells[y * cols + x];
      }
    }
    cells = next;
    cols = c;
    rows = r;
    scrollBot = rows - 1;
    if (scrollTop > scrollBot) scrollTop = scrollBot;
    if (cx >= cols) cx = cols - 1;
    if (cy >= rows) cy = rows - 1;
  }

  void reset(int c, int r) {
    cols = c.clamp(2, 400);
    rows = r.clamp(2, 200);
    cells = List<VtCell>.filled(cols * rows, const VtCell());
    cx = cy = 0;
    fg = 7;
    bg = 0;
    bold = inverse = alt = false;
    scrollTop = 0;
    scrollBot = rows - 1;
    _esc = _Esc.ground;
    _utf8.clear();
  }

  void feed(Uint8List bytes) {
    for (final b in bytes) {
      _byte(b);
    }
  }

  void _byte(int b) {
    switch (_esc) {
      case _Esc.osc:
        if (b == 0x07 || (b == 0x5c && _osc.endsWith('\x1b'))) {
          _esc = _Esc.ground;
          _osc = '';
        } else {
          _osc += String.fromCharCode(b);
          if (_osc.length > 1024) {
            _esc = _Esc.ground;
            _osc = '';
          }
        }
        return;
      case _Esc.csi:
        if (b >= 0x40 && b <= 0x7e) {
          final p = _csi;
          _csi = '';
          _esc = _Esc.ground;
          _csiCmd(p, String.fromCharCode(b));
        } else {
          _csi += String.fromCharCode(b);
          if (_csi.length > 64) {
            _esc = _Esc.ground;
            _csi = '';
          }
        }
        return;
      case _Esc.esc:
        _esc = _Esc.ground;
        switch (b) {
          case 0x5b:
            _esc = _Esc.csi;
            _csi = '';
            return;
          case 0x5d:
            _esc = _Esc.osc;
            _osc = '';
            return;
          case 0x28:
          case 0x29:
          case 0x2a:
          case 0x2b:
            _esc = _Esc.charset;
            return;
          case 0x37:
            _savedX = cx;
            _savedY = cy;
          case 0x38:
            cx = _savedX.clamp(0, cols - 1);
            cy = _savedY.clamp(0, rows - 1);
          case 0x4d:
            _ri();
          case 0x44:
            _index();
          case 0x45:
            cx = 0;
            _index();
          case 0x63:
            reset(cols, rows);
        }
        return;
      case _Esc.charset:
        _esc = _Esc.ground;
        return;
      case _Esc.ground:
        break;
    }
    if (b == 0x1b) {
      _esc = _Esc.esc;
      return;
    }
    if (b == 0x08) {
      if (cx > 0) cx--;
      return;
    }
    if (b == 0x09) {
      cx = ((cx ~/ 8) + 1) * 8;
      if (cx >= cols) {
        cx = 0;
        _index();
      }
      return;
    }
    if (b == 0x0a || b == 0x0b || b == 0x0c) {
      _index();
      return;
    }
    if (b == 0x0d) {
      cx = 0;
      return;
    }
    if (b == 0x07 || b < 0x20) return;
    _utf8.add(b);
    try {
      final s = utf8.decode(_utf8);
      _put(String.fromCharCode(s.runes.first));
      _utf8.clear();
    } catch (_) {
      if (_utf8.length > 4) _utf8.clear();
    }
  }

  void _put(String ch) {
    if (cx >= cols) {
      cx = 0;
      _index();
    }
    final i = cy * cols + cx;
    if (i >= 0 && i < cells.length) {
      cells[i] = VtCell(ch: ch, fg: fg, bg: bg, bold: bold, inverse: inverse);
    }
    cx++;
  }

  void _index() {
    if (cy == scrollBot) {
      _scrollUp();
    } else if (cy + 1 < rows) {
      cy++;
    }
  }

  void _ri() {
    if (cy == scrollTop) {
      _scrollDown();
    } else if (cy > 0) {
      cy--;
    }
  }

  void _scrollUp() {
    if (scrollBot <= scrollTop) return;
    for (var y = scrollTop; y < scrollBot; y++) {
      for (var x = 0; x < cols; x++) {
        cells[y * cols + x] = cells[(y + 1) * cols + x];
      }
    }
    for (var x = 0; x < cols; x++) {
      cells[scrollBot * cols + x] = const VtCell();
    }
  }

  void _scrollDown() {
    if (scrollBot <= scrollTop) return;
    for (var y = scrollBot; y > scrollTop; y--) {
      for (var x = 0; x < cols; x++) {
        cells[y * cols + x] = cells[(y - 1) * cols + x];
      }
    }
    for (var x = 0; x < cols; x++) {
      cells[scrollTop * cols + x] = const VtCell();
    }
  }

  void _csiCmd(String params, String cmd) {
    final priv = params.startsWith('?');
    final body = params.replaceFirst(RegExp(r'^[?>=]'), '');
    final nums = body.isEmpty
        ? <int>[]
        : body.split(';').map((p) => int.tryParse(p) ?? 0).toList();
    int n(int i, int d) {
      if (i >= nums.length || nums[i] <= 0) return d;
      return nums[i];
    }

    if (priv && (cmd == 'h' || cmd == 'l')) {
      final on = cmd == 'h';
      for (final p in nums) {
        if (p == 1049 || p == 47 || p == 1047) _setAlt(on);
      }
      return;
    }
    switch (cmd) {
      case 'A':
        cy = (cy - n(0, 1)).clamp(0, rows - 1);
      case 'B':
        cy = (cy + n(0, 1)).clamp(0, rows - 1);
      case 'C':
        cx = (cx + n(0, 1)).clamp(0, cols - 1);
      case 'D':
        cx = (cx - n(0, 1)).clamp(0, cols - 1);
      case 'G':
        cx = (n(0, 1) - 1).clamp(0, cols - 1);
      case 'd':
        cy = (n(0, 1) - 1).clamp(0, rows - 1);
      case 'H':
      case 'f':
        cy = (n(0, 1) - 1).clamp(0, rows - 1);
        cx = (n(1, 1) - 1).clamp(0, cols - 1);
      case 'J':
        _ed(nums.isEmpty ? 0 : nums.first);
      case 'K':
        _el(nums.isEmpty ? 0 : nums.first);
      case 'm':
        _sgr(nums);
      case 'r':
        scrollTop = (n(0, 1) - 1).clamp(0, rows - 1);
        scrollBot = (nums.length > 1 ? n(1, 1) - 1 : rows - 1)
            .clamp(scrollTop, rows - 1);
      case 's':
        _savedX = cx;
        _savedY = cy;
      case 'u':
        cx = _savedX.clamp(0, cols - 1);
        cy = _savedY.clamp(0, rows - 1);
      case 'L':
        for (var i = 0; i < n(0, 1); i++) {
          _scrollDown();
        }
      case 'M':
        for (var i = 0; i < n(0, 1); i++) {
          _scrollUp();
        }
    }
  }

  void _setAlt(bool on) {
    if (on == alt) return;
    if (on) {
      _main = List<VtCell>.from(cells);
      _mainCx = cx;
      _mainCy = cy;
      cells = List<VtCell>.filled(cols * rows, const VtCell());
      cx = cy = 0;
      alt = true;
    } else {
      if (_main.length == cells.length) {
        cells = _main;
      } else {
        cells = List<VtCell>.filled(cols * rows, const VtCell());
      }
      cx = _mainCx.clamp(0, cols - 1);
      cy = _mainCy.clamp(0, rows - 1);
      alt = false;
    }
  }

  void _ed(int mode) {
    if (mode == 2 || mode == 3) {
      cells = List<VtCell>.filled(cols * rows, const VtCell());
      if (mode == 2) {
        cx = cy = 0;
      }
      return;
    }
    if (mode == 1) {
      final end = (cy * cols + cx).clamp(0, cells.length);
      for (var i = 0; i < end; i++) {
        cells[i] = const VtCell();
      }
      return;
    }
    for (var i = cy * cols + cx; i < cells.length; i++) {
      cells[i] = const VtCell();
    }
  }

  void _el(int mode) {
    final row = cy * cols;
    if (mode == 1) {
      for (var x = 0; x <= cx && x < cols; x++) {
        cells[row + x] = const VtCell();
      }
    } else if (mode == 2) {
      for (var x = 0; x < cols; x++) {
        cells[row + x] = const VtCell();
      }
    } else {
      for (var x = cx; x < cols; x++) {
        cells[row + x] = const VtCell();
      }
    }
  }

  void _sgr(List<int> nums) {
    if (nums.isEmpty) {
      fg = 7;
      bg = 0;
      bold = inverse = false;
      return;
    }
    for (var i = 0; i < nums.length; i++) {
      final n = nums[i];
      if (n == 0) {
        fg = 7;
        bg = 0;
        bold = inverse = false;
      } else if (n == 1) {
        bold = true;
      } else if (n == 22) {
        bold = false;
      } else if (n == 7) {
        inverse = true;
      } else if (n == 27) {
        inverse = false;
      } else if (n >= 30 && n <= 37) {
        fg = n - 30;
      } else if (n == 39) {
        fg = 7;
      } else if (n >= 40 && n <= 47) {
        bg = n - 40;
      } else if (n == 49) {
        bg = 0;
      } else if (n >= 90 && n <= 97) {
        fg = n - 90 + 8;
      } else if (n >= 100 && n <= 107) {
        bg = n - 100 + 8;
      } else if ((n == 38 || n == 48) &&
          i + 2 < nums.length &&
          nums[i + 1] == 5) {
        final idx = nums[i + 2].clamp(0, 255);
        if (n == 38) {
          fg = idx;
        } else {
          bg = idx;
        }
        i += 2;
      } else if ((n == 38 || n == 48) &&
          i + 4 < nums.length &&
          nums[i + 1] == 2) {
        final idx = _rgb256(nums[i + 2], nums[i + 3], nums[i + 4]);
        if (n == 38) {
          fg = idx;
        } else {
          bg = idx;
        }
        i += 4;
      }
    }
  }
}

int _rgb256(int r, int g, int b) {
  r = r.clamp(0, 255);
  g = g.clamp(0, 255);
  b = b.clamp(0, 255);
  if (r == g && g == b) {
    if (r < 8) return 16;
    if (r > 248) return 231;
    return 232 + ((r - 8) * 24 ~/ 247);
  }
  return 16 + 36 * (r * 5 ~/ 255) + 6 * (g * 5 ~/ 255) + (b * 5 ~/ 255);
}

enum _Esc { ground, esc, csi, osc, charset }

class VtCell {
  const VtCell({
    this.ch = ' ',
    this.fg = 7,
    this.bg = 0,
    this.bold = false,
    this.inverse = false,
  });
  final String ch;
  final int fg;
  final int bg;
  final bool bold;
  final bool inverse;
}

Color ansiColor(int idx) {
  const basic = <int>[
    0x000000,
    0xcd3131,
    0x0dbc79,
    0xe5e510,
    0x2472c8,
    0xbc3fbc,
    0x11a8cd,
    0xe5e5e5,
    0x666666,
    0xf14c4c,
    0x23d18b,
    0xf5f543,
    0x3b8eea,
    0xd670d6,
    0x29b8db,
    0xe5e5e5,
  ];
  if (idx < 16) return Color(0xff000000 | basic[idx]);
  if (idx >= 232) {
    final v = 8 + (idx - 232) * 10;
    return Color.fromARGB(255, v, v, v);
  }
  final n = idx - 16;
  int cube(int i) => i == 0 ? 0 : 55 + i * 40;
  return Color.fromARGB(255, cube(n ~/ 36), cube((n % 36) ~/ 6), cube(n % 6));
}

/// Encode a Flutter key event as PTY bytes (xterm).
Uint8List? encodeTermKey(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final key = event.logicalKey;
  final ctrl = HardwareKeyboard.instance.isControlPressed;
  final alt = HardwareKeyboard.instance.isAltPressed;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return Uint8List.fromList([0x0d]);
  }
  if (key == LogicalKeyboardKey.tab) return Uint8List.fromList([0x09]);
  if (key == LogicalKeyboardKey.backspace) return Uint8List.fromList([0x7f]);
  if (key == LogicalKeyboardKey.delete) {
    return Uint8List.fromList([0x1b, 0x5b, 0x33, 0x7e]);
  }
  if (key == LogicalKeyboardKey.escape) return Uint8List.fromList([0x1b]);
  if (key == LogicalKeyboardKey.arrowUp) {
    return Uint8List.fromList([0x1b, 0x5b, 0x41]);
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return Uint8List.fromList([0x1b, 0x5b, 0x42]);
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return Uint8List.fromList([0x1b, 0x5b, 0x43]);
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return Uint8List.fromList([0x1b, 0x5b, 0x44]);
  }
  if (key == LogicalKeyboardKey.home) {
    return Uint8List.fromList([0x1b, 0x5b, 0x48]);
  }
  if (key == LogicalKeyboardKey.end) {
    return Uint8List.fromList([0x1b, 0x5b, 0x46]);
  }
  if (key == LogicalKeyboardKey.pageUp) {
    return Uint8List.fromList([0x1b, 0x5b, 0x35, 0x7e]);
  }
  if (key == LogicalKeyboardKey.pageDown) {
    return Uint8List.fromList([0x1b, 0x5b, 0x36, 0x7e]);
  }
  final ch = event.character;
  if (ch != null && ch.isNotEmpty) {
    if (ctrl && ch.length == 1) {
      final c = ch.toLowerCase().codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7a) return Uint8List.fromList([c - 0x60]);
    }
    if (alt) {
      return Uint8List.fromList([0x1b, ...utf8.encode(ch)]);
    }
    return Uint8List.fromList(utf8.encode(ch));
  }
  return null;
}

class SessionTermView extends StatefulWidget {
  const SessionTermView({
    super.key,
    required this.alive,
    required this.screen,
    required this.onInput,
    required this.onResize,
    required this.onClose,
    this.onNew,
    this.mobileKeys = false,
  });

  final bool alive;
  final VtScreen screen;
  final ValueChanged<Uint8List> onInput;
  final void Function(int cols, int rows) onResize;
  final VoidCallback onClose;
  final VoidCallback? onNew;
  final bool mobileKeys;

  @override
  State<SessionTermView> createState() => _SessionTermViewState();
}

class _SessionTermViewState extends State<SessionTermView> {
  final _focus = FocusNode();
  int _lastC = 0;
  int _lastR = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
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
              size: 28, iconSize: 14, tooltip: 'Close', onTap: widget.onClose),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          const cw = 8.2;
          const ch = 16.0;
          final cols = (box.maxWidth / cw).floor().clamp(20, 200);
          final rows = (box.maxHeight / ch).floor().clamp(8, 80);
          if (cols != _lastC || rows != _lastR) {
            _lastC = cols;
            _lastR = rows;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.screen.resize(cols, rows);
              widget.onResize(cols, rows);
            });
          }
          return KeyboardListener(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: (e) {
              final b = encodeTermKey(e);
              if (b != null) widget.onInput(b);
            },
            child: GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: ColoredBox(
                color: const Color(0xff0a0a0a),
                child: CustomPaint(
                  painter: _VtPainter(widget.screen),
                  size: Size.infinite,
                ),
              ),
            ),
          );
        }),
      ),
      if (widget.mobileKeys)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in const [
              ('Esc', [0x1b]),
              ('Tab', [0x09]),
              ('Ctrl-C', [0x03]),
              ('Ctrl-D', [0x04]),
              ('Ctrl-Z', [0x1a]),
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
    ]);
  }
}

class _VtPainter extends CustomPainter {
  _VtPainter(this.screen);
  final VtScreen screen;

  @override
  void paint(Canvas canvas, Size size) {
    const cw = 8.2;
    const ch = 16.0;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var y = 0; y < screen.rows; y++) {
      for (var x = 0; x < screen.cols; x++) {
        final cell = screen.cell(x, y);
        var fg = cell.inverse ? cell.bg : cell.fg;
        var bg = cell.inverse ? cell.fg : cell.bg;
        if (x == screen.cx && y == screen.cy) {
          fg = 0;
          bg = 15;
        }
        final rect = Rect.fromLTWH(x * cw, y * ch, cw, ch);
        if (bg != 0 || (x == screen.cx && y == screen.cy)) {
          canvas.drawRect(rect, Paint()..color = ansiColor(bg));
        }
        if (cell.ch.trim().isEmpty && cell.ch != ' ') continue;
        if (cell.ch == ' ') continue;
        tp.text = TextSpan(
          text: cell.ch,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.2,
            fontWeight: cell.bold ? FontWeight.w600 : FontWeight.w400,
            color: ansiColor(fg),
          ),
        );
        tp.layout(maxWidth: cw * 2);
        tp.paint(canvas, Offset(x * cw, y * ch));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VtPainter old) => true;
}
