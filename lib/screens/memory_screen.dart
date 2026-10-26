import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../motion.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../theme.dart';
import '../desktop_layout.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// What agents remember: one git repo per scope (you, each project, each
/// agent, each session). Read-only here; agents write it and consolidation keeps
/// it tidy on its own.
class MemoryScreen extends StatefulWidget {
  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  /// Open straight into one scope (`agent:<id>`, `session:<id>`, …).
  final String? initialKey;

  const MemoryScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
    this.initialKey,
  });

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryScope>? _scopes;
  String? _error;
  String? _open;
  bool _allSessions = false;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _scopes = widget.client.cachedMemoryScopes();
    _open = widget.initialKey;
    _load();
  }

  Future<void> _load() async {
    try {
      final scopes = await widget.client.memoryScopes();
      if (mounted) {
        setState(() {
          _scopes = scopes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Phones push the scope as its own screen so the system back button
  /// returns to this list instead of leaving Memory altogether.
  void _openScopeKey(String key) {
    if (!kMobile) {
      setState(() => _open = key);
      return;
    }
    final scope = _scopes?.where((s) => s.key == key).firstOrNull;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            backgroundColor: AppColors.bg,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NavBackRow(
                      title: scopeTitle(scope, key),
                      onBack: () => Navigator.of(ctx).maybePop()),
                  Expanded(
                    child: _ScopeView(
                        client: widget.client, scopeKey: key, scope: scope),
                  ),
                ],
              ),
            ),
          ),
        ))
        .then((_) => _load());
  }

  MemoryScope? get _openScope =>
      _scopes?.where((s) => s.key == _open).firstOrNull;

  void _close() {
    if (_open != null && widget.initialKey == null) {
      setState(() => _open = null);
      _load();
    } else {
      (widget.onBack ?? () => Navigator.pop(context))();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile &&
        widget.embedded &&
        widget.initialKey == null &&
        widget.onBack == null) {
      return _DeskMemory(
        client: widget.client,
        scopes: _scopes,
        error: _error,
        allSessions: _allSessions,
        onShowAll: () => setState(() => _allSessions = true),
      );
    }
    final open = _open;
    final scope = _openScope;
    final title = open == null ? 'Memory' : scopeTitle(scope, open);
    final body = Swap(
      stateKey: open ?? 'list',
      fill: true,
      child: open == null
          ? _list()
          : _ScopeView(
              key: ValueKey(open),
              client: widget.client,
              scopeKey: open,
              scope: scope,
            ),
    );
    final back = open != null || widget.onBack != null || !widget.embedded;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (back)
          NavBackRow(title: title, onBack: _close)
        else if (!widget.embedded)
          const SizedBox.shrink(),
        Expanded(child: body),
      ],
    );
    if (widget.embedded) {
      final page = widget.initialKey != null;
      return Material(
        color: page ? AppColors.bg : Colors.transparent,
        child: page ? SafeArea(bottom: false, child: content) : content,
      );
    }
    return Scaffold(body: SafeArea(bottom: false, child: content));
  }

  Widget _list() {
    final scopes = _scopes;
    if (scopes == null) {
      return Center(
        child: _error == null
            ? const Spinner(size: 20)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center, style: TS.meta()),
              ),
      );
    }
    _shownAt ??= DateTime.now();
    final global = scopes.where((s) => s.kind == 'global').toList();
    final projects = scopes.where((s) => s.kind == 'project').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final agents = scopes.where((s) => s.kind == 'agent').toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final sessions = scopes.where((s) => s.kind == 'session').toList()
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final shownSessions = _allSessions ? sessions : sessions.take(5).toList();
    var index = 0;
    Widget group(String label, List<MemoryScope> items, {Widget? footer}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Appear(
        index: index++,
        since: _shownAt,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label.isNotEmpty) SectionHeader(label),
              ListGroup(children: [
                for (final s in items)
                  ListRow(
                    title: scopeTitle(s, s.key),
                    subtitle: scopeStatus(s),
                    leading: IconTile(scopeIcon(s.kind)),
                    trailing: AppIcon('chevron-right',
                        size: 15, color: AppColors.fg4),
                    onTap: () => _openScopeKey(s.key),
                  ),
                if (footer != null) footer,
              ]),
            ],
          ),
        ),
      );
    }

    return PullToRefresh(
      onRefresh: _load,
      child: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
                'What your agents remember, kept as files in git. Agents write it as they work, and it is consolidated in the background.',
                style: sans(13, height: 19 / 13, color: AppColors.fg3)),
          ),
          group('', global),
          group('Projects', projects),
          group('Agents', agents),
          group(
            'Sessions',
            shownSessions,
            footer: sessions.length > 5 && !_allSessions
                ? ListRow(
                    title: 'Show all ${sessions.length}',
                    titleWidget: Text('Show all ${sessions.length}',
                        style: sans(14, color: AppColors.accent)),
                    onTap: () => setState(() => _allSessions = true),
                  )
                : null,
          ),
          if (scopes.isEmpty)
            const EmptyState(
              icon: 'brain',
              title: 'Nothing remembered yet',
              body: 'Memory fills in as agents work.',
            ),
        ],
      ),
    );
  }
}

