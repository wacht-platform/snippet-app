import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart';
import 'git_diff_sidebar_panel.dart';
import '../models.dart' show GitFile;
import 'session.dart' show TerminalHost;
import 'shell_nav.dart';

class SessionSidePanel extends StatefulWidget {
  const SessionSidePanel({
    super.key,
    required this.client,
    required this.workspacePath,
    required this.onOpenFile,
    this.host,
    this.sessionId,
    this.onOpenDiff,
  });

  final String? sessionId;
  final void Function(GitFile file)? onOpenDiff;

  final DaemonClient client;
  final String workspacePath;
  final void Function(String path, String name) onOpenFile;
  final TerminalHost? host;

  @override
  State<SessionSidePanel> createState() => _SessionSidePanelState();
}

class _SessionSidePanelState extends State<SessionSidePanel> {
  static bool _termsOpen = true;
  static bool _changes = false;

  Widget _segs() => Row(children: [
        _seg('Files', !_changes, () => setState(() => _changes = false)),
        _seg('Changes', _changes, () => setState(() => _changes = true)),
      ]);

  Widget _seg(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Material(
          color: on ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(label,
                  style: sans(12.5, color: on ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );
  static const _rowInset = 12.0 + 13 + 6;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final terms = host?.terms ?? const [];
    final open = _termsOpen && terms.isNotEmpty;
    final header = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: terms.isEmpty ? null : () => setState(() => _termsOpen = !open),
        child: Container(
          height: 38,
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          child: Row(children: [
            AppIcon(open ? 'chevron-down' : 'chevron-right',
                size: 13, color: AppColors.fg3),
            const SizedBox(width: 6),
            Text('Terminals', style: sans(13, color: AppColors.fg3)),
            if (terms.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('${terms.length}',
                  style: sans(11.5, color: AppColors.fg4, tabular: true)),
            ],
            const Spacer(),
            ShellSectionAction(
              small: true,
              icon: 'plus',
              tooltip: 'New terminal',
              onTap: host == null
                  ? null
                  : () {
                      setState(() => _termsOpen = true);
                      host.newTerminal();
                    },
            ),
          ]),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: widget.workspacePath.isEmpty
              ? const SizedBox()
              : _changes
              ? GitDiffSidebarPanel(
                  key: ValueKey('git-${widget.workspacePath}'),
                  client: widget.client,
                  workspacePath: widget.workspacePath,
                  sessionId: widget.sessionId,
                  onOpenDiff: widget.onOpenDiff,
                  header: _segs(),
                )
              : FileTreeSidebarPanel(
                  key: ValueKey('files-${widget.workspacePath}'),
                  client: widget.client,
                  workspacePath: widget.workspacePath,
                  onOpenFile: widget.onOpenFile,
                  header: _segs(),
                ),
        ),
        Container(height: 1, color: AppColors.border),
        header,
        if (open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Stack(children: [
                Positioned(
                  left: 18,
                  top: 0,
                  bottom: 4,
                  child: Container(width: 1, color: AppColors.border),
                ),
                Column(children: [
                  for (var i = 0; i < terms.length; i++)
                    _TermTreeRow(
                      title: terms[i].title,
                      alive: terms[i].alive,
                      selected: i == host!.focus,
                      onTap: () => host.focusTerm(terms[i].id),
                      onClose: () => host.closeTerm(terms[i].id),
                    ),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

class _TermTreeRow extends StatefulWidget {
  const _TermTreeRow({
    required this.title,
    required this.alive,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool alive;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TermTreeRow> createState() => _TermTreeRowState();
}

class _TermTreeRowState extends State<_TermTreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(
          left: _SessionSidePanelState._rowInset - 6,
          right: kSidebarContentInset),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: kNavRowHeight,
            padding: const EdgeInsets.only(left: 6, right: 4),
            decoration: BoxDecoration(
              color: on || _hover ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(children: [
              AppIcon('terminal',
                  size: 14, color: on ? AppColors.fg1 : AppColors.fg3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: on ? AppColors.fg1 : AppColors.fg2)),
              ),
              if (widget.alive && !_hover)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: StatusDot(status: 'online', size: 6),
                ),
              if (_hover)
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: AppIcon('x', size: 11, color: AppColors.fg3),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
