import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'memory_screen.dart' show memoryMarkdown;

class _Entry {
  _Entry({required this.text, this.file, this.added});
  final String text;
  final String? file;
  final String? added;
}

List<_Entry> _parse(String md) {
  final out = <_Entry>[];
  final link = RegExp(r'^\[\[([^\]]+)\]\]\s*[—–-]?\s*(.*)$');
  final meta = RegExp(r'\s*\[(?:source|added)[^\]\n]*\]');
  final added = RegExp(r'added: (\d{4}-\d{2}-\d{2})');
  for (final raw in md.split('\n')) {
    final l = raw.trim();
    if (!l.startsWith('- ')) continue;
    final body = l.substring(2).trim();
    final m = link.firstMatch(body);
    if (m != null) {
      out.add(_Entry(text: m[2]!.trim(), file: m[1]!.trim()));
      continue;
    }
    out.add(_Entry(
        text: body.replaceAll(meta, '').trim(),
        added: added.firstMatch(body)?[1]));
  }
  return out;
}

String _day(String? ymd) {
  final d = ymd == null ? null : DateTime.tryParse(ymd);
  if (d == null) return '';
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return '${m[d.month - 1]} ${d.day}';
}

class DeskMemoryView extends StatefulWidget {
  const DeskMemoryView({
    super.key,
    required this.client,
    required this.sessionId,
    this.workspace,
  });

  final DaemonClient client;
  final String sessionId;
  final String? workspace;

  @override
  State<DeskMemoryView> createState() => _DeskMemoryViewState();
}