class _DeskMemory extends StatefulWidget {
  const _DeskMemory({
    required this.client,
    required this.scopes,
    required this.error,
    required this.allSessions,
    required this.onShowAll,
  });

  final DaemonClient client;
  final List<MemoryScope>? scopes;
  final String? error;
  final bool allSessions;
  final VoidCallback onShowAll;

  @override
  State<_DeskMemory> createState() => _DeskMemoryState();
}

class _DeskMemoryState extends State<_DeskMemory> {
  String? _key;
  String _path = 'MEMORY.md';
  String? _content;
  List<String> _files = const [];
  String? _error;
  bool _history = false;
  List<MemoryCommit>? _commits;

  @override
  void initState() {
    super.initState();
    _autoSelect();
  }

  @override
  void didUpdateWidget(covariant _DeskMemory old) {
    super.didUpdateWidget(old);
    _autoSelect();
  }

  void _autoSelect() {
    final scopes = widget.scopes;
    if (_key != null || scopes == null || scopes.isEmpty) return;
    final first = scopes.where((s) => s.kind == 'global').firstOrNull ??
        scopes.first;
    _key = first.key;
    _loadFile();
  }

  void _select(String key) {
    if (key == _key) return;
    setState(() {
      _key = key;
      _path = 'MEMORY.md';
      _history = false;
      _commits = null;
      _files = const [];
    });
    _loadFile();
  }

  void _openPath(String path) {
    final file = path.contains('.') ? path : '$path.md';
    setState(() {
      _path = file;
      _history = false;
    });
    _loadFile();
  }

  Future<void> _loadFile() async {
    final key = _key;
    final path = _path;
    if (key == null) return;
    setState(() {
      _content = null;
      _error = null;
    });
    try {
      final f = await widget.client.memoryFile(key, path: path);
      if (!mounted || _key != key || _path != path) return;
      setState(() {
        _content = f.content;
        _files = f.files;
      });
    } catch (e) {
      if (mounted && _key == key && _path == path) {
        setState(() => _error = '$e');
      }
    }
  }

