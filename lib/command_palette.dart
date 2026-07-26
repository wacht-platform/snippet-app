import 'package:flutter/material.dart';

import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class PaletteCommand {
  final String icon;
  final String label;
  final String hint;
  final VoidCallback action;
  const PaletteCommand(this.icon, this.label, this.hint, this.action);
}

/// Codex-style command palette: search chats + run commands. A centered floating
/// card on desktop, a bottom sheet on mobile.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<SessionInfo> sessions,
  required void Function(SessionInfo) onOpenChat,
  required List<PaletteCommand> commands,
}) {
  final view = View.of(context);
  final desktop =
      view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
  Widget body() =>
      _Palette(sessions: sessions, onOpenChat: onOpenChat, commands: commands);
  if (desktop) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'palette',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => Align(
        alignment: const Alignment(0, -0.5),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
            child: _frame(body()),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
            opacity: c,
            child: ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(c), child: child));
      },
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: _frame(body()),
      ),
    ),
  );
}

Widget _frame(Widget child) => Material(
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

class _Palette extends StatefulWidget {
  final List<SessionInfo> sessions;
  final void Function(SessionInfo) onOpenChat;
  final List<PaletteCommand> commands;
  const _Palette(
      {required this.sessions,
      required this.onOpenChat,
      required this.commands});
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(
        () => setState(() => _q = _ctrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _proj(String folder) => lastPathSegment(folder, ifEmpty: folder);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final chats = widget.sessions
        .where((s) =>
            _q.isEmpty ||
            s.title.toLowerCase().contains(_q) ||
            s.folder.toLowerCase().contains(_q))
        .take(12)
        .toList();
    final cmds = widget.commands
        .where((c) => _q.isEmpty || c.label.toLowerCase().contains(_q))
        .toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(children: [
          AppIcon('search', size: 16, color: AppColors.fg3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              cursorColor: AppColors.accent,
              style: sans(14, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search chats or run a command',
                hintStyle: sans(14, color: AppColors.fg4),
              ),
            ),
          ),
        ]),
      ),
      Divider(height: 1, thickness: 1, color: AppColors.border),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            if (chats.isNotEmpty) ...[
              _label('Chats'),
              ...chats.map((s) => _row(
                    title: s.title.isEmpty ? '(untitled)' : s.title,
                    hint: _proj(s.folder),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpenChat(s);
                    },
                  )),
            ],
            if (cmds.isNotEmpty) ...[
              _label('Suggested'),
              ...cmds.map((c) => _row(
                    icon: c.icon,
                    title: c.label,
                    hint: c.hint,
                    onTap: () {
                      Navigator.pop(context);
                      c.action();
                    },
                  )),
            ],
            if (chats.isEmpty && cmds.isEmpty)
              Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                      child: Text('No matches',
                          style: sans(12.5, color: AppColors.fg4)))),
          ],
        ),
      ),
    ]);
  }

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: SectionLabel(t));

  Widget _row(
      {String? icon,
      required String title,
      String? hint,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            if (icon != null) ...[
              AppIcon(icon, size: 15, color: AppColors.fg2),
              SizedBox(width: 10)
            ],
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1))),
            if (hint != null) Text(hint, style: mono(11, color: AppColors.fg4)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme picker bottom sheet — a grid of colour swatches, one per preset.
// ---------------------------------------------------------------------------

/// Show a bottom-sheet grid of theme swatches. Caller typically invokes this
/// from the command palette ("Change theme" command) or settings.
Future<void> showThemePicker(BuildContext context) {
  final view = View.of(context);
  final desktop =
      view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
  final current = ThemeManager.instance.index;

  Widget body() => _ThemeGrid(currentIndex: current);

  if (desktop) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'theme',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => Align(
        alignment: const Alignment(0, -0.3),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
            child: _frame(body()),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
            opacity: c,
            child: ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(c), child: child));
      },
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: _frame(body()),
      ),
    ),
  );
}

class _ThemeGrid extends StatelessWidget {
  final int currentIndex;
  const _ThemeGrid({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            AppIcon('sliders', size: 15, color: AppColors.fg2),
            const SizedBox(width: 8),
            Text('Choose theme', style: sans(14, color: AppColors.fg1)),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: AppColors.border),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
            ),
            itemCount: allPresets.length,
            itemBuilder: (_, i) {
              final p = allPresets[i];
              final selected = i == currentIndex;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ThemeManager.instance.setIndex(i);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(R.sm),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(
                        color: selected ? p.accent : p.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        // Colour swatch circle
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: p.accent,
                            shape: BoxShape.circle,
                          ),
                          child: selected
                              ? Icon(Icons.check_rounded,
                                  size: 13, color: p.accentFg)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: p.fg1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
