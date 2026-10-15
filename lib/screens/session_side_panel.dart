import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_tree_sidebar_panel.dart';
import 'session.dart' show TerminalHost;
import 'shell_nav.dart';

class SessionSidePanel extends StatefulWidget {
  const SessionSidePanel({
    super.key,
    required this.client,
    required this.workspacePath,
    required this.onOpenFile,
    this.host,
  });

  final DaemonClient client;
  final String workspacePath;
  final void Function(String path, String name) onOpenFile;
  final TerminalHost? host;

  @override
  State<SessionSidePanel> createState() => _SessionSidePanelState();
}

class _SessionSidePanelState extends State<SessionSidePanel> {
  static bool _termsOpen = true;
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
              : FileTreeSidebarPanel(
                  key: ValueKey('files-${widget.workspacePath}'),
                  client: widget.client,
                  workspacePath: widget.workspacePath,
                  onOpenFile: widget.onOpenFile,
                ),
        ),
        Container(height: 1, color: AppColors.border),
        header,
        if (open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (var i = 0; i < terms.length; i++)
                  ShellNavRow(
                    id: terms[i].id,
                    indent: _rowInset,
                    label: terms[i].title,
                    icon: 'terminal',
                    tone: ShellTone.neutral,
                    selected: i == host!.focus,
                    onTap: () => host.focusTerm(terms[i].id),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (terms[i].alive) ...[
                        const StatusDot(status: 'online', size: 7),
                        const SizedBox(width: 6),
                      ],
                      GestureDetector(
                        onTap: () => host.closeTerm(terms[i].id),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: AppIcon('x', size: 12, color: AppColors.fg4),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