  Future<void> _toggleHistory() async {
    final key = _key;
    if (key == null) return;
    setState(() => _history = !_history);
    if (!_history || _commits != null) return;
    try {
      final h = await widget.client.memoryHistory(key);
      if (mounted && _key == key) setState(() => _commits = h);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopes = widget.scopes;
    if (scopes == null) {
      return Center(
        child: widget.error == null
            ? const Spinner(size: 20)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.error!,
                    textAlign: TextAlign.center, style: TS.meta()),
              ),
      );
    }
    final scope = scopes.where((s) => s.key == _key).firstOrNull;
    return Material(
      color: Colors.transparent,
      child: MasterDetail(
        master: _master(scopes),
        detail: scope == null
            ? const DetailEmpty('Select a memory to read it.')
            : _detail(scope),
      ),
    );
  }

  Widget _master(List<MemoryScope> scopes) {
    List<MemoryScope> of(String kind) => scopes.where((s) => s.kind == kind).toList();
    final projects = of('project')
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final agents = of('agent')..sort((a, b) => a.label.compareTo(b.label));
    final sessions = of('session')
      ..sort((a, b) => (b.lastCommitAt ?? 0).compareTo(a.lastCommitAt ?? 0));
    final shown = widget.allSessions ? sessions : sessions.take(5).toList();

    List<Widget> group(String label, List<MemoryScope> items) {
      if (items.isEmpty) return const [];
      return [
        if (label.isNotEmpty)
          SectionHeader(label,
              padding: const EdgeInsets.fromLTRB(S.s12, S.s16, S.s12, S.s4)),
        for (final s in items) ...[
          ListRow(
            title: scopeTitle(s, s.key),
            subtitle: scopeStatus(s),
            leading: IconTile(scopeIcon(s.kind)),
            selected: s.key == _key && _path == 'MEMORY.md',
            onTap: () {
              _select(s.key);
              if (_path != 'MEMORY.md') _openPath('MEMORY.md');
            },
          ),
          if (s.key == _key)
            for (final f in _files)
              if (f != 'MEMORY.md')
                Padding(
                  padding: const EdgeInsets.only(left: S.s16),
                  child: ListRow(
                  title: f,
                  titleWidget: Text(f,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12.5, color: AppColors.fg2)),
                  selected: _path == f,
                  onTap: () => _openPath(f),
                  ),
                ),
        ],
      ];
    }

    return MasterPane(
      title: 'Memory',
      empty: const EmptyState(
        icon: 'brain',
        title: 'Nothing remembered yet',
        body: 'Memory fills in as agents work.',
      ),
      children: [
        ...group('', of('global')),
        ...group('Projects', projects),
        ...group('Agents', agents),
        ...group('Sessions', shown),
        if (sessions.length > 5 && !widget.allSessions)
          ListRow(
            title: 'Show all ${sessions.length}',
            titleWidget: Text('Show all ${sessions.length}',
                style: sans(13, color: AppColors.accent)),
            onTap: widget.onShowAll,
          ),
      ],
    );
  }

  Widget _detail(MemoryScope scope) {
    return DetailPane(
      key: ValueKey('${scope.key}:$_path:$_history'),
      title: scopeTitle(scope, scope.key),
      subtitle: scopeStatus(scope),
      actions: [
        Btn(_history ? 'Memory' : 'History',
            variant: BtnVariant.surface,
            small: true,
            icon: _history ? 'brain' : 'git-commit',
            onTap: _toggleHistory),
      ],
      child: _history ? _historyBody() : _fileBody(scope),
    );
  }

  Widget _fileBody(MemoryScope scope) {
    final content = _content;
    if (content == null) {
      return SizedBox(
        height: 240,
        child: Center(
          child: _error == null
              ? const Spinner(size: 20)
              : const EmptyState(
                  icon: 'brain',
                  title: 'Nothing remembered yet',
                  body: 'This memory fills in as work happens here.',
                ),
        ),
      );
    }
    final hasEntries = content
        .split('\n')
        .any((l) => l.trim().startsWith('- ') || l.contains('[['));
    if (!hasEntries && _path == 'MEMORY.md') {
      return SizedBox(
        height: 280,
        child: EmptyState(
          icon: 'brain',
          title: 'Nothing remembered yet',
          body: _emptyBody(scope),
        ),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_path != 'MEMORY.md')
            Padding(
              padding: const EdgeInsets.only(bottom: S.s12),
              child: Text(_path, style: mono(12.5, color: AppColors.fg3)),
            ),
          MarkdownBody(
            data: memoryMarkdown(content),
            selectable: false,
            styleSheet: documentMarkdownStyle(context)
                .copyWith(em: sans(12, color: AppColors.fg4)),
            builders: {'pre': PreBlockBuilder()},
            onTapLink: (_, href, __) {
              if (href != null && href.startsWith('memory:')) {
                _openPath(href.substring('memory:'.length));
              } else {
                openMarkdownLink(href, context);
              }
            },
          ),
        ],
      ),
    );
  }

  String _emptyBody(MemoryScope scope) {
    if (scope.kind == 'agent') {
      return 'Filled by sessions and tasks run as ${scope.label}. Lessons from your other sessions go to global and project memory.';
    }
    if (scope.kind == 'project') {
      return 'Filled by sessions working in this project.';
    }
    return 'Entries appear here as agents save what they learn.';
  }

  Widget _historyBody() {
    final commits = _commits;
    if (commits == null) {
      return const SizedBox(height: 240, child: Center(child: Spinner(size: 20)));
    }
    return Column(children: [
      for (final c in commits)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(c.isConsolidation ? 'layers' : 'git-commit',
                  size: 15,
                  color: c.isConsolidation ? AppColors.accent : AppColors.fg4),
            ),
            const SizedBox(width: S.s12),
            Expanded(
              child: Text(
                  c.isConsolidation
                      ? c.subject.substring('Consolidate:'.length).trim()
                      : c.subject,
                  style: sans(14, height: 19 / 14, color: AppColors.fg1)),
            ),
            const SizedBox(width: S.s12),
            Text(relativeTime(c.date),
                style: sans(12, color: AppColors.fg4, tabular: true)),
          ]),
        ),
    ]);
  }
}

