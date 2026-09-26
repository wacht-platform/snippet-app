import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../file_actions.dart';
import '../highlight.dart';
import '../models.dart';
import '../notifications.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor.dart';
import 'git.dart';
import 'file_viewer.dart';
export 'file_viewer.dart';

/// Standalone file browser — navigate folders and view file contents on a
/// connected machine without opening an agent session.
class FileExplorer extends StatefulWidget {
  final DaemonClient client;
  final String title;
  final String? start; // initial folder (null = the daemon's home dir)
  final VoidCallback? onClose; // dismiss when hosted in a desktop panel
  final void Function(String folder)?
      onNewChat; // start a chat in the current folder
  final void Function(String path, String name)?
      onOpenFile; // open as a shell tab
  /// When set, tapping a file pops this path instead of opening a viewer.
  final void Function(String path)? onPickFile;
  const FileExplorer(
      {super.key,
      required this.client,
      this.title = 'Files',
      this.start,
      this.onClose,
      this.onNewChat,
      this.onOpenFile,
      this.onPickFile});
  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  late Future<FsListing> _future;
  bool _selecting = false;
  final Set<String> _selected = {};
  String?
      _busy; // non-null while uploading/deleting (label shown in a progress strip)
  String?
      _root; // the folder we opened at — the OS back button climbs no higher
  String? _viewingPath;
  String? _viewingName;
  final TextEditingController _filterCtl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _future = widget.client.fs(widget.start);
  }

  @override
  void dispose() {
    _filterCtl.dispose();
    super.dispose();
  }

  void _go(String? path) => setState(() {
        _future = widget.client.fs(path);
        _filterCtl.clear();
        _filter = '';
        _selecting = false;
        _selected.clear();
      });

  void _toggle(FsEntry e) => setState(() {
        if (!_selected.remove(e.path)) _selected.add(e.path);
        if (_selected.isEmpty) _selecting = false;
      });

  void _enterSelect(FsEntry e) => setState(() {
        _selecting = true;
        _selected.add(e.path);
      });

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _deleteSelected(String cwd) async {
    final n = _selected.length;
    if (n == 0) return;
    final ok = await confirmAction(
      context,
      title: 'Delete $n item${n == 1 ? '' : 's'}?',
      body:
          'Permanently deletes the selected item${n == 1 ? '' : 's'} from the machine. Folders are removed with their contents.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    if (mounted)
      setState(() => _busy = 'Deleting $n item${n == 1 ? '' : 's'}…');
    var failed = 0;
    for (final p in _selected.toList()) {
      try {
        await widget.client.deletePath(p);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (failed > 0)
      toast(context, 'Failed to delete $failed item(s)', danger: true);
    _go(cwd); // refresh + clears selection
  }

  Future<void> _newFolder(String cwd) async {
    final name = await promptText(context,
        title: 'New folder', hint: 'Folder name', saveLabel: 'Create');
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      await widget.client.mkdir('$cwd/$trimmed');
      if (!mounted) return;
      _go(cwd);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  // Upload files from the device into the current directory.
  Future<void> _upload(String cwd) async {
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    var uploaded = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (mounted)
        setState(() => _busy = 'Uploading ${i + 1}/${files.length}…');
      try {
        final bytes = await f.readAsBytes();
        await widget.client.uploadFile(bytes, name: f.name, dir: cwd);
        uploaded++;
      } catch (e) {
        if (mounted) toast(context, '${f.name}: $e', danger: true);
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (uploaded > 0) {
      _go(cwd);
      toast(context, 'Uploaded $uploaded file${uploaded == 1 ? '' : 's'}');
    }
  }

  void _openFile(FsEntry e) {
    final pick = widget.onPickFile;
    if (pick != null) {
      Navigator.of(context).pop(e.path);
      pick(e.path);
      return;
    }
    // ON PHONES the viewer is a full route, whatever the host offered. See
    // `openFileForViewing` — `onOpenFile` opens a shell TAB, which the phone
    // shell never draws. Desktop keeps the tab behaviour below.
    if (openFileForViewing(context,
        client: widget.client, path: e.path, name: e.name)) {
      return;
    }
    final open = widget.onOpenFile;
    if (open != null) {
      (widget.onClose ?? () => Navigator.of(context).pop())();
      open(e.path, e.name);
      return;
    }
    setState(() {
      _viewingPath = e.path;
      _viewingName = e.name;
    });
  }

  // Git for the current folder directly — no session required (the daemon runs
  // git in that directory; non-repos show a "No git here" message).
  void _openGit(String dir) => presentScreen(
        context,
        builder: (_, close) =>
            GitScreen(client: widget.client, folder: dir, onClose: close),
      );

  void _showFolderActions(String cwd) {
    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    showAppSheet(
      context,
      title: 'Folder actions',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onNewChat != null)
            _FileActionRow(
              icon: 'plus',
              label: 'New chat here',
              onTap: () => run(() => widget.onNewChat!(cwd)),
            ),
          _FileActionRow(
            icon: 'git-branch',
            label: 'Git',
            onTap: () => run(() => _openGit(cwd)),
          ),
          _FileActionRow(
            icon: 'upload',
            label: 'Upload files',
            onTap: _busy == null ? () => run(() => _upload(cwd)) : null,
          ),
          _FileActionRow(
            icon: 'folder-plus',
            label: 'New folder',
            onTap: _busy == null ? () => run(() => _newFolder(cwd)) : null,
          ),
        ],
      ),
    );
  }

  List<FsEntry> _visibleEntries(FsListing listing) {
    final query = _filter.trim().toLowerCase();
    final entries = [
      for (final entry in listing.entries)
        if (query.isEmpty || entry.name.toLowerCase().contains(query)) entry,
    ];
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (_viewingPath != null) {
      return FileViewer(
        client: widget.client,
        path: _viewingPath!,
        name: _viewingName ?? '',
        onClose: () => setState(() {
          _viewingPath = null;
          _viewingName = null;
        }),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<FsListing>(
          future: _future,
          builder: (context, snap) {
            final listing = snap.data;
            if (listing != null) _root ??= listing.path;
            final segs = (listing?.path ?? '')
                .split('/')
                .where((s) => s.isNotEmpty)
                .toList();
            // OS/gesture back: exit select mode first → else climb ONE folder →
            // and only leave the browser once we're back at the folder we opened.
            final canLeave = !_selecting &&
                (listing == null ||
                    listing.parent == null ||
                    listing.path == _root);
            return PopScope(
              canPop: canLeave,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_selecting) {
                  _exitSelect();
                } else if (listing != null &&
                    listing.parent != null &&
                    listing.path != _root) {
                  _go(listing.parent);
                }
              },
              child: Column(children: [
                if (!kMobile)
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      border:
                          Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(children: [
                      IconBtn('chevron-left',
                          size: 30,
                          iconSize: 18,
                          tooltip: _selecting ? 'Exit select' : 'Back',
                          onTap: _selecting
                              ? _exitSelect
                              : (listing?.parent != null &&
                                      listing?.path != _root
                                  ? () => _go(listing!.parent!)
                                  : (widget.onClose ??
                                      () => Navigator.pop(context)))),
                      const SizedBox(width: 4),
                      Expanded(
                        child: segs.isEmpty
                            ? Text(widget.title,
                                style: sans(13,
                                    weight: FontWeight.w500,
                                    color: AppColors.fg1))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  GestureDetector(
                                    onTap: listing?.parent == null
                                        ? null
                                        : () => _go('/'),
                                    child: AppIcon('folder',
                                        size: 14, color: AppColors.fg3),
                                  ),
                                  const SizedBox(width: 4),
                                  for (var i = 0; i < segs.length; i++) ...[
                                    if (i > 0)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        child: AppIcon('chevron-right',
                                            size: 11, color: AppColors.fg4),
                                      ),
                                    GestureDetector(
                                      onTap: i == segs.length - 1
                                          ? null
                                          : () => _go(
                                              '/${segs.sublist(0, i + 1).join('/')}'),
                                      child: Text(segs[i],
                                          style: mono(12,
                                              color: i == segs.length - 1
                                                  ? AppColors.fg1
                                                  : AppColors.fg3)),
                                    ),
                                  ],
                                ]),
                              ),
                      ),
                      const SizedBox(width: 8),
                      if (_selecting) ...[
                        Text('${_selected.length} selected',
                            style: sans(12,
                                tabular: true, color: AppColors.accent)),
                        const SizedBox(width: 8),
                        IconBtn('trash',
                            size: 28,
                            iconSize: 14,
                            tooltip: 'Delete',
                            onTap: (_busy != null ||
                                    listing == null ||
                                    _selected.isEmpty)
                                ? null
                                : () => _deleteSelected(listing.path)),
                        IconBtn('x',
                            size: 28,
                            iconSize: 14,
                            tooltip: 'Cancel',
                            onTap: _exitSelect),
                      ] else ...[
                        if (!_selecting &&
                            listing != null &&
                            widget.onNewChat != null)
                          InkWell(
                            onTap: () => widget.onNewChat!(listing.path),
                            borderRadius: BorderRadius.circular(R.xs),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentBg,
                                borderRadius: BorderRadius.circular(R.xs),
                                border: Border.all(color: AppColors.accentLine),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon('plus',
                                        size: 11, color: AppColors.accent),
                                    const SizedBox(width: 4),
                                    Text('New chat here',
                                        style: sans(11,
                                            weight: FontWeight.w500,
                                            color: AppColors.accent)),
                                  ]),
                            ),
                          ),
                        if (listing != null) ...[
                          const SizedBox(width: 4),
                          IconBtn('git-branch',
                              size: 28,
                              iconSize: 14,
                              tooltip: 'Git',
                              onTap: () => _openGit(listing.path)),
                          IconBtn('upload',
                              size: 28,
                              iconSize: 14,
                              tooltip: 'Upload files',
                              onTap: _busy != null
                                  ? null
                                  : () => _upload(listing.path)),
                          IconBtn('folder-plus',
                              size: 28,
                              iconSize: 14,
                              tooltip: 'New folder',
                              onTap: _busy != null
                                  ? null
                                  : () => _newFolder(listing.path)),
                        ],
                        if (widget.onClose != null) ...[
                          const SizedBox(width: 4),
                          IconBtn('x',
                              size: 28,
                              iconSize: 14,
                              tooltip: 'Close',
                              onTap: widget.onClose),
                        ],
                      ],
                    ]),
                  )
                else ...[
                  SnAppBar(
                    title:
                        _selecting ? '${_selected.length} selected' : 'Files',
                    // No subtitle. The folder path was printed TWICE — here and
                    // again in the row below the divider — so the same long
                    // string appeared twice within ~40dp and the header read as
                    // broken. The path describes the LIST, so it belongs in that
                    // row (with the item count); this bar names the screen.
                    titleSize: M.sectionTitle,
                    compact: true,
                    onBack: _selecting
                        ? _exitSelect
                        : (listing?.parent != null && listing?.path != _root
                            ? () => _go(listing!.parent!)
                            : (widget.onClose ?? () => Navigator.pop(context))),
                    actions: _selecting
                        ? [
                            IconBtn('trash',
                                tooltip: 'Delete',
                                onTap: (_busy != null ||
                                        listing == null ||
                                        _selected.isEmpty)
                                    ? null
                                    : () => _deleteSelected(listing.path)),
                            IconBtn('x', tooltip: 'Cancel', onTap: _exitSelect),
                          ]
                        : [
                            if (listing != null && widget.onNewChat != null)
                              IconBtn('plus',
                                  tooltip: 'New chat here',
                                  onTap: () => widget.onNewChat!(listing.path)),
                            if (listing != null)
                              IconBtn('more-vertical',
                                  tooltip: 'Folder actions',
                                  onTap: () =>
                                      _showFolderActions(listing.path)),
                            if (widget.onClose != null && listing?.path != _root)
                              IconBtn('x',
                                  tooltip: 'Close',
                                  onTap: widget.onClose),
                          ],
                  ),
                  if (!_selecting && listing != null)
                    _mobileSwitcherContext(listing),
                ],
                Expanded(
                  child: snap.connectionState == ConnectionState.waiting
                      ? Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.fg3)))
                      : snap.hasError
                          ? Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('${snap.error}',
                                      textAlign: TextAlign.center,
                                      style: sans(12, color: AppColors.fg3))))
                          : Builder(builder: (context) {
                              final entries = _visibleEntries(listing!);
                              return ListView(
                                padding: EdgeInsets.fromLTRB(
                                    M.gutter, 4, M.gutter, 16),
                                children: [
                                  if (listing.parent != null && !_selecting)
                                    _Row(
                                        icon: 'folder-open',
                                        name: '.. (parent directory)',
                                        muted: true,
                                        onTap: () => _go(listing.parent)),
                                  if (entries.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 28),
                                      child: Text('No matching files.',
                                          textAlign: TextAlign.center,
                                          style: sans(M.meta,
                                              color: AppColors.fg3)),
                                    ),
                                  ...entries.map((e) => _Row(
                                        icon: _entryIcon(e.name, e.isDir),
                                        name: e.name,
                                        git: e.git,
                                        chevron:
                                            e.isDir && kMobile && !_selecting,
                                        selecting: _selecting,
                                        selected: _selected.contains(e.path),
                                        onTap: _selecting
                                            ? () => _toggle(e)
                                            : (e.isDir
                                                ? () => _go(e.path)
                                                : () => _openFile(e)),
                                        onLongPress: () => _selecting
                                            ? _toggle(e)
                                            : _enterSelect(e),
                                      )),
                                ],
                              );
                            }),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _mobileSwitcherContext(FsListing listing) {
    final visible = _visibleEntries(listing);
    final noun = visible.length == 1 ? 'item' : 'items';
    return Padding(
      // Top inset is NOT 0. The app bar draws a divider along its bottom edge,
      // and with no inset the path row started ~3dp under it — the text read as
      // touching the rule above it rather than sitting below it.
      padding: EdgeInsets.fromLTRB(M.gutter, 10, M.gutter, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Row(children: [
            AppIcon('folder', size: 14, color: AppColors.fg4),
            const SizedBox(width: 7),
            Expanded(
              child: Text(listing.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(M.monoMeta, color: AppColors.fg3)),
            ),
            const SizedBox(width: 8),
            Text('${visible.length} $noun',
                style: sans(M.meta, tabular: true, color: AppColors.fg3)),
          ]),
        ),
        Container(
          height: M.minTarget,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(children: [
            AppIcon('search', size: 17, color: AppColors.fg4),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _filterCtl,
                autofocus: false,
                onChanged: (value) => setState(() => _filter = value),
                style: sans(M.rowTitle, color: AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Filter files',
                  hintStyle: sans(M.rowTitle, color: AppColors.fg4),
                ),
              ),
            ),
            if (_filter.isNotEmpty)
              IconBtn('x', size: 32, iconSize: 14, tooltip: 'Clear filter',
                  onTap: () {
                _filterCtl.clear();
                setState(() => _filter = '');
              }),
          ]),
        ),
      ]),
    );
  }

  static String _entryIcon(String name, bool isDir) {
    if (isDir) return 'folder';
    final l = name.toLowerCase();
    if (l.endsWith('.rs') ||
        l.endsWith('.dart') ||
        l.endsWith('.py') ||
        l.endsWith('.js') ||
        l.endsWith('.ts') ||
        l.endsWith('.tsx') ||
        l.endsWith('.jsx') ||
        l.endsWith('.go') ||
        l.endsWith('.c') ||
        l.endsWith('.cpp') ||
        l.endsWith('.h') ||
        l.endsWith('.sh') ||
        l.endsWith('.html') ||
        l.endsWith('.css')) {
      return 'code';
    }
    if (l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.webp') ||
        l.endsWith('.svg') ||
        l.endsWith('.gif') ||
        l.endsWith('.bmp') ||
        l.endsWith('.heic') ||
        l.endsWith('.heif') ||
        l.endsWith('.avif')) {
      return 'image';
    }
    // Media get their own glyphs so a folder full of clips is scannable, and so
    // the row reads as "this plays" rather than as an unknown file.
    if (l.endsWith('.mp4') ||
        l.endsWith('.m4v') ||
        l.endsWith('.mov') ||
        l.endsWith('.webm') ||
        l.endsWith('.mkv') ||
        l.endsWith('.avi')) {
      return 'film';
    }
    if (l.endsWith('.mp3') ||
        l.endsWith('.m4a') ||
        l.endsWith('.wav') ||
        l.endsWith('.ogg') ||
        l.endsWith('.flac') ||
        l.endsWith('.aac')) {
      return 'music';
    }
    if (l.endsWith('.pdf')) return 'pdf';
    if (l.endsWith('.json') ||
        l.endsWith('.toml') ||
        l.endsWith('.yaml') ||
        l.endsWith('.yml') ||
        l.endsWith('.lock') ||
        l.endsWith('.env')) {
      return 'settings';
    }
    // `file`, not the arbitrary `file-text` this used to return: that name has no
    // case in the icon map, so every unrecognised file rendered as the map's
    // generic fallback circle instead of a document.
    return 'file';
  }
}

