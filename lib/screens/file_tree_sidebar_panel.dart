import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';

/// Nesting step for a tree level.
///
/// Measured: a top-level row box sits at x8 and its child at x29 — 21px, not the
/// 20px a round number suggests. That 1px compounds on deep trees, so it is kept
/// exact.
const double kTreeIndentStep = 21;

/// A recursively browsable workspace tree. Each directory is fetched only when
/// first opened, then retained while the panel stays mounted.
///
/// Structure follows the measured reference panel: 26px rows with 12px inner
/// padding, nesting in 20px steps, and a muted filter field inset one surface
/// step into the panel.
///
/// Icons are deliberately monochrome. The previous per-extension palette (six
/// hues across .ts/.tsx/.json/.md/.rs/.dart) made a long listing read as noise;
/// in this shell colour is reserved for state, not file type.
class FileTreeSidebarPanel extends StatefulWidget {
  const FileTreeSidebarPanel({
    super.key,
    required this.client,
    required this.workspacePath,
    required this.onOpenFile,
  });

  final DaemonClient client;
  final String workspacePath;
  final void Function(String path, String name) onOpenFile;

  @override
  State<FileTreeSidebarPanel> createState() => _FileTreeSidebarPanelState();
}

class _FileTreeSidebarPanelState extends State<FileTreeSidebarPanel> {
  FsListing? _listing;
  bool _loading = true;
  String? _error;
  final Set<String> _expandedFolders = {};
  final Set<String> _loadingFolders = {};
  final Map<String, List<FsEntry>> _childrenByPath = {};
  final Map<String, String> _folderErrors = {};