String scopeTitle(MemoryScope? s, String key) {
  if (s == null) {
    final kind = key.split(':').first;
    return switch (kind) {
      'global' => 'You',
      'session' => 'This session',
      _ => key.split(':').skip(1).join(':'),
    };
  }
  return switch (s.kind) {
    'global' => 'You',
    'session' => sessionScopeTitle(s.label),
    _ => s.label,
  };
}

String sessionScopeTitle(String id) {
  final workspace =
      id.split('/').first.replaceFirst(RegExp(r'-[0-9a-f]{8,}$'), '');
  return id.contains('/conversations/') ? '$workspace · chat' : workspace;
}

String scopeIcon(String kind) => switch (kind) {
      'global' => 'user',
      'project' => 'folder',
      'agent' => 'agent',
      _ => 'chat-thread',
    };

String scopeStatus(MemoryScope s) {
  final entries = '${s.entries} ${s.entries == 1 ? 'entry' : 'entries'}';
  if (s.consolidating) return '$entries · consolidating now';
  if (s.kind == 'session') {
    return s.lastCommitAt == null
        ? entries
        : '$entries · updated ${relativeTime(s.lastCommitAt!)}';
  }
  final consolidated = s.lastConsolidated == null
      ? 'not consolidated yet'
      : 'consolidated ${relativeTime(s.lastConsolidated!)}';
  return '$entries · $consolidated';
}

/// One scope: its MEMORY.md (or a linked topic file), its files, its history.
class _ScopeView extends StatefulWidget {
  final DaemonClient client;
  final String scopeKey;
  final MemoryScope? scope;
  const _ScopeView({
    super.key,
    required this.client,
    required this.scopeKey,
    required this.scope,
  });

  @override
  State<_ScopeView> createState() => _ScopeViewState();
}

enum _Tab { memory, files, history }

class _ScopeViewState extends State<_ScopeView> {
  _Tab _tab = _Tab.memory;
  final List<String> _trail = ['MEMORY.md'];
  String? _content;
  List<String> _files = const [];
  List<MemoryCommit>? _history;
  String? _error;

