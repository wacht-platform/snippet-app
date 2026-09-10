import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// A recursively browsable workspace tree. Each directory is fetched only when
/// first opened, then retained while the panel stays mounted.
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
    super.dispose();
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
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
        children: [
          ShellSectionHeader(
            label: 'File Tree',
            expanded: true,
            onToggle: () {},
            actions: [
              ShellSectionAction(
                icon: 'refresh',
                tooltip: 'Refresh files',
                onTap: refresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _workspaceRow(wsName),
          const SizedBox(height: 10),
          _filterField(),
          const SizedBox(height: 12),
          if (_loading && _listing == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            _rootError()
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Text(
                query.isEmpty ? 'Empty directory' : 'No matching files',
                style: sans(12, color: AppColors.fg4),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._buildRows(entries, depth: 0, query: query),
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
          padding: EdgeInsets.fromLTRB(30 + depth * 16, 2, 8, 6),
          child: Text('Could not load folder',
              style: sans(11, color: AppColors.danger)),
        ));
      }
    }
    return rows;
  }

  Widget _workspaceRow(String wsName) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          AppIcon('folder', size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(wsName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12.5, weight: W.label, color: AppColors.fg1)),
          ),
          AppIcon('chevron-down', size: 12, color: AppColors.fg4),
        ]),
      );

  Widget _filterField() => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          AppIcon('search', size: 13, color: AppColors.fg4),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _filterCtl,
              onChanged: (_) => setState(() {}),
              style: sans(12, color: AppColors.fg1),
              decoration: InputDecoration(
                hintText: 'Filter by name...',
                hintStyle: sans(12, color: AppColors.fg4),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_filterCtl.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _filterCtl.clear()),
              child: AppIcon('x', size: 11, color: AppColors.fg4),
            ),
        ]),
      );

  Widget _rootError() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(_error!,
              style: sans(12, color: AppColors.danger),
              textAlign: TextAlign.center),
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
    final (icon, color) = _fileIconAndColor(entry);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6 + depth * 16, 5, 6, 5),
          child: Row(children: [
            if (entry.isDir) ...[
              loading
                  ? const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : AppIcon(
                      expanded ? 'chevron-down' : 'chevron-right',
                      size: 11,
                      color: hasError ? AppColors.danger : AppColors.fg4,
                    ),
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 15),
            AppIcon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12,
                      weight: entry.isDir ? W.label : W.body,
                      color: entry.isDir ? AppColors.fg2 : AppColors.fg1)),
            ),
          ]),
        ),
      ),
    );
  }

  static (String, Color) _fileIconAndColor(FsEntry entry) {
    if (entry.isDir) return ('folder', const Color(0xFF60A5FA));
    final name = entry.name.toLowerCase();
    if (name.endsWith('.tsx') || name.endsWith('.jsx')) {
      return ('code', const Color(0xFF38BDF8));
    }
    if (name.endsWith('.ts') || name.endsWith('.js')) {
      return ('code', const Color(0xFF60A5FA));
    }
    if (name.endsWith('.html') || name.endsWith('.rs')) {
      return ('code', const Color(0xFFF97316));
    }
    if (name.endsWith('.json')) return ('code', const Color(0xFFFBBF24));
    if (name.endsWith('.md')) return ('file', const Color(0xFFA78BFA));
    if (name.startsWith('.git')) return ('git-branch', const Color(0xFFF97316));
    if (name.endsWith('.dart')) return ('code', const Color(0xFF38BDF8));
    return ('file', AppColors.fg3);
  }
}
