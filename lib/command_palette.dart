import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

enum PaletteKind {
  recent('Recent'),
  session('This chat'),
  command('Go to'),
  tab('Open tabs'),
  chat('Chats'),
  file('Files'),
  pr('Pull requests'),
  task('Tasks'),
  agent('Agents'),
  artifact('Artifacts'),
  terminal('Terminals'),
  setting('Settings');

  const PaletteKind(this.label);
  final String label;
}

class PaletteItem {
  final String id;
  final PaletteKind kind;
  final String icon;
  final String title;
  final String subtitle;
  final String shortcut;
  final List<String> keywords;
  final VoidCallback run;

  const PaletteItem({
    required this.id,
    required this.kind,
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle = '',
    this.shortcut = '',
    this.keywords = const [],
  });
}

class PaletteSource {
  final PaletteKind kind;
  final Future<List<PaletteItem>> Function() load;
  const PaletteSource(this.kind, this.load);
}

const _prefixes = <String, Set<PaletteKind>>{
  '>': {PaletteKind.session, PaletteKind.command, PaletteKind.setting},
  '@': {PaletteKind.agent},
  '#': {PaletteKind.pr},
  '/': {PaletteKind.file},
};

const _recentKey = 'palette.recent';
const _recentMax = 8;

Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteItem> items,
  List<PaletteSource> sources = const [],
}) {
  Widget body() => _Palette(items: items, sources: sources);
  final view = View.of(context);
  final desktop =
      view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
  if (desktop) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'palette',
      barrierColor: AppColors.scrim,
      transitionDuration: Motion.quick,
      pageBuilder: (ctx, _, __) => Align(
        alignment: const Alignment(0, -0.55),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
            child: _frame(body()),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Motion.enter);
        return FadeTransition(
            opacity: c,
            child: ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(c), child: child));
      },
    );
  }
  return showModalBottomSheet(
    sheetAnimationStyle: sheetMotion,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final mq = MediaQuery.of(context);
      final available = mq.size.height - mq.viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: available * 0.85),
          child: _frame(body()),
        ),
      );
    },
  );
}

Widget _frame(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(R.card),
      child: Material(color: AppColors.glassSurface, child: child),
    );

double? fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  if (text.isEmpty) return null;
  final t = text.toLowerCase();
  final at = t.indexOf(query);
  if (at >= 0) {
    final boundary = at == 0 || _isBoundary(t.codeUnitAt(at - 1));
    return 100 +
        (boundary ? 40 : 0) +
        (at == 0 ? 20 : 0) -
        math.min(at, 30) -
        math.min(t.length - query.length, 40) * 0.25;
  }
  var score = 0.0;
  var ti = 0;
  var last = -2;
  for (var qi = 0; qi < query.length; qi++) {
    final c = query.codeUnitAt(qi);
    var found = -1;
    while (ti < t.length) {
      if (t.codeUnitAt(ti) == c) {
        found = ti;
        ti++;
        break;
      }
      ti++;
    }
    if (found < 0) return null;
    if (found == last + 1) {
      score += 6;
    } else if (found == 0 || _isBoundary(t.codeUnitAt(found - 1))) {
      score += 8;
    } else {
      score += 1;
    }
    last = found;
  }
  return score - math.min(t.length, 60) * 0.1;
}

bool _isBoundary(int c) =>
    c == 0x20 || c == 0x2F || c == 0x2D || c == 0x5F || c == 0x2E || c == 0x3A;

class _Scored {
  final PaletteItem item;
  final double score;
  const _Scored(this.item, this.score);
}