  String get _path => _trail.last;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _content = null;
      _error = null;
    });
    try {
      final f = await widget.client.memoryFile(widget.scopeKey, path: _path);
      if (mounted) {
        setState(() {
          _content = f.content;
          _files = f.files;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final h = await widget.client.memoryHistory(widget.scopeKey);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _openFile(String path) {
    final file = path.contains('.') ? path : '$path.md';
    setState(() {
      _tab = _Tab.memory;
      if (_trail.last != file) _trail.add(file);
    });
    _loadFile();
  }

  void _backFile() {
    if (_trail.length < 2) return;
    setState(() => _trail.removeLast());
    _loadFile();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    final side = kMobile ? M.gutter : 24.0;
    final page = PopScope(
      canPop: _trail.length < 2,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backFile();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s != null)
            Padding(
              padding: EdgeInsets.fromLTRB(side + 4, 0, side, 8),
              child: Text(scopeStatus(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg4)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(side, 0, side, 10),
            child: Row(children: [
              Pills<_Tab>(
                items: const [
                  (_Tab.memory, 'Memory'),
                  (_Tab.files, 'Files'),
                  (_Tab.history, 'History'),
                ],
                selected: _tab,
                onSelect: (t) {
                  setState(() => _tab = t);
                  if (t == _Tab.history && _history == null) _loadHistory();
                },
              ),
            ]),
          ),
          Expanded(
            child: Swap(
              stateKey: '$_tab:$_path:${_content != null}',
              fill: true,
              child: switch (_tab) {
                _Tab.memory => _memory(side),
                _Tab.files => _fileList(side),
                _Tab.history => _historyList(side),
              },
            ),
          ),
        ],
      ),
    );
    if (kMobile) return page;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: page,
      ),
    );
  }

  String _emptyBody() {
    final key = widget.scopeKey;
    if (key.startsWith('agent:')) {
      final name = widget.scope?.label ?? key.substring('agent:'.length);
      return 'Filled by sessions and tasks run as $name. Lessons from your other sessions go to global and project memory.';
    }
    if (key.startsWith('project:')) {
      return 'Filled by sessions working in this project.';
    }
    return 'Entries appear here as agents save what they learn.';
  }

  Widget _memory(double side) {
    final content = _content;
    if (content == null) {
      return Center(
        child: _error == null
            ? const Spinner(size: 20)
            : const EmptyState(
                icon: 'brain',
                title: 'Nothing remembered yet',
                body: 'This memory fills in as work happens here.',
              ),
      );
    }
    final hasEntries = content
        .split('\n')
        .any((l) => l.trim().startsWith('- ') || l.contains('[['));
    if (!hasEntries && _trail.length < 2) {
      return Center(
        child: EmptyState(
          icon: 'brain',
          title: 'Nothing remembered yet',
          body: _emptyBody(),
        ),
      );
    }
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(side, 4, side, 40),
        children: [
          if (_trail.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _backFile,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.fg3,
                  minimumSize: kMobile ? const Size(0, 30) : const Size(0, 28),
                  padding: EdgeInsets.symmetric(horizontal: kMobile ? 6 : 8),
                  tapTargetSize: kMobile
                      ? null
                      : MaterialTapTargetSize.shrinkWrap,
                ),
                icon: AppIcon('chevron-left', size: 14, color: AppColors.fg3),
                label: Text(_trail[_trail.length - 2],
                    style: sans(13, color: AppColors.fg3)),
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox(
                width: double.infinity,
                child: MarkdownBody(
                  data: memoryMarkdown(content),
                  selectable: false,
                  styleSheet: documentMarkdownStyle(context)
                      .copyWith(em: sans(12, color: AppColors.fg4)),
                  builders: {'pre': PreBlockBuilder()},
                  onTapLink: (_, href, __) {
                    if (href != null && href.startsWith('memory:')) {
                      _openFile(href.substring('memory:'.length));
                    } else {
                      openMarkdownLink(href, context);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileList(double side) => PageBody(
        topPadding: 4,
        children: [
          ListGroup(children: [
            for (final f in _files)
              ListRow(
                title: f,
                titleWidget: Text(f,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(13, color: AppColors.fg1)),
                leading: IconTile(f == 'MEMORY.md' ? 'brain' : 'file-text'),
                onTap: () {
                  setState(() {
                    _trail
                      ..clear()
                      ..add('MEMORY.md');
                  });
                  _openFile(f);
                },
              ),
          ]),
        ],
      );

  Widget _historyList(double side) {
    final history = _history;
    if (history == null) return const Center(child: Spinner(size: 20));
    return PageBody(
      topPadding: 4,
      children: [
        for (final c in history)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppIcon(c.isConsolidation ? 'layers' : 'git-commit',
                    size: 15,
                    color:
                        c.isConsolidation ? AppColors.accent : AppColors.fg4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    c.isConsolidation
                        ? c.subject.substring('Consolidate:'.length).trim()
                        : c.subject,
                    style: sans(14, height: 19 / 14, color: AppColors.fg1)),
              ),
              const SizedBox(width: 10),
              Text(relativeTime(c.date),
                  style: sans(12, color: AppColors.fg4, tabular: true)),
            ]),
          ),
      ],
    );
  }
}

/// MEMORY.md as readable markdown: `[[links]]` become tappable, and the
/// `[source: …; added: …]` metadata shrinks to a quiet date.
String memoryMarkdown(String text) {
  var out = text.replaceAllMapped(
      RegExp(r'\[\[([^\]]+)\]\]'), (m) => '[${m[1]}](memory:${m[1]})');
  out = out.replaceAllMapped(
      RegExp(r'[ \t]*\[(?:source|added)[^\]\n]*\]', multiLine: true), (m) {
    final added = RegExp(r'added: (\d{4}-\d{2}-\d{2})').firstMatch(m[0]!);
    return added == null ? '' : '  *${added[1]}*';
  });
  return out;
}
