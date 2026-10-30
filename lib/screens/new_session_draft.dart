import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class NewSessionDraft extends StatefulWidget {
  const NewSessionDraft({
    super.key,
    required this.client,
    required this.machineLabel,
    required this.onStart,
    this.folder,
  });

  final DaemonClient client;
  final String machineLabel;
  final String? folder;
  final Future<void> Function(
      String folder, WorkspaceMode mode, String? profile, String text) onStart;

  @override
  State<NewSessionDraft> createState() => _NewSessionDraftState();
}

class _NewSessionDraftState extends State<NewSessionDraft> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _folderChipKey = GlobalKey();
  String? _folder;
  WorkspaceMode _mode = WorkspaceMode.worktree;
  bool _isRepo = false;
  String? _branch;
  List<InferenceProfile> _profiles = const [];
  String? _profile;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _input.addListener(() => setState(() {}));
    _loadRepo();
    _loadProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted) return;
      setState(() {
        _profiles = cfg.profiles;
        _profile =
            cfg.active ?? cfg.profiles.where((p) => p.active).firstOrNull?.name;
      });
    } catch (_) {}
  }

  Future<void> _loadRepo() async {
    final f = _folder;
    if (f == null || f.isEmpty) {
      setState(() {
        _isRepo = false;
        _branch = null;
      });
      return;
    }
    try {
      final r = await widget.client.worktrees(f);
      if (!mounted || _folder != f) return;
      final main = r.worktrees.where((w) => w.path == r.repo).firstOrNull ??
          r.worktrees.firstOrNull;
      setState(() {
        _isRepo = r.repo != null;
        _branch = main?.branch;
        if (!_isRepo) _mode = WorkspaceMode.folder;
      });
    } catch (_) {
      if (mounted) setState(() => _isRepo = false);
    }
  }

  Future<void> _pickFolder() async {
    final picked = await _showFolderPopover(
      context,
      anchor: _folderChipKey.currentContext,
      client: widget.client,
      startPath: _folder,
    );
    if (picked != null && mounted) {
      setState(() => _folder = picked);
      _loadRepo();
    }
    if (mounted) _focus.requestFocus();
  }

  Future<void> _start() async {
    final text = _input.text.trim();
    if (_starting) return;
    if (_folder == null) {
      await _pickFolder();
      return;
    }
    if (text.isEmpty) return;
    setState(() => _starting = true);
    try {
      await widget.onStart(_folder!, _mode, _profile, text);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _pickProfile(BuildContext anchor) async {
    if (_profiles.isEmpty) return;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 260,
      maxWidth: 360,
      items: [
        appMenuHeading<String>('Inference profile'),
        for (final p in _profiles)
          appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} · ${p.model}',
            selected: p.name == _profile,
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _profile = picked);
  }

  Widget _chip(String icon, String label,
          {VoidCallback? onTap, bool filled = false}) =>
      Material(
        color: filled ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 13, color: AppColors.fg3),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, color: AppColors.fg3)),
              ),
            ]),
          ),
        ),
      );

  Widget _worktreeToggle() {
    final on = _mode == WorkspaceMode.worktree;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(
            () => _mode = on ? WorkspaceMode.folder : WorkspaceMode.worktree),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 13,
              padding: const EdgeInsets.all(2),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: on ? AppColors.accent : AppColors.fg4,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text('Worktree',
                style: sans(12.5, color: on ? AppColors.fg2 : AppColors.fg4)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folderName = _folder == null
        ? 'Choose folder'
        : lastPathSegment(_folder!, ifEmpty: _folder!);
    final current = _profiles.where((p) => p.name == _profile).firstOrNull;
    final canSend = !_starting && _input.text.trim().isNotEmpty;
    return Container(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: box.maxHeight, minWidth: box.maxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 70),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const DottedMochi(width: 300),
                  const SizedBox(height: 10),
                  Text('What are we making?',
                      style: sans(26, spacing: -0.5, color: AppColors.fg1)),
                  const SizedBox(height: 26),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Wrap(spacing: 6, children: [
                              KeyedSubtree(
                                key: _folderChipKey,
                                child: _chip('folder', folderName,
                                    filled: true, onTap: _pickFolder),
                              ),
                              if (_isRepo && (_branch ?? '').isNotEmpty)
                                _chip('git-branch', _branch!),
                              if (_isRepo) _worktreeToggle(),
                            ]),
                          ),
                          CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.enter):
                                  _start,
                            },
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              minLines: 2,
                              maxLines: 10,
                              style:
                                  sans(14.5, height: 1.5, color: AppColors.fg1),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(18, 12, 18, 6),
                                hintText: 'Ask, build, or type / for commands',
                                hintStyle: sans(14.5, color: AppColors.fg4),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                            child: Row(children: [
                              const Spacer(),
                              if (current != null)
                                Builder(
                                  builder: (anchor) => Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(15),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(15),
                                      onTap: () => _pickProfile(anchor),
                                      child: Container(
                                        height: 30,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Row(children: [
                                          ProviderLogo(current.provider,
                                              size: 13),
                                          const SizedBox(width: 7),
                                          Text(current.name,
                                              style: sans(12.5,
                                                  color: AppColors.fg2)),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Material(
                                color: canSend
                                    ? AppColors.fg1
                                    : AppColors.surface2,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: canSend ? _start : null,
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Center(
                                      child: _starting
                                          ? const Spinner(size: 14)
                                          : AppIcon('arrow-up',
                                              size: 16,
                                              color: canSend
                                                  ? AppColors.bg
                                                  : AppColors.fg4),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _showFolderPopover(
  BuildContext context, {
  required BuildContext? anchor,
  required DaemonClient client,
  String? startPath,
}) {
  final screen = MediaQuery.sizeOf(context);
  const width = 340.0;
  var left = (screen.width - width) / 2;
  var top = 220.0;
  final box = anchor?.findRenderObject() as RenderBox?;
  if (box != null) {
    final origin = box.localToGlobal(Offset.zero);
    left = origin.dx
        .clamp(12.0, (screen.width - width - 12).clamp(12.0, double.infinity));
    top = origin.dy + box.size.height + 6;
  }
  final maxHeight = (screen.height - top - 16).clamp(220.0, 360.0);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Choose folder',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.quick,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        left: left,
        top: top,
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _FolderPopover(client: client, startPath: startPath),
        ),
      ),
    ]),
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Motion.enter);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.97, end: 1.0).animate(c),
          child: child,
        ),
      );
    },
  );
}