  /// True while an upload is in flight. Guards the header action so a second
  /// tap cannot start an overlapping batch, and drives the icon's spinner.
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(covariant FileTreeSidebarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.client != widget.client) {
      _expandedFolders.clear();
      _loadingFolders.clear();
      _childrenByPath.clear();
      _folderErrors.clear();
      refresh();
    }
  }

  /// Search opens as a POPOVER anchored under its button, not a centered dialog.
  ///
  /// An inline field would spend a slab of the panel's height on something used
  /// occasionally and push the tree down; a dialog takes over the whole window
  /// and puts the results nowhere near the control that asked for them.
  Future<void> _openFileSearch(BuildContext anchor) => showFileSearchDialog(
        context,
        anchor: anchor,
        client: widget.client,
        root: widget.workspacePath,
        onOpen: widget.onOpenFile,
      );

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.client.fs(
        widget.workspacePath.isEmpty ? null : widget.workspacePath,
      );
      if (!mounted) return;
      setState(() {
        _listing = res;
        _childrenByPath.clear();
        _folderErrors.clear();
        _expandedFolders.clear();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFolder(FsEntry entry) async {
    if (!entry.isDir) return;
    final path = entry.path;
    if (_expandedFolders.contains(path)) {
      setState(() => _expandedFolders.remove(path));
      return;
    }

    setState(() {
      _expandedFolders.add(path);
      _folderErrors.remove(path);
    });
    if (_childrenByPath.containsKey(path)) return;

    setState(() => _loadingFolders.add(path));
    try {
      final listing = await widget.client.fs(path);
      if (!mounted) return;
      setState(() => _childrenByPath[path] = listing.entries);
    } catch (e) {
      if (mounted) setState(() => _folderErrors[path] = '$e');
    } finally {
      if (mounted) setState(() => _loadingFolders.remove(path));
    }
  }

  String get _createDir => _listing?.path ?? widget.workspacePath;

  Future<void> _newFile() async {
    final name = await promptText(context,
        title: 'New file', hint: 'name, e.g. notes.md', saveLabel: 'Create');
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      await widget.client.writeFile('$_createDir/$trimmed', '');
      if (!mounted) return;
      await refresh();
      if (mounted) toast(context, 'Created $trimmed');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _newFolder() async {
    final name = await promptText(context,
        title: 'New folder', hint: 'folder name', saveLabel: 'Create');
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      await widget.client.mkdir('$_createDir/$trimmed');
      if (!mounted) return;
      await refresh();
      if (mounted) toast(context, 'Created $trimmed');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  /// Upload files from this machine into the folder being browsed.
  ///
  /// Lands in the directory currently LISTED (`_createDir`), so an upload goes
  /// where you are looking rather than always to the workspace root.
  Future<void> _uploadFiles() async {
    if (_uploading) return;
    List<PickedLocalFile> picked;
    try {
      picked = await pickLocalFiles();
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not open the file picker: $e', danger: true);
      }
      return;
    }
    if (picked.isEmpty || !mounted) return;

    // Capture the destination ONCE: `_createDir` is derived from the listing,
    // and the listing is refreshed below, so reading it per iteration could send
    // later files somewhere else mid-upload.
    final dir = _createDir;
    setState(() => _uploading = true);
    var uploaded = 0;
    try {
      for (final f in picked) {
        try {
          await widget.client
              .uploadFile(await f.readAsBytes(), name: f.name, dir: dir);
          uploaded++;
        } catch (e) {
          if (mounted) toast(context, '${f.name}: $e', danger: true);
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    if (!mounted) return;
    if (uploaded > 0) {
      await refresh();
      if (mounted) {
        toast(context, 'Uploaded $uploaded file${uploaded == 1 ? '' : 's'}');
      }
    }
  }

  /// The "+" menu, anchored under its own button.
  ///
  /// This was a modal sheet — a full barrier and a centered card for two items,
  /// which read as leaving the panel rather than adding to it. `below` because
  /// the button sits at the top of the window, `alignEnd` because it is at the
  /// right end of the header.
  Future<void> _openAddMenu(BuildContext anchor) async {
    final choice = await showAppMenu<String>(
      context,
      anchor: anchor,
      below: true,
      alignEnd: true,
      minWidth: 200,
      maxWidth: 240,
      items: [
        appMenuItem(
          value: 'file',
          label: 'New file',
          icon: 'file-plus',
          height: 36,
        ),
        appMenuItem(
          value: 'folder',
          label: 'New folder',
          icon: 'folder-plus',
          height: 36,
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'file') await _newFile();
    if (choice == 'folder') await _newFolder();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final wsName = widget.workspacePath.isEmpty
        ? 'Workspace'
        : lastPathSegment(widget.workspacePath, ifEmpty: 'Workspace');
    final entries = _listing?.entries ?? const <FsEntry>[];

    return Container(
      color: AppColors.bg,
      child: ListView(
        // Horizontal insets belong to each child (the section header carries
        // its own), so the list itself only manages the top and tail.
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          ShellSectionHeader(
            label: 'File Tree',
            actions: [
              // `Builder` gives each menu a context that anchors to its OWN
              // button: `Element.findRenderObject` walks DOWN to the button's
              // box, so the popover opens under the control that summoned it
              // rather than at the panel's corner.
              Builder(
                builder: (ctx) => ShellSectionAction(
                  icon: 'search',
                  tooltip: 'Search files',
                  onTap: () => _openFileSearch(ctx),
                ),
              ),
              Builder(
                builder: (ctx) => ShellSectionAction(
                  icon: 'upload',
                  tooltip: 'Upload files',
                  // Enabled before the first listing arrives: `_createDir` falls
                  // back to the workspace root, so an upload is valid even while
                  // the tree is still loading. Tinted while busy — accent is the
                  // state channel, and "uploading" is a state.
                  active: _uploading,
                  onTap: _uploading ? null : _uploadFiles,
                ),
              ),
              Builder(
                builder: (ctx) => ShellSectionAction(
                  icon: 'plus',
                  tooltip: 'New file or folder',
                  onTap: _listing == null ? null : () => _openAddMenu(ctx),
                ),
              ),
            ],
          ),
          _workspaceRow(wsName),
          if (_loading && _listing == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            _rootError()
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Text('Empty directory',
                  style: sans(12.5, color: AppColors.fg4)),
            )
          else ...[
            const SizedBox(height: 4),
            ..._buildRows(entries, depth: 0),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildRows(
    List<FsEntry> entries, {
    required int depth,
  }) {
    final rows = <Widget>[];
    for (final entry in entries) {
      final expanded = _expandedFolders.contains(entry.path);
      final children = _childrenByPath[entry.path] ?? const <FsEntry>[];
      rows.add(_FileTreeRow(
        entry: entry,
        depth: depth,
        expanded: expanded,
        loading: _loadingFolders.contains(entry.path),
        hasError: _folderErrors.containsKey(entry.path),
        onTap: () => entry.isDir
            ? _toggleFolder(entry)
            : widget.onOpenFile(entry.path, entry.name),
      ));
      if (expanded && children.isNotEmpty) {
        rows.addAll(_buildRows(children, depth: depth + 1));
      }
      if (expanded && _folderErrors.containsKey(entry.path)) {
        rows.add(Padding(
          padding: EdgeInsets.only(
              left: kSidebarContentInset +
                  kNavPadH +
                  (depth + 1) * kTreeIndentStep,
              right: kSidebarContentInset,
              top: 2,
              bottom: 6),
          child: Text('Could not load folder',
              style: sans(11, color: AppColors.danger)),
        ));
      }
    }
    return rows;
  }

  /// Workspace selector: a flat 32px row, not a bordered card. The reference
  /// keeps this level quiet — the tree below it is the content.
  Widget _workspaceRow(String wsName) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
          child: Row(children: [
            AppIcon('folder-open', size: 14, color: AppColors.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(wsName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
            ),
            AppIcon('chevron-down', size: 12, color: AppColors.fg4),
          ]),
        ),
      );

  Widget _rootError() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_error!,
              style: sans(12.5, color: AppColors.danger, height: 1.4)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: refresh),
        ]),
      );
}

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    required this.entry,
    required this.depth,
    required this.expanded,
    required this.loading,
    required this.hasError,
    required this.onTap,
  });

  final FsEntry entry;
  final int depth;
  final bool expanded;
  final bool loading;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Folders and files share ONE tone: measured labels are #C1C1C1 for both
    // (`Src` is white only because it is the selected row). Tinting directories
    // brighter invented a hierarchy the reference does not have.
    final color = AppColors.fg2;
    return Padding(
      padding: EdgeInsets.only(
        left: kSidebarContentInset + depth * kTreeIndentStep,
        right: kSidebarContentInset,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            height: kNavRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
            child: Row(children: [
              // Fixed chevron column so names align whether or not a row can be
              // expanded — a file must not shift left against its siblings.
              //
              // SQUARE, and the spinner is CENTERED inside it. A width-only
              // `SizedBox(width: 16)` hands its child a TIGHT width of 16, so an
              // inner `SizedBox(width: 11)` is enforced against minWidth=16 and
              // the spinner renders 16 wide x 11 tall — a flattened oval.
              // Center gives the child loose constraints instead, so it stays
              // circular.
              SizedBox(
                width: 16,
                height: 16,
                child: entry.isDir
                    ? (loading
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 11,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          )
                        : AppIcon(
                            expanded ? 'chevron-down' : 'chevron-right',
                            size: 12,
                            color: hasError ? AppColors.danger : AppColors.fg4,
                          ))
                    : null,
              ),
              const SizedBox(width: 4),
              AppIcon(
                entry.isDir ? (expanded ? 'folder-open' : 'folder') : 'file',
                size: 14,
                color: hasError ? AppColors.danger : color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg2)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File search popover.
// ---------------------------------------------------------------------------

/// One matched file.
class _FileHit {
  final String name;
  final String path;
  const _FileHit(this.name, this.path);
}

/// File search: a popover anchored under its button on desktop, a bottom sheet
/// on mobile.
///
/// Anchored rather than centered so the results appear at the control that asked
/// for them, matching every other desktop popover in the shell. Matches come
/// from a bounded walk of the workspace, cached for the lifetime of the popover
/// so typing filters locally instead of re-fetching the tree on every keystroke.
Future<void> showFileSearchDialog(
  BuildContext context, {
  /// The control this popover belongs to. Desktop anchors to it; without one
  /// (or if it has no box) the popover falls back to the window's top-left.
  BuildContext? anchor,
  required DaemonClient client,
  required String root,
  required void Function(String path, String name) onOpen,
}) {
  final view = View.of(context);
  final desktop =
      view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
  Widget body() => _FileSearch(client: client, root: root, onOpen: onOpen);
  if (desktop) {
    // Sized to the sidebar it belongs to, not a wide centered card. This is a
    // popover on a sidebar control: 640px of centered card dwarfed the panel,
    // and even a 380px column overhung it. Basing the width on `kSidebarWidth`
    // keeps the popover inside the very column whose button opened it — and it
    // still fits the narrower compact-window drawer, whose minimum is 280.
    final width = kSidebarWidth - 24;
    final screen = MediaQuery.sizeOf(context);
    var left = 16.0;
    var top = 96.0;
    final box = anchor?.findRenderObject() as RenderBox?;
    if (box != null) {
      final origin = box.localToGlobal(Offset.zero);
      // Right-aligned to the button (both actions sit at the header's right
      // end), and clamped so it can never leave the window.
      left = (origin.dx + box.size.width - width).clamp(
          12.0, (screen.width - width - 12).clamp(12.0, double.infinity));
      top = origin.dy + box.size.height + 6;
    }
    // Capped well below the window: at the previous 460px this could fill most
    // of a laptop viewport, which is the opposite of a compact popover. With the
    // 26px result rows this shows roughly ten matches, and the list scrolls past
    // that rather than growing the card.
    final maxHeight = (screen.height - top - 16).clamp(200.0, 340.0);
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'file search',
      // Transparent: this is a popover beside the panel, not a modal over it.
      // A dimmed barrier would black out the tree you are searching.
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _fileSearchFrame(body()),
          ),
        ),
      ]),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(
            // Grows from its top-right, i.e. out of the button it is anchored to.
            alignment: Alignment.topRight,
            scale: Tween(begin: 0.97, end: 1.0).animate(c),
            child: child,
          ),
        );
      },
    );
  }
  return showModalBottomSheet(
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
          child: _fileSearchFrame(body()),
        ),
      );
    },
  );
}

