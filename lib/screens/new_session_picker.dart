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
/// window width — a centered modal on desktop, a full screen on a phone — so the
/// two cannot drift apart.
///
/// Deliberately NOT a git browser. Starting a chat needs a directory and,
/// optionally, files uploaded into it; version-control affordances belong to the
/// session's own tooling, never to this picker.
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

  /// Which machine these folders live on — identity, not a switcher. The machine
  /// is settled before this screen opens.
  final String machineLabel;

  /// Start a conversation rooted at the given folder.
  final Future<void> Function(String folder) onOpenFolder;

  /// Where to open. Null means the server's home directory, which is the sane
  /// default: this screen is a FOLDER PICKER, so it must not depend on a session
  /// already being open, and it must not silently inherit one's workspace.
  final String? startPath;

  /// Absent when the host owns navigation.
  final VoidCallback? onClose;

  @override
  State<NewSessionPicker> createState() => _NewSessionPickerState();
}

class _NewSessionPickerState extends State<NewSessionPicker> {
  final TextEditingController _pathCtl = TextEditingController();
  FsListing? _listing;
  bool _loading = true;
  String? _error;
  String? _busy;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _go(widget.startPath);
  }

  @override
  void dispose() {
    _pathCtl.dispose();
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
        _pathCtl.text = res.path;
        _pathCtl.selection =
            TextSelection.collapsed(offset: _pathCtl.text.length);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _run) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Folders first, then files — the thing you can act on leads. Both stay
  /// alphabetical inside their group so a long listing stays scannable.
  List<FsEntry> get _entries {
    final all = [...?_listing?.entries];
    all.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return all;
  }

  List<FsEntry> get _dirs => [
        for (final e in _entries)
          if (e.isDir) e
      ];
  List<FsEntry> get _files => [
        for (final e in _entries)
          if (!e.isDir) e
      ];

  Future<void> _open() async {
    final path = _pathCtl.text.trim();
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

  Future<void> _upload() async {
    final dir = _listing?.path ?? _pathCtl.text.trim();
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
      if (mounted)
        setState(() => _busy = 'Uploading ${i + 1}/${files.length}…');
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
    final listing = _listing;
    final parent = listing?.parent;
    final folderName = listing == null
        ? 'this folder'
        : lastPathSegment(listing.path, ifEmpty: listing.path);

    return Material(
      // A Material ancestor is REQUIRED here, and not merely for ink: without
      // one, every Text that is not inside a nested Material falls back to
      // DefaultTextStyle.fallback(), whose yellow double underline is exactly
      // what the phone build showed. The desktop dialog supplies its own
      // Material (which is why only the phone was broken); the narrow branch of
      // presentScreen returns the child raw.
      color: AppColors.bg,
      child: SafeArea(
        // presentScreen renders edge-to-edge when narrow, so the phone's status
        // bar and gesture inset have to come from here — the header was sitting
        // underneath the clock.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (_error != null)
              Expanded(child: _errorState())
            else ...[
              _pathRow(parent),
              _openRow(folderName),
              Expanded(
                child: _loading && listing == null
                    ? const Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(kMobile ? M.gutter : 10, 6,
                            kMobile ? M.gutter : 10, 16),
                        children: [
                          if (listing != null && _entries.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 22, 12, 22),
                              child: Text('This folder is empty.',
                                  textAlign: TextAlign.center,
                                  style: sans(12.5, color: AppColors.fg4)),
                            ),
                          if (_dirs.isNotEmpty) ...[
                            _groupLabel('Folders'),
                            for (final d in _dirs) _folderRow(d),
                          ],
                          if (_files.isNotEmpty) ...[
                            _groupLabel('Files'),
                            for (final f in _files) _fileRow(f),
                          ],
                        ],
                      ),
              ),
              _footer(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? M.gutter : 16, 14, 10, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('New chat',
                    style: sans(kMobile ? 17 : 15,
                        weight: W.label, color: AppColors.fg1)),
                const SizedBox(height: 2),
                Text('Pick a folder to work in.',
                    style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
          if (widget.onClose != null)
            IconBtn('x',
                size: kMobile ? M.minTarget : 30,
                iconSize: kMobile ? 19 : 15,
                tooltip: 'Close',
                onTap: widget.onClose),
        ]),
      );

  /// Path field + up + reload.
  ///
  /// The field stays EDITABLE (typing or pasting a path is the shortest route to
  /// a deep directory), while the folder rows below cover click/tap navigation.
  Widget _pathRow(String? parent) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 16, 0, kMobile ? M.gutter : 16, 8),
        child: Row(children: [
          Expanded(
            child: Container(
              height: kMobile ? M.minTarget : 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border2),
              ),
              child: Row(children: [
                AppIcon('folder-open', size: 15, color: AppColors.fg3),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _pathCtl,
                    cursorColor: AppColors.accent,
                    style: mono(kMobile ? 12.5 : 12, color: AppColors.fg1),
                    textInputAction: TextInputAction.go,
                    onSubmitted: _go,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '~/path/to/folder',
                      hintStyle: mono(12, color: AppColors.fg4),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          // Up is a first-class action, not a decoration: it is the only way
          // back out of a directory without typing.
          IconBtn('arrow-up',
              size: kMobile ? M.minTarget : 38,
              iconSize: 17,
              tooltip: 'Parent folder',
              onTap: parent == null ? null : () => _go(parent)),
          IconBtn('refresh',
              size: kMobile ? M.minTarget : 38,
              iconSize: 17,
              tooltip: 'Reload',
              onTap: _busy != null ? null : () => _go(_listing?.path)),
        ]),
      );

  /// The primary action. Highlighted and full width so the one thing this screen
  /// is for cannot be missed.
  Widget _openRow(String folderName) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 16, 0, kMobile ? M.gutter : 16, 6),
        child: Material(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(R.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.md),
            onTap: _busy != null ? null : _open,
            child: Container(
              height: kMobile ? 50 : 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.md),
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                if (_busy != null)
                  const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 1.6))
                else
                  AppIcon('corner-down-right',
                      size: 16, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _busy ?? 'Open “$folderName”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 14 : 13,
                        weight: W.label, color: AppColors.accent),
                  ),
                ),
                Text(widget.machineLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(kMobile ? 11 : 10.5, color: AppColors.fg4)),
              ]),
            ),
          ),
        ),
      );

  Widget _groupLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(label.toUpperCase(),
            style:
                sans(10, weight: W.label, color: AppColors.fg4, spacing: 0.5)),
      );

  /// One row's shared shell: hover feedback, a real touch target, and a pointer
  /// cursor on desktop so a folder reads as clickable before it is clicked.
  Widget _rowShell({
    required String icon,
    required String name,
    required bool isDir,
    required VoidCallback? onTap,
    double? iconSize,
  }) {
    final color = isDir ? AppColors.fg1 : AppColors.fg4;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        hoverColor: AppColors.surface2,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Container(
            height: kMobile ? 46 : 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              AppIcon(icon, size: iconSize ?? (isDir ? 15 : 14), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 13.5 : 12.5, color: color)),
              ),
              // The chevron is what makes "this goes somewhere" visible; without
              // it a folder row and a file row looked identical.
              if (isDir)
                AppIcon('chevron-right', size: 14, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _folderRow(FsEntry e) => _rowShell(
        icon: 'folder',
        name: e.name,
        isDir: true,
        onTap: _busy == null ? () => _go(e.path) : null,
      );

  /// Files are listing CONTEXT (what the folder holds, and what an upload
  /// produced) — not a destination, so they get no tap target rather than
  /// pretending to be a dead button.
  Widget _fileRow(FsEntry e) => _rowShell(
        icon: 'file',
        name: e.name,
        isDir: false,
        onTap: null,
      );

  Widget _footer() => Container(
        padding: EdgeInsets.fromLTRB(
            kMobile ? M.gutter : 16, 8, kMobile ? M.gutter : 16, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              'Files are uploaded into the folder you open.',
              style: sans(11, color: AppColors.fg4),
            ),
          ),
          const SizedBox(width: 8),
          IconBtn('upload',
              size: kMobile ? M.minTarget : 36,
              iconSize: 18,
              tooltip: 'Upload files here',
              onTap: (_listing == null || _busy != null) ? null : _upload),
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
            Btn('Retry', small: true, onTap: () => _go(_pathCtl.text.trim())),
          ]),
        ),
      );
}
