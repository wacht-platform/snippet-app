import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

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
  final TextEditingController _filterCtl = TextEditingController();
  final FocusNode _filterFocus = FocusNode();

  /// Whether the search field is revealed. Collapsed by default: at 26px rows
  /// an always-visible field spent a slab of vertical space on something used
  /// occasionally, and it competed with the tree for the eye.
  bool _searchOpen = false;
  final Set<String> _expandedFolders = {};
  final Set<String> _loadingFolders = {};
  final Map<String, List<FsEntry>> _childrenByPath = {};
  final Map<String, String> _folderErrors = {};

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

  @override
  void dispose() {
    _filterCtl.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  /// Show/hide the search field.
  ///
  /// Closing CLEARS the query: a filter that stays applied while its field is
  /// hidden leaves the tree silently missing files, with nothing on screen
  /// explaining why.
  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _filterCtl.clear();
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _filterFocus.requestFocus();
      });
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

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

  /// Where a new entry lands: the root of the tree currently on screen.
  String get _createDir => _listing?.path ?? widget.workspacePath;

  Future<void> _newFile() async {
    final name = await promptText(context,
        title: 'New file', hint: 'name, e.g. notes.md', saveLabel: 'Create');
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      // Empty content, so this creates the file rather than truncating one:
      // the daemon writes a new path, and an existing name is an explicit
      // overwrite the user just asked for.
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

  /// One '+' offering file or folder, matching the Chats header's single add
  /// action instead of spending two slots on it.
  Future<void> _openAddMenu() async {
    final choice = await showAppSheet<String>(context,
        title: 'New',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _addRow('file-plus', 'New file',
                onTap: () => Navigator.pop(context, 'file')),
            _addRow('folder-plus', 'New folder',
                onTap: () => Navigator.pop(context, 'folder')),
          ],
        ));
    if (!mounted) return;
    if (choice == 'file') await _newFile();
    if (choice == 'folder') await _newFolder();
  }

  Widget _addRow(String icon, String label, {required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
            child: Row(children: [
              AppIcon(icon, size: 16, color: AppColors.fg3),
              const SizedBox(width: 12),
              Text(label, style: sans(13.5, color: AppColors.fg1)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final wsName = widget.workspacePath.isEmpty
        ? 'Workspace'
        : lastPathSegment(widget.workspacePath, ifEmpty: 'Workspace');
    final query = _filterCtl.text.trim().toLowerCase();
    final entries = _rootEntries(query);

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
              ShellSectionAction(
                icon: 'search',
                tooltip: _searchOpen ? 'Hide search' : 'Search files',
                active: _searchOpen,
                onTap: _toggleSearch,
              ),
              // Matches the Chats header: one '+' that offers the create
              // choices, rather than two slots competing for the same idea.
              ShellSectionAction(
                icon: 'plus',
                tooltip: 'New file or folder',
                onTap: _listing == null ? null : _openAddMenu,
              ),
              ShellSectionAction(
                icon: 'refresh',
                tooltip: 'Refresh files',
                onTap: refresh,
              ),
            ],
          ),
          _workspaceRow(wsName),
          // Collapsible: the field is only present while searching, so the tree
          // gets the full column the rest of the time. AnimatedSize keeps the
          // reveal from snapping the whole list.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _searchOpen
                ? _filterField()
                : const SizedBox(width: double.infinity),
          ),
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
              child: Text(
                query.isEmpty ? 'Empty directory' : 'No matching files',
                style: sans(12.5, color: AppColors.fg4),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            ..._buildRows(entries, depth: 0, query: query),
          ],
        ],
      ),
    );
  }

  List<FsEntry> _rootEntries(String query) {
    final entries = _listing?.entries ?? const <FsEntry>[];
    if (query.isEmpty) return entries;
    return entries.where((entry) => _matchesFilter(entry, query)).toList();
  }

  bool _matchesFilter(FsEntry entry, String query) {
    if (entry.name.toLowerCase().contains(query)) return true;
    return entry.isDir &&
        (_childrenByPath[entry.path] ?? const <FsEntry>[])
            .any((child) => _matchesFilter(child, query));
  }

  List<Widget> _buildRows(
    List<FsEntry> entries, {
    required int depth,
    required String query,
  }) {
    final rows = <Widget>[];
    for (final entry in entries) {
      final expanded = _expandedFolders.contains(entry.path);
      final children = _childrenByPath[entry.path] ?? const <FsEntry>[];
      final showChildren = entry.isDir && (expanded || query.isNotEmpty);
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
      if (showChildren && children.isNotEmpty) {
        final visible = query.isEmpty
            ? children
            : children.where((child) => _matchesFilter(child, query)).toList();
        rows.addAll(_buildRows(visible, depth: depth + 1, query: query));
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

  /// Filter field: a full-height input, not a hairline strip.
  ///
  /// 44px with a 16px glyph, matching the phone's Chats search field. The old
  /// 32px / 14px version read as a decorative rule rather than something you can
  /// type into — which is exactly what "thin" described.
  Widget _filterField() => Padding(
        padding: const EdgeInsets.fromLTRB(
            kSidebarContentInset, 6, kSidebarContentInset, 6),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            AppIcon('search', size: 16, color: AppColors.fg4),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _filterCtl,
                focusNode: _filterFocus,
                onChanged: (_) => setState(() {}),
                cursorColor: AppColors.fg1,
                style: sans(13.5, color: AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search this folder...',
                  hintStyle: sans(13.5, color: AppColors.fg4),
                ),
              ),
            ),
            if (_filterCtl.text.isNotEmpty)
              IconBtn('x',
                  size: 24,
                  iconSize: 13,
                  tooltip: 'Clear',
                  onTap: () => setState(() => _filterCtl.clear())),
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