class _DeskMemoryViewState extends State<DeskMemoryView> {
  final _search = TextEditingController();
  List<MemoryScope> _scopes = const [];
  String _scope = '';
  bool _history = false;
  final Map<String, List<_Entry>> _entries = {};
  final Map<String, List<MemoryCommit>> _commits = {};
  _Entry? _selected;
  String? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await widget.client.memoryScopes();
      if (mounted) setState(() => _scopes = s);
    } catch (_) {}
    if (!mounted) return;
    final key = _projectKey ?? _globalKey;
    if (key == null) {
      setState(() => _loading = false);
      return;
    }
    _scope = key;
    await _load(_scope);
  }

  String? get _projectKey {
    final parts = (widget.workspace ?? '')
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList()
        .reversed;
    for (final name in parts) {
      final hit = _scopes
          .where((s) => s.kind == 'project' && s.label == name)
          .firstOrNull;
      if (hit != null) return hit.key;
    }
    return null;
  }

  String? get _globalKey =>
      _scopes.where((s) => s.kind == 'global').firstOrNull?.key;

  Future<void> _load(String key) async {
    setState(() => _loading = !_entries.containsKey(key));
    try {
      final f = await widget.client.memoryFile(key);
      if (mounted) setState(() => _entries[key] = _parse(f.content));
    } catch (_) {
      if (mounted) setState(() => _entries[key] = const []);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadHistory() async {
    if (_commits.containsKey(_scope)) return;
    try {
      final h = await widget.client.memoryHistory(_scope);
      if (mounted) setState(() => _commits[_scope] = h);
    } catch (_) {
      if (mounted) setState(() => _commits[_scope] = const []);
    }
  }

  Future<void> _select(_Entry e) async {
    setState(() {
      _selected = e;
      _detail = null;
    });
    final f = e.file;
    if (f == null) return;
    try {
      final r = await widget.client
          .memoryFile(_scope, path: f.contains('.') ? f : '$f.md');
      if (mounted && _selected == e) setState(() => _detail = r.content);
    } catch (_) {
      if (mounted && _selected == e) setState(() => _detail = '');
    }
  }

  void _pick(String key) {
    setState(() {
      _scope = key;
      _history = false;
      _selected = null;
    });
    _load(key);
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: on ? AppColors.surface2 : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
              side:
                  BorderSide(color: on ? Colors.transparent : AppColors.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
            onTap: tap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(label,
                  style: sans(12, color: on ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );

  Widget _searchField() => Container(
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          AppIcon('search', size: 13, color: AppColors.fg4),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              style: sans(12.5, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search memory',
                hintStyle: sans(12.5, color: AppColors.fg4),
              ),
            ),
          ),
        ]),
      );

  Widget _card(_Entry e, {required bool wide}) {
    final sel = wide && identical(_selected, e);
    final when = _day(e.added);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? AppColors.surface2 : AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: sel ? Colors.transparent : AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _select(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (e.file != null || when.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(children: [
                        if (e.file != null)
                          Expanded(
                            child: Text(e.file!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(11.5, color: AppColors.fg2)),
                          )
                        else
                          const Spacer(),
                        if (when.isNotEmpty)
                          Text(when, style: sans(11, color: AppColors.fg4)),
                        if (e.file != null)
                          AppIcon('chevron-right',
                              size: 12, color: AppColors.fg4),
                      ]),
                    ),
                  Text(e.text,
                      maxLines: wide ? 3 : 6,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, height: 1.5, color: AppColors.fg3)),
                ]),
          ),
        ),
      ),
    );
  }

  String _match(_Entry e) => e.file != null
      ? '[[${e.file}]]'
      : (e.text.length > 80 ? e.text.substring(0, 80) : e.text);

  Future<void> _forget(_Entry e) async {
    final ok = await confirmAction(context,
        title: 'Forget this?',
        body: e.file != null
            ? 'Removes ${e.file} from the memory index. The file itself stays.'
            : e.text,
        confirmLabel: 'Forget');
    if (!ok) return;
    try {
      await widget.client.editMemoryEntry(_scope, _match(e));
      setState(() => _selected = null);
      await _load(_scope);
    } catch (err) {
      if (mounted) toast(context, '$err', danger: true);
    }
  }

  Future<void> _edit(_Entry e) async {
    final next = await promptText(context,
        title: 'Edit memory', initial: e.text, minLines: 3, maxLines: 8);
    if (next == null || next.trim().isEmpty || next.trim() == e.text) return;
    try {
      await widget.client.editMemoryEntry(_scope, _match(e),
          entry: next.trim().replaceAll(RegExp(r'\s*\n\s*'), ' '));
      setState(() => _selected = null);
      await _load(_scope);
    } catch (err) {
      if (mounted) toast(context, '$err', danger: true);
    }
  }

  Widget _action(String label, VoidCallback onTap, {bool danger = false}) =>
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: danger ? Colors.transparent : AppColors.surface2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
              side: BorderSide(
                  color: danger
                      ? AppColors.danger.withValues(alpha: 0.3)
                      : Colors.transparent)),
          child: InkWell(
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
            onTap: onTap,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(label,
                  style: sans(12,
                      color: danger ? AppColors.danger : AppColors.fg2)),
            ),
          ),
        ),
      );

  Widget _detailView({bool wide = true}) {
    final e = _selected;
    if (e == null) {
      return Center(
        child: Text('Pick an entry to read it in full.',
            style: sans(13, color: AppColors.fg4)),
      );
    }
    final body = e.file == null ? e.text : _detail;
    return SelectionArea(
      child: ListView(
        padding: wide
            ? const EdgeInsets.fromLTRB(40, 28, 40, 40)
            : const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child:
                  Text(e.file ?? 'Note', style: mono(13, color: AppColors.fg1)),
            ),
            if (_day(e.added).isNotEmpty)
              Text('Added ${_day(e.added)}',
                  style: sans(12, color: AppColors.fg4)),
            if (e.file == null) _action('Edit', () => _edit(e)),
            _action('Forget', () => _forget(e), danger: true),
          ]),
          const SizedBox(height: 16),
          if (body == null)
            const Align(
                alignment: Alignment.centerLeft, child: Spinner(size: 14))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: MarkdownBody(
                data: memoryMarkdown(body),
                styleSheet: documentMarkdownStyle(context)
                    .copyWith(em: sans(12, color: AppColors.fg4)),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (_, href, __) => openMarkdownLink(href, context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyList() {
    final h = _commits[_scope];
    if (h == null) return const Center(child: Spinner(size: 16));
    if (h.isEmpty) {
      return Center(
          child:
              Text('No history yet.', style: sans(13, color: AppColors.fg4)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        for (final c in h)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.isConsolidation ? AppColors.accent : AppColors.fg4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    c.isConsolidation
                        ? c.subject.substring('Consolidate:'.length).trim()
                        : c.subject,
                    style: sans(12.5, height: 1.45, color: AppColors.fg2)),
              ),
              const SizedBox(width: 8),
              Text(relativeTime(c.date),
                  style: sans(11, color: AppColors.fg4, tabular: true)),
            ]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = _entries[_scope] ?? const <_Entry>[];
    final shown = [
      for (final e in all)
        if (q.isEmpty ||
            e.text.toLowerCase().contains(q) ||
            (e.file ?? '').toLowerCase().contains(q))
          e
    ];
    final project = _projectKey;
    final global = _globalKey;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 640;
      final list =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(children: [
              Expanded(
                child: Text('Memory',
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
              Text('${all.length} entries',
                  style: sans(12, color: AppColors.fg4)),
            ]),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, wide ? 0 : 2, 14, 8),
          child: _searchField(),
        ),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              if (project != null)
                _chip('Project', _scope == project && !_history,
                    () => _pick(project)),
              if (global != null)
                _chip('Global', _scope == global && !_history,
                    () => _pick(global)),
              _chip('History', _history, () {
                setState(() => _history = true);
                _loadHistory();
              }),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _history
              ? _historyList()
              : _loading
                  ? const Center(child: Spinner(size: 16))
                  : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              q.isEmpty
                                  ? 'Nothing remembered here yet. Agents save decisions and progress as they work.'
                                  : 'No entries match.',
                              textAlign: TextAlign.center,
                              style: sans(12.5,
                                  height: 1.5, color: AppColors.fg4)),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                          children: [
                            for (final e in shown) _card(e, wide: wide)
                          ],
                        ),
        ),
        if (!_history)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text('Saved by agents while they work.',
                style: sans(11.5, color: AppColors.fg4)),
          ),
      ]);
      if (!wide) {
        final e = _selected;
        if (e != null) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _selected = null),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.fg3,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: AppIcon('chevron-left',
                          size: 14, color: AppColors.fg3),
                      label: Text('Memory',
                          style: sans(12.5, color: AppColors.fg3)),
                    ),
                  ),
                ),
                Expanded(child: _detailView(wide: false)),
              ]);
        }
        return list;
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 380, child: list),
        Container(width: 1, color: AppColors.line),
        Expanded(child: _detailView()),
      ]);
    });
  }
}
