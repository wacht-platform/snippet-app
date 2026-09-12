import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Open a folder to start a new conversation in.
///
/// ONE screen for both platforms: `presentScreen` picks the shape from the
/// window width — a centered modal on desktop, a full screen on a phone.
///
/// Deliberately NOT a file browser. Two rules hold this design together:
///
///  1. A row tap does exactly ONE thing — navigate in. It never also starts a
///     conversation, which is what made the previous version ambiguous.
///  2. There is exactly ONE highlighted action, pinned to the bottom, naming the
///     folder it will use.
///
/// Folders only. Files cannot be opened or picked here, so listing them gave the
/// eye work with no matching affordance; upload lives in the pinned bar instead.
class NewSessionPicker extends StatefulWidget {
  const NewSessionPicker({
    super.key,
    required this.client,
    required this.machineLabel,
    required this.onOpenFolder,
    this.startPath,
    this.onClose,
  });

  final DaemonClient client;

  /// Which machine these folders live on — identity, not a switcher.
  final String machineLabel;

  /// Start a conversation rooted at the given folder.
  final Future<void> Function(String folder) onOpenFolder;

  /// Where to open. Null means the server's home directory, which is the sane
  /// default: this screen must not depend on a session already being open, and
  /// it must not silently inherit one's workspace.
  final String? startPath;

  /// Absent when the host owns navigation.
  final VoidCallback? onClose;

  @override
  State<NewSessionPicker> createState() => _NewSessionPickerState();
}

class _NewSessionPickerState extends State<NewSessionPicker> {
  FsListing? _listing;

  /// The server's home directory, learned on the first load. Every breadcrumb is
  /// expressed relative to this, and the home button returns to it.
  String? _homePath;

  bool _loading = true;
  String? _error;
  String? _busy;
  int _run = 0;