class _Palette extends StatefulWidget {
  final List<PaletteItem> items;
  final List<PaletteSource> sources;
  const _Palette({required this.items, required this.sources});
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  static const _rowHeight = 40.0;
  static const _headerHeight = 28.0;

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final Map<PaletteKind, List<PaletteItem>> _loaded = {};
  final Set<PaletteKind> _loading = {};
  List<String> _recent = const [];
  int _selected = 0;
  List<Object> _rows = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _selected = 0));
    _loadRecent();
    for (final s in widget.sources) {
      _loading.add(s.kind);
      s.load().then((items) {
        if (!mounted) return;
        setState(() {
          _loaded[s.kind] = items;
          _loading.remove(s.kind);
        });
      }, onError: (_) {
        if (mounted) setState(() => _loading.remove(s.kind));
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = p.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = r);
    } catch (_) {}
  }

  Future<void> _remember(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = [
        id,
        ...(p.getStringList(_recentKey) ?? const <String>[])
            .where((e) => e != id),
      ];
      await p.setStringList(_recentKey, r.take(_recentMax).toList());
    } catch (_) {}
  }

  Iterable<PaletteItem> get _all sync* {
    yield* widget.items;
    for (final list in _loaded.values) {
      yield* list;
    }
  }

  (Set<PaletteKind>?, String) get _parsed {
    final raw = _ctrl.text.trimLeft();
    if (raw.isNotEmpty) {
      final kinds = _prefixes[raw[0]];
      if (kinds != null) return (kinds, raw.substring(1).trim().toLowerCase());
    }
    return (null, raw.trim().toLowerCase());
  }

  double? _score(PaletteItem item, List<String> tokens) {
    var total = 0.0;
    for (final tok in tokens) {
      var best = fuzzyScore(tok, item.title);
      final sub = fuzzyScore(tok, item.subtitle);
      if (sub != null && (best == null || sub * 0.6 > best)) best = sub * 0.6;
      for (final k in item.keywords) {
        final ks = fuzzyScore(tok, k);
        if (ks != null && (best == null || ks * 0.8 > best)) best = ks * 0.8;
      }
      if (best == null) return null;
      total += best;
    }
    if (_recent.contains(item.id)) total += 15;
    return total;
  }

  int _capFor(PaletteKind k) => switch (k) {
        PaletteKind.file => 20,
        PaletteKind.chat => 8,
        _ => 10,
      };

  List<Object> _buildRows() {
    final (kinds, q) = _parsed;
    final rows = <Object>[];
    if (q.isEmpty && kinds == null) {
      final byId = {for (final i in _all) i.id: i};
      final recent = [
        for (final id in _recent)
          if (byId[id] != null) byId[id]!,
      ];
      final shown = <String>{};
      void section(PaletteKind label, Iterable<PaletteItem> items, int cap) {
        final list =
            items.where((i) => !shown.contains(i.id)).take(cap).toList();
        if (list.isEmpty) return;
        rows.add(label);
        rows.addAll(list);
        shown.addAll(list.map((e) => e.id));
      }

      Iterable<PaletteItem> of(PaletteKind k) =>
          widget.items.where((i) => i.kind == k);
      section(PaletteKind.recent, recent, _recentMax);
      section(PaletteKind.session, of(PaletteKind.session), 6);
      section(PaletteKind.tab, of(PaletteKind.tab), 6);
      section(PaletteKind.chat, of(PaletteKind.chat), 5);
      section(PaletteKind.command, of(PaletteKind.command), 20);
      return rows;
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final groups = <PaletteKind, List<_Scored>>{};
    for (final item in _all) {
      if (kinds != null && !kinds.contains(item.kind)) continue;
      final s = tokens.isEmpty ? 0.0 : _score(item, tokens);
      if (s == null) continue;
      (groups[item.kind] ??= []).add(_Scored(item, s));
    }
    double best(List<_Scored> l) => l.map((e) => e.score).reduce(math.max);
    final ordered = groups.entries.toList()
      ..sort((a, b) => best(b.value).compareTo(best(a.value)));
    for (final g in ordered) {
      if (tokens.isNotEmpty) {
        g.value.sort((a, b) => b.score.compareTo(a.score));
      }
      rows.add(g.key);
      rows.addAll(g.value.take(_capFor(g.key)).map((e) => e.item));
    }
    return rows;
  }

  List<PaletteItem> get _selectable => _rows.whereType<PaletteItem>().toList();

  void _move(int delta) {
    final n = _selectable.length;
    if (n == 0) return;
    setState(() => _selected = ((_selected + delta) % n + n) % n);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    var y = 0.0;
    var idx = -1;
    for (final r in _rows) {
      if (r is PaletteKind) {
        y += _headerHeight;
        continue;
      }
      idx++;
      if (idx == _selected) break;
      y += _rowHeight;
    }
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    final max = _scroll.position.maxScrollExtent;
    if (y - _headerHeight < off) {
      _scroll.jumpTo(math.max(0, y - _headerHeight).clamp(0, max).toDouble());
    } else if (y + _rowHeight + 6 > off + view) {
      _scroll.jumpTo((y + _rowHeight + 6 - view).clamp(0, max).toDouble());
    }
  }

  void _run(PaletteItem item) {
    _remember(item.id);
    Navigator.pop(context);
    item.run();
  }

  void _runSelected() {
    final list = _selectable;
    if (list.isEmpty) return;
    _run(list[_selected.clamp(0, list.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    _rows = _buildRows();
    final selectable = _selectable;
    if (_selected >= selectable.length) _selected = 0;
    final (kinds, q) = _parsed;
    final busy = _loading.isNotEmpty && (q.isNotEmpty || kinds != null);
    var index = -1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _move(1),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _runSelected,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _runSelected,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(children: [
            AppIcon('search', size: 17, color: AppColors.fg3),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                cursorColor: AppColors.accent,
                style: sans(kMobile ? 15 : 16, color: AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search or jump to anything',
                  hintStyle: sans(kMobile ? 15 : 16, color: AppColors.fg4),
                ),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: DelayedSpinner(size: 12),
              ),
          ]),
        ),
        Flexible(
          child: selectable.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Center(
                      heightFactor: 1,
                      child: Text(busy ? 'Searching…' : 'No matches',
                          style: TS.meta())),
                )
              : ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  children: [
                    for (final r in _rows)
                      if (r is PaletteKind)
                        _header(r)
                      else
                        _row(r as PaletteItem, ++index),
                  ],
                ),
        ),
        if (!kMobile) _footer(),
      ]),
    );
  }

  Widget _header(PaletteKind k) => SizedBox(
        height: _headerHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
          child: Text(k.label.toUpperCase(),
              style: sans(11, spacing: 0.9, color: AppColors.fg4)),
        ),
      );

  Widget _row(PaletteItem item, int i) {
    final selected = i == _selected;
    return MouseRegion(
      onHover: (_) {
        if (_selected != i) setState(() => _selected = i);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _run(item),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            AppIcon(item.icon,
                size: 15, color: selected ? AppColors.fg1 : AppColors.fg3),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: item.title, style: sans(13, color: AppColors.fg1)),
                  if (item.subtitle.isNotEmpty)
                    TextSpan(
                        text: '   ${item.subtitle}',
                        style: sans(12, color: AppColors.fg4)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.shortcut.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child:
                    Text(item.shortcut, style: mono(11, color: AppColors.fg4)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _footer() {
    Widget hint(String k, String label, {bool last = false}) => Padding(
          padding: EdgeInsets.only(right: last ? 0 : 14),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: k, style: mono(11, color: AppColors.fg2)),
            TextSpan(text: ' $label', style: sans(11, color: AppColors.fg4)),
          ])),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(children: [
        hint('↑↓', 'move'),
        hint('enter', 'open'),
        hint('esc', 'close'),
        const Spacer(),
        hint('>', 'commands'),
        hint('@', 'agents'),
        hint('#', 'PRs'),
        hint('/', 'files', last: true),
      ]),
    );
  }
}
