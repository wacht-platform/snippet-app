import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// File Tree sidebar panel:
/// - Header: `⌄ 🗐 FILE TREE` with action buttons
/// - Workspace selector card: `[folder] Workspace ⌄`
/// - Filter input: `🔍 Filter by name...`
/// - Hierarchical file/folder tree with colored extension icons
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

  @override
  void initState() {
    super.initState();
    refresh();
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
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final wsName = widget.workspacePath.isEmpty
        ? 'Workspace'
        : lastPathSegment(widget.workspacePath, ifEmpty: 'Workspace');
    final query = _filterCtl.text.trim().toLowerCase();

    final entries = (_listing?.entries ?? const <FsEntry>[]).where((e) {
      if (query.isEmpty) return true;
      return e.name.toLowerCase().contains(query);
    }).toList();

    return Container(
      color: AppColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
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
          // Workspace selector card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                AppIcon('folder', size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    wsName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, weight: W.label, color: AppColors.fg1),
                  ),
                ),
                AppIcon('chevron-down', size: 12, color: AppColors.fg4),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Filter search field
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
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
              ],
            ),
          ),
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!,
                      style: sans(12, color: AppColors.danger),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Btn('Retry', small: true, onTap: refresh),
                ],
              ),
            )
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
            for (final e in entries)
              _FileTreeRow(
                entry: e,
                onTap: () {
                  if (e.isDir) {
                    final expanded = _expandedFolders.contains(e.path);
                    setState(() {
                      if (expanded) {
                        _expandedFolders.remove(e.path);
                      } else {
                        _expandedFolders.add(e.path);
                      }
                    });
                  } else {
                    widget.onOpenFile(e.path, e.name);
                  }
                },
              ),
        ],
      ),
    );
  }
}

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    required this.entry,
    required this.onTap,
  });

  final FsEntry entry;
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              if (entry.isDir) ...[
                AppIcon('chevron-right', size: 11, color: AppColors.fg4),
                const SizedBox(width: 4),
              ] else
                const SizedBox(width: 15),
              AppIcon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12,
                      weight: entry.isDir ? W.label : W.body,
                      color: entry.isDir ? AppColors.fg2 : AppColors.fg1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static (String, Color) _fileIconAndColor(FsEntry e) {
    if (e.isDir) {
      return ('folder', const Color(0xFF60A5FA));
    }
    final name = e.name.toLowerCase();
    if (name.endsWith('.tsx') || name.endsWith('.jsx')) {
      return ('code', const Color(0xFF38BDF8));
    }
    if (name.endsWith('.ts') || name.endsWith('.js')) {
      return ('code', const Color(0xFF60A5FA));
    }
    if (name.endsWith('.html')) {
      return ('code', const Color(0xFFF97316));
    }
    if (name.endsWith('.json')) {
      return ('code', const Color(0xFFFBBF24));
    }
    if (name.endsWith('.md')) {
      return ('file', const Color(0xFFA78BFA));
    }
    if (name.startsWith('.git')) {
      return ('git-branch', const Color(0xFFF97316));
    }
    if (name.endsWith('.rs')) {
      return ('code', const Color(0xFFF97316));
    }
    if (name.endsWith('.dart')) {
      return ('code', const Color(0xFF38BDF8));
    }
    return ('file', AppColors.fg3);
  }
}