  /// Keeps the CURRENT folder (the last crumb) in view on wide paths.
  ///
  /// Deliberately NOT `ListView(reverse: true)`: reverse flips the DRAWING order,
  /// which rendered `intellinesia › code › ~` — the path backwards. Order stays
  /// left-to-right; only the scroll position moves to the end.
  final ScrollController _crumbScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _go(widget.startPath);
  }

  @override
  void dispose() {
    _crumbScroll.dispose();
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
      setState(() {
        _listing = res;
        // The first successful load of an unspecified path IS home.
        if (path == null || _homePath == null) _homePath = res.path;
        _loading = false;
      });
      // After the crumbs rebuild, park the view at the deep end.
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

  /// Folders first (tappable), then files (inert), each alphabetical.
  ///
  /// Files are LISTED but not tappable. Hiding them made "New file" look broken
  /// — you could create one and never see it — and a folder browser that hides
  /// the files you just made reads as a failed write. They stay non-interactive
  /// because a tap here can only mean "navigate in", which a file cannot do.
  List<FsEntry> get _dirs => _sorted(true);
  List<FsEntry> get _files => _sorted(false);

  List<FsEntry> _sorted(bool dirs) {
    final entries = _listing?.entries ?? const <FsEntry>[];
    final all = [
      for (final e in entries)
        if (e.isDir == dirs) e
    ];
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  String get _here => _listing?.path ?? '';

  String get _hereName =>
      _here.isEmpty ? 'home' : lastPathSegment(_here, ifEmpty: _here);

  bool get _atHome =>
      _homePath == null || _homePath!.isEmpty || _here == _homePath;

  /// Path split into tappable crumbs, relative to home: `~ › code › repo`.
  ///
  /// Each crumb carries the absolute path it jumps to, so tapping a middle one
  /// goes straight there rather than one level at a time.
  List<_Crum> get _crumbs {
    final home = _homePath;
    final here = _here;
    if (here.isEmpty) return const [];
    if (home == null || home.isEmpty) return [_Crum('~', here)];
    final crumbs = <_Crum>[_Crum('~', home)];
    if (here == home) return crumbs;
    // Only a genuine descendant splits into parts — otherwise `~/x` and `~/x-two`
    // would be conflated by a plain prefix test.
    if (!here.startsWith('$home/')) {
      return [...crumbs, _Crum(_hereName, here)];
    }
    var acc = home;
    for (final part in here.substring(home.length + 1).split('/')) {
      if (part.isEmpty) continue;
      acc = '$acc/$part';
      crumbs.add(_Crum(part, acc));
    }
    return crumbs;
  }

  Future<void> _open() async {
    final path = _here;
    if (path.isEmpty) return;
    setState(() => _busy = 'Starting…');
    try {
      await widget.onOpenFolder(path);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        toast(context, '$e', danger: true);
      }
    }
  }

  /// Normalize a typed name into a safe RELATIVE path, or null if unusable.
  ///
  /// Splitting on `/` is what makes nesting work: `src/api/v2` becomes three
  /// levels in one step. `..` is rejected so a name cannot walk out of the
  /// folder you are looking at — the daemon would happily create it, and the
  /// picker would then be browsing somewhere the user did not choose.
  String? _sanitizeRel(String raw) {
    final parts = raw
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '.')
        .toList();
    if (parts.isEmpty) return null;
    if (parts.any((p) => p == '..')) return null;
    return parts.join('/');
  }

  /// Create a folder inside the current one.
  ///
  /// The name may contain `/`, so a whole nested chain is created at once — the
  /// daemon's `/fs/mkdir` calls `create_dir_all`, which builds the intermediate
  /// levels for free. No per-level round trip needed.
  Future<void> _newFolder() => _create(isDir: true);

  /// Create an empty file inside the current one, with the same nesting rule.
  /// A file has no content to type here; this is for placing structure, and the
  /// editor (or upload) fills it in afterwards.
  Future<void> _newFile() => _create(isDir: false);

  Future<void> _create({required bool isDir}) async {
    final dir = _here;
    if (dir.isEmpty) return;
    final name = await promptText(
      context,
      title: isDir ? 'New folder' : 'New file',
      hint: isDir ? 'name, or path/in/one/go' : 'name, or path/in/one.go',
      saveLabel: 'Create',
    );
    if (name == null || !mounted) return;
    final rel = _sanitizeRel(name);
    if (rel == null) {
      toast(context, 'Enter a name, with no leading / or ..', danger: true);
      return;
    }
    setState(() => _busy = 'Creating…');
    try {
      final path = '$dir/$rel';
      if (isDir) {
        await widget.client.mkdir(path);
      } else {
        await widget.client.writeFile(path, '');
      }
      if (!mounted) return;
      setState(() => _busy = null);
      // Reload so the new entry appears. The picker lists FOLDERS only, so a new
      // file is confirmed by its toast rather than by a row.
      await _go(dir);
      if (mounted) toast(context, 'Created $rel');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _upload() async {
    final dir = _here;
    if (dir.isEmpty) return;
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (mounted) {
        setState(() => _busy = 'Uploading ${i + 1}/${files.length}…');
      }
      try {
        await widget.client
            .uploadFile(await f.readAsBytes(), name: f.name, dir: dir);
        done++;
      } catch (e) {
        if (mounted) toast(context, '${f.name}: $e', danger: true);
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (done > 0) {
      await _go(dir);
      if (mounted) toast(context, 'Uploaded $done file${done == 1 ? '' : 's'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    // A Material ancestor is REQUIRED, not merely for ink: without one every
    // Text outside a nested Material falls back to DefaultTextStyle.fallback(),
    // whose yellow double underline is what the phone build showed. The desktop
    // dialog supplies its own Material; presentScreen's narrow branch does not.
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        // presentScreen renders edge-to-edge when narrow, so the phone's status
        // bar inset has to come from here.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (_error != null)
              Expanded(child: _errorState())
            else ...[
              _breadcrumbs(),
              Expanded(
                child: _loading && _listing == null
                    ? const Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : RefreshIndicator(
                        color: AppColors.accent,
                        backgroundColor: AppColors.surface3,
                        onRefresh: () async => _go(_here),
                        child: _folderList(),
                      ),
              ),
              _actionBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? M.gutter : 16, 12, 10, 8),
        child: Row(children: [
          Expanded(
            child: Text('New chat',
                style: sans(kMobile ? 17 : 15,
                    weight: W.label, color: AppColors.fg1)),
          ),
          if (widget.onClose != null)
            IconBtn('x',
                size: kMobile ? M.minTarget : 30,
                iconSize: kMobile ? 19 : 15,
                tooltip: 'Close',
                onTap: widget.onClose),
        ]),
      );

  /// Breadcrumb + home, in place of a raw path field: it shows where you are and
  /// jumps up several levels in one tap, instead of asking you to edit text.
  Widget _breadcrumbs() {
    final crumbs = _crumbs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: kMobile ? M.gutter : 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: kMobile ? M.minTarget : 40,
            child: ListView.separated(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              // Order is deliberately LEFT-TO-RIGHT (root first). `reverse: true`
              // would have kept the tail in view but draws the list backwards,
              // which rendered the path as `intellinesia › code › ~`. The
              // controller jumps to the deep end instead (see `_go`).
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child:
                      AppIcon('chevron-right', size: 12, color: AppColors.fg4),
                ),
              ),
              itemBuilder: (_, i) {
                final c = crumbs[i];
                final last = i == crumbs.length - 1;
                return Center(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(R.sm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.sm),
                      onTap: last ? null : () => _go(c.path),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(kMobile ? 12.5 : 12,
                              weight: last ? W.label : W.body,
                              color: last ? AppColors.fg1 : AppColors.fg3),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconBtn('arrow-up',
            size: kMobile ? M.minTarget : 36,
            iconSize: 17,
            tooltip: 'Home',
            onTap: _atHome ? null : () => _go(_homePath)),
      ]),
    );
  }

  Widget _folderList() {
    final dirs = _dirs;
    final files = _files;
    if (dirs.isEmpty && files.isEmpty) {
      // Still a ListView, so RefreshIndicator has a scrollable to attach to.
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 44),
        children: [
          Text('This folder is empty.',
              textAlign: TextAlign.center,
              style: sans(12.5, color: AppColors.fg4)),
        ],
      );
    }
    // Folders first so the tappable rows are always above the fold; files
    // follow as context. One flat list keeps the index arithmetic simple and
    // lets a single ListView.builder do both.
    final rows = <Widget>[
      for (final d in dirs) _folderRow(d),
      if (dirs.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
      for (final f in files) _fileRow(f),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  /// A file: shown for context, deliberately NOT tappable.
  ///
  /// Visually muted and without a chevron, so it does not invite a tap that
  /// cannot go anywhere.
  Widget _fileRow(FsEntry e) {
    return Container(
      height: kMobile ? 40 : 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        AppIcon('file', size: 14, color: AppColors.fg4),
        const SizedBox(width: 12),
        Expanded(
          child: Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(kMobile ? 12.5 : 12, color: AppColors.fg3)),
        ),
      ]),
    );
  }

  Widget _folderRow(FsEntry e) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        hoverColor: AppColors.surface2,
        onTap: _busy == null ? () => _go(e.path) : null,
        child: MouseRegion(
          // The desktop half of "this goes somewhere".
          cursor: SystemMouseCursors.click,
          child: Container(
            height: kMobile ? 46 : 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              AppIcon('folder', size: 15, color: AppColors.fg2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 13.5 : 12.5, color: AppColors.fg1)),
              ),
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }

  /// The single highlighted action, pinned so it never scrolls out of reach.
  ///
  /// Deliberately under the full touch height: as a pinned bar it is always
  /// present, so a 48px block read as a slab competing with the folder list
  /// rather than a footer action. The whole row is still the target.
  Widget _actionBar() => Container(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 16, 8, kMobile ? M.gutter : 16, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(children: [
          IconBtn('folder-plus',
              size: kMobile ? 40 : 34,
              iconSize: kMobile ? 17 : 15,
              tooltip: 'New folder here',
              onTap: (_listing == null || _busy != null) ? null : _newFolder),
          const SizedBox(width: 2),
          IconBtn('file-plus',
              size: kMobile ? 40 : 34,
              iconSize: kMobile ? 17 : 15,
              tooltip: 'New file here',
              onTap: (_listing == null || _busy != null) ? null : _newFile),
          const SizedBox(width: 2),
          IconBtn('upload',
              size: kMobile ? 40 : 34,
              iconSize: kMobile ? 17 : 15,
              tooltip: 'Upload files into this folder',
              onTap: (_listing == null || _busy != null) ? null : _upload),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(R.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.md),
                onTap: _busy != null ? null : _open,
                child: Container(
                  height: kMobile ? 40 : 34,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy != null)
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: AppColors.accentFg))
                      else
                        // `chat-thread` is the app's ONE conversation glyph, used
                        // by every session row and tab. `corner-down-right`
                        // rendered as a return/enter arrow, which reads as "send
                        // message" rather than "start a conversation here".
                        AppIcon('chat-thread',
                            size: kMobile ? 15 : 14, color: AppColors.accentFg),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _busy ?? 'Start chat in $_hereName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(kMobile ? 13.5 : 12.5,
                              weight: W.label, color: AppColors.accentFg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('wifi-off', size: 22, color: AppColors.fg4),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: sans(12.5, color: AppColors.fg3, height: 1.45)),
            const SizedBox(height: 14),
            Btn('Retry', small: true, onTap: () => _go(widget.startPath)),
          ]),
        ),
      );
}

/// One breadcrumb: the label to draw and the absolute path it jumps to.
class _Crum {
  const _Crum(this.label, this.path);
  final String label;
  final String path;
}