class _FolderPopover extends StatefulWidget {
  const _FolderPopover({required this.client, this.startPath});
  final DaemonClient client;
  final String? startPath;

  @override
  State<_FolderPopover> createState() => _FolderPopoverState();
}

class _FolderPopoverState extends State<_FolderPopover> {
  final _crumbScroll = ScrollController();
  final _newFolderCtrl = TextEditingController();
  FsListing? _listing;
  String? _homePath;
  bool _loading = true;
  String? _error;
  bool _creating = false;
  bool _busy = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _go(widget.startPath);
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _go(String? path) async {
    final id = ++_run;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.client.fs(path);
      if (!mounted || id != _run) return;
      final learnHome = _homePath == null &&
          (path == null || path.isEmpty) &&
          res.path.isNotEmpty;
      setState(() {
        if (learnHome) _homePath = res.path;
        _listing = res;
        _loading = false;
      });
      if (_homePath == null && path != null && path.isNotEmpty) {
        _learnHome();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _crumbScroll.hasClients) {
          _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted || id != _run) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _learnHome() async {
    try {
      final res = await widget.client.fs(null);
      if (mounted && _homePath == null && res.path.isNotEmpty) {
        setState(() => _homePath = res.path);
      }
    } catch (_) {}
  }

  String get _here => _listing?.path ?? '';

  bool get _atHome =>
      _homePath != null && _homePath!.isNotEmpty && _here == _homePath;

  String get _hereName => _here.isEmpty
      ? 'folder'
      : (_atHome ? '~' : lastPathSegment(_here, ifEmpty: _here));

  String get _displayPath {
    final home = _homePath;
    if (home != null && home.isNotEmpty) {
      if (_here == home) return '~';
      if (_here.startsWith('$home/'))
        return '~/${_here.substring(home.length + 1)}';
    }
    return _here;
  }

  List<FsEntry> get _dirs {
    final entries = _listing?.entries ?? const <FsEntry>[];
    final all = [
      for (final e in entries)
        if (e.isDir) e
    ];
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  List<({String label, String path})> get _crumbs {
    final home = _homePath;
    final here = _here;
    if (here.isEmpty) return const [];
    if (home != null &&
        home.isNotEmpty &&
        (here == home || here.startsWith('$home/'))) {
      final out = <({String label, String path})>[(label: '~', path: home)];
      if (here == home) return out;
      var acc = home;
      for (final part in here.substring(home.length + 1).split('/')) {
        if (part.isEmpty) continue;
        acc = '$acc/$part';
        out.add((label: part, path: acc));
      }
      return out;
    }
    final parts = here.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return [(label: '/', path: '/')];
    final out = <({String label, String path})>[];
    var acc = '';
    for (final part in parts) {
      acc = '$acc/$part';
      out.add((label: part, path: acc));
    }
    return out;
  }

  Future<void> _submitNewFolder() async {
    final raw = _newFolderCtrl.text.trim();
    if (raw.isEmpty || _here.isEmpty || _busy) return;
    final parts = raw
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '.')
        .toList();
    if (parts.isEmpty || parts.any((p) => p == '..')) return;
    final target = '$_here/${parts.join('/')}';
    setState(() => _busy = true);
    try {
      await widget.client.mkdir(target);
      if (!mounted) return;
      _newFolderCtrl.clear();
      setState(() {
        _creating = false;
        _busy = false;
      });
      await _go(target);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbs;
    final dirs = _dirs;
    final parent = _listing?.parent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                if (!_atHome && parent != null && parent.isNotEmpty)
                  IconBtn('chevron-left',
                      size: 24,
                      iconSize: 14,
                      tooltip: 'Up one folder',
                      onTap: _loading ? null : () => _go(parent)),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _crumbScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < crumbs.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text('/',
                                style: mono(11.5, color: AppColors.fg4)),
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: i == crumbs.length - 1
                              ? null
                              : () => _go(crumbs[i].path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 3),
                            child: Text(
                              crumbs[i].label,
                              style: sans(
                                12.5,
                                weight: i == crumbs.length - 1
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: i == crumbs.length - 1
                                    ? AppColors.fg1
                                    : AppColors.fg3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
                IconBtn(
                  _creating ? 'x' : 'folder-plus',
                  size: 26,
                  iconSize: 14,
                  tooltip: _creating ? 'Cancel' : 'New folder',
                  onTap: _here.isEmpty
                      ? null
                      : () => setState(() {
                            _creating = !_creating;
                            _newFolderCtrl.clear();
                          }),
                ),
              ]),
            ),
            if (_creating)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(children: [
                  AppIcon('folder-plus', size: 14, color: AppColors.fg3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _newFolderCtrl,
                      autofocus: true,
                      style: sans(12.5, color: AppColors.fg1),
                      onSubmitted: (_) => _submitNewFolder(),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'New folder name',
                        hintStyle: sans(12.5, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _busy ? null : _submitNewFolder,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_busy ? '…' : 'Create',
                          style: sans(11.5,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                  ),
                ]),
              ),
            Flexible(
              child: _loading && _listing == null
                  ? const SizedBox(
                      height: 140,
                      child: Center(child: Spinner(size: 16)),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: sans(12, color: AppColors.fg3)),
                              const SizedBox(height: 10),
                              Btn('Retry',
                                  small: true,
                                  onTap: () => _go(widget.startPath)),
                            ],
                          ),
                        )
                      : dirs.isEmpty
                          ? SizedBox(
                              height: 96,
                              child: Center(
                                child: Text('No subfolders',
                                    style: sans(12.5, color: AppColors.fg4)),
                              ),
                            )
                          : SizedBox(
                              height: (dirs.length.clamp(1, _creating ? 5 : 7) *
                                      32.0) +
                                  12,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(6),
                                itemExtent: 32,
                                itemCount: dirs.length,
                                itemBuilder: (ctx, i) {
                                  final e = dirs[i];
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(7),
                                    onTap: () => _go(e.path),
                                    child: Container(
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Row(children: [
                                        AppIcon('folder',
                                            size: 15, color: AppColors.fg3),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            e.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                sans(13, color: AppColors.fg1),
                                          ),
                                        ),
                                        AppIcon('chevron-right',
                                            size: 14, color: AppColors.fg4),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
            Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(11.5, color: AppColors.fg3),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _here.isEmpty ? AppColors.surface2 : AppColors.fg1,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: _here.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_here),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      alignment: Alignment.center,
                      child: Text(
                        'Use $_hereName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            weight: FontWeight.w500,
                            color:
                                _here.isEmpty ? AppColors.fg4 : AppColors.bg),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