Widget _fileSearchFrame(Widget child) => Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(R.card),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border2)),
        child: child,
      ),
    );

class _FileSearch extends StatefulWidget {
  const _FileSearch(
      {required this.client, required this.root, required this.onOpen});
  final DaemonClient client;
  final String root;
  final void Function(String path, String name) onOpen;
  @override
  State<_FileSearch> createState() => _FileSearchState();
}

class _FileSearchState extends State<_FileSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  /// True while the ONE crawl is running.
  ///
  /// Deliberately not tied to the query. An earlier version guarded the walk
  /// with a run id bumped per query, so every keystroke aborted the crawl
  /// in flight — and because the result is CACHED, the index stayed truncated
  /// for the life of the popover and later searches silently missed files.
  /// Typing now filters what has already arrived; the crawl runs to completion
  /// on its own.
  bool _crawling = false;

  /// Every file discovered by the crawl. Null until it has been started, so
  /// opening the popover does not crawl the whole tree.
  List<_FileHit>? _all;

  List<_FileHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQuery() {
    // Filter against what the crawl has ALREADY found, so typing is instant even
    // mid-walk, then debounce the START of the crawl (once).
    _applyFilter();
    if (_all != null || _crawling) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _startCrawl);
  }

  /// Filter whatever `_all` currently holds against the live query.
  void _applyFilter() {
    final q = _ctrl.text.trim().toLowerCase();
    final all = _all;
    final next = (q.isEmpty || all == null)
        ? const <_FileHit>[]
        : all.where((h) => h.name.toLowerCase().contains(q)).take(80).toList();
    if (mounted) setState(() => _hits = next);
  }

  /// Crawl the workspace ONCE, to completion.
  ///
  /// Bounded so a huge repo (or a slow tunnel) cannot hang the popover.
  Future<void> _startCrawl() async {
    if (_crawling || _all != null) return;
    setState(() => _crawling = true);

    final all = <_FileHit>[];
    var wave = <String>[widget.root];
    var dirs = 0;
    var visited = 0;
    const maxDirs = 200;
    const maxEntries = 6000;
    // Directories fetched at once. High enough that a real repo finishes in a
    // few rounds, low enough not to flood the daemon (or a tunnel).
    const maxConcurrent = 24;

    // Breadth-first, one LEVEL per round, each round fired CONCURRENTLY.
    //
    // This used to await one directory at a time, so a 200-directory workspace
    // cost 200 sequential round trips — the whole reason search felt slow. That
    // is latency-bound rather than CPU-bound, so overlapping the requests is the
    // fix rather than a faster walk.
    while (wave.isNotEmpty && dirs < maxDirs && visited < maxEntries) {
      final batch = wave.take(maxConcurrent).toList();
      wave = wave.skip(batch.length).toList();
      dirs += batch.length;

      final listings = await Future.wait(batch.map((dir) async {
        try {
          return await widget.client.fs(dir.isEmpty ? null : dir);
        } catch (_) {
          // One unreadable directory must not abort the whole walk.
          return null;
        }
      }));
      if (!mounted) return;

      var grew = false;
      for (final listing in listings) {
        if (listing == null) continue;
        visited += listing.entries.length;
        for (final e in listing.entries) {
          if (e.isDir) {
            wave.add(e.path);
          } else {
            all.add(_FileHit(e.name, e.path));
            grew = true;
          }
        }
      }

      // Publish each completed round, so matches appear while it is still
      // walking instead of only at the end.
      if (grew) {
        _all = all;
        _applyFilter();
      }
    }

    if (!mounted) return;
    _all = all;
    setState(() => _crawling = false);
    _applyFilter();
  }

  String _dirLabel(String path) {
    final i = path.lastIndexOf('/');
    if (i <= 0) return '';
    final dir = path.substring(0, i);
    return lastPathSegment(dir, ifEmpty: dir);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final typed = _ctrl.text.trim();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Compact header. The previous 14/12/10 padding around a 14px field made
      // the search row taller than any row in the panel it opens from.
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        child: Row(children: [
          AppIcon('search', size: 14, color: AppColors.fg4),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              cursorColor: AppColors.accent,
              style: sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search files',
                hintStyle: sans(13, color: AppColors.fg4),
              ),
            ),
          ),
          if (_crawling)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5)),
        ]),
      ),
      // A sub-pixel seam, not a drawn rule. The language separates by surface
      // step and hairline; a 1px `Divider` made this popover read heavier than
      // the panel it belongs to. Same token the pane strips use.
      Container(height: kPaneHairline, color: kPaneSeamColor),
      Flexible(
        child: typed.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                    child: Text('Type to search the workspace',
                        style: sans(12, color: AppColors.fg4))),
              )
            : (_hits.isEmpty && !_crawling
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                        child: Text('No matching files',
                            style: sans(12, color: AppColors.fg4))),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [for (final h in _hits) _row(h)],
                  )),
      ),
    ]);
  }

  /// One result, at the sidebar's own row height (26px) so the list matches the
  /// tree it is searching rather than reading as a separate, roomier surface.
  Widget _row(_FileHit h) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            widget.onOpen(h.path, h.name);
          },
          child: Container(
            height: kNavRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              AppIcon('file', size: 13, color: AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(h.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, color: AppColors.fg1))),
              Text(_dirLabel(h.path), style: mono(10, color: AppColors.fg4)),
            ]),
          ),
        ),
      );
}