class _FileActionRow extends StatelessWidget {
  const _FileActionRow({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: SizedBox(
              height: M.minTarget,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(children: [
                  AppIcon(icon, size: 16, color: AppColors.fg3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: sans(M.rowTitle, color: AppColors.fg1)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final String icon, name;
  final bool git, muted, chevron, selecting, selected;
  final VoidCallback? onTap, onLongPress;
  const _Row({
    required this.icon,
    required this.name,
    this.git = false,
    this.muted = false,
    this.chevron = false,
    this.selecting = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final isFolder = icon == 'folder' || icon == 'folder-open';
    // One tone for files and folders, and a sans label — matching the desktop
    // file tree. Mono made the phone listing read as a terminal dump, and a
    // brighter folder invented a hierarchy the language does not have: colour
    // here is reserved for state, not file type. Folder glyphs stay faintly
    // distinct by icon alone, which is what the desktop panel does.
    final iconColor = AppColors.fg3;
    return Material(
      // Selection is a neutral surface step; the accent is reserved for
      // STATE. An accent-filled row among files read as an alert.
      color: selected ? AppColors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(R.sm),
        child: SizedBox(
          // A full phone touch target on mobile, the tighter desktop row
          // otherwise.
          height: kMobile ? M.rowHeight : 42,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: kMobile ? M.rowPadH : 14),
            child: Row(children: [
              if (selecting) ...[
                _checkbox(selected),
                const SizedBox(width: 11)
              ],
              AppIcon(icon, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? M.rowTitle : 13,
                          weight: isFolder && kMobile ? W.label : W.body,
                          color: muted ? AppColors.fg3 : AppColors.fg1))),
              if (git) ...[
                AppIcon('git-branch', size: 12, color: AppColors.ok),
                const SizedBox(width: 4),
                Text('git', style: mono(10, color: AppColors.fg3)),
                const SizedBox(width: 8),
              ],
              if (chevron)
                AppIcon('chevron-right', size: 16, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _checkbox(bool on) => Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? AppColors.accentFill : Colors.transparent,
          border: Border.all(
              color: on ? AppColors.accentFill : AppColors.border2, width: 1.5),
        ),
        child:
            on ? AppIcon('check', size: 12, color: AppColors.accentFg) : null,
      );
}

/// Push the file viewer as a full-screen route.
///


