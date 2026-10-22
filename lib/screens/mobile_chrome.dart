import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

BoxDecoration _floating(double radius) => BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: AppColors.fg1.withValues(alpha: 0.08), spreadRadius: 1),
      ],
    );

class RoundBtn extends StatelessWidget {
  const RoundBtn({
    super.key,
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.size = 44,
    this.iconSize = 19,
    this.badge = false,
  });

  final String? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool badge;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Container(
              width: size,
              height: size,
              decoration: _floating(size / 2),
              alignment: Alignment.center,
              child: Stack(clipBehavior: Clip.none, children: [
                child ?? AppIcon(icon!, size: iconSize, color: AppColors.fg2),
                if (badge)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

class MobileTopBar extends StatelessWidget {
  const MobileTopBar({
    super.key,
    required this.mission,
    required this.onMission,
    required this.onSessions,
    required this.onMenu,
    required this.onSettings,
    this.sessionsBusy = false,
    this.trailingOrb,
  });

  final Widget? trailingOrb;
  final bool mission;
  final VoidCallback onMission;
  final VoidCallback onSessions;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  final bool sessionsBusy;

  Widget _segment({
    required bool active,
    required Widget glyph,
    required String label,
    required VoidCallback onTap,
    bool dot = false,
  }) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 13),
          decoration: BoxDecoration(
            color: active ? AppColors.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              glyph,
              if (dot && !active)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                ),
            ]),
            if (active) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: sans(15, weight: W.strong, color: AppColors.fg1)),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          RoundBtn(icon: 'menu', tooltip: 'Menu', onTap: onMenu),
          if (trailingOrb != null) const SizedBox(width: 44),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: _floating(24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _segment(
                active: mission,
                label: 'Mission',
                glyph: MochiIcon(
                    color: mission ? mochiPalette.first.$2 : AppColors.fg4,
                    size: 19),
                onTap: onMission,
              ),
              const SizedBox(width: 2),
              _segment(
                active: !mission,
                label: 'Sessions',
                dot: sessionsBusy,
                glyph: AppIcon('list',
                    size: 18, color: mission ? AppColors.fg3 : AppColors.fg1),
                onTap: onSessions,
              ),
            ]),
          ),
          const Spacer(),
          if (trailingOrb != null) trailingOrb!,
          RoundBtn(icon: 'settings', tooltip: 'Settings', onTap: onSettings),
        ]),
      ),
    );
  }
}

class MobileBackBar extends StatelessWidget {
  const MobileBackBar({
    super.key,
    required this.title,
    this.onBack,
    this.subtitle,
    this.onTitleTap,
    this.trailing = const [],
    this.menu = false,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;
  final bool menu;
  final bool chevron;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final pill = onTitleTap != null || subtitle != null;
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: sans(pill ? 14.5 : 16,
                    weight: W.strong, color: AppColors.fg1)),
          ),
          if (chevron) ...[
            const SizedBox(width: 4),
            AppIcon('chevron-down', size: 14, color: AppColors.fg3),
          ],
        ]),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11.5, color: AppColors.fg3)),
          ),
      ],
    );
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          if (onBack == null && trailing.isNotEmpty)
            const SizedBox(width: 44)
          else if (onBack != null)
            RoundBtn(
                icon: menu ? 'menu' : 'chevron-left',
                tooltip: menu ? 'Menu' : 'Back',
                onTap: onBack),
          if (trailing.length == 2) const SizedBox(width: 44),
          if (onBack != null || trailing.isNotEmpty) const SizedBox(width: 10),
          Expanded(
            child: pill
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTitleTap,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: _floating(22),
                      alignment: Alignment.center,
                      child: label,
                    ),
                  )
                : Center(child: label),
          ),
          if (onBack != null || trailing.isNotEmpty) ...[
            const SizedBox(width: 10),
            if (trailing.isEmpty) const SizedBox(width: 44) else ...trailing,
          ],
        ]),
      ),
    );
  }
}

class FloatingSearch extends StatelessWidget {
  const FloatingSearch({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Container(
        height: 50,
        decoration: _floating(25),
        padding: const EdgeInsets.only(left: 18, right: 8),
        child: Row(children: [
          AppIcon('search', size: 17, color: AppColors.fg4),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: sans(16, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: sans(16, color: AppColors.fg4),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox(width: 8)
                : IconBtn('x',
                    size: 36,
                    iconSize: 16,
                    tooltip: 'Clear',
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    }),
          ),
        ]),
      );
}

class AccentFab extends StatelessWidget {
  const AccentFab(
      {super.key, required this.tooltip, required this.onTap, this.icon = 'plus'});

  final String tooltip;
  final VoidCallback onTap;
  final String icon;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: AppColors.accentFill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 21, color: AppColors.accentFg),
            ),
          ),
        ),
      );
}

class BottomFade extends StatelessWidget {
  const BottomFade({super.key, this.height = 130});

  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg],
              stops: const [0, 0.6],
            ),
          ),
        ),
      );
}

enum MobileMenuPick { newSession, tasks, agents, usage, ambient, machines }

Future<void> showMobileMenu(
  BuildContext context, {
  required DaemonClient? client,
  required String newSessionSubtitle,
  required void Function(MobileMenuPick pick) onPick,
  required void Function(CoordinationAgent agent) onAgent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion,
    builder: (sheet) => _MobileMenu(
      client: client,
      newSessionSubtitle: newSessionSubtitle,
      onPick: (p) {
        Navigator.pop(sheet);
        onPick(p);
      },
      onAgent: (a) {
        Navigator.pop(sheet);
        onAgent(a);
      },
    ),
  );
}

class _MobileMenu extends StatefulWidget {
  const _MobileMenu({
    required this.client,
    required this.newSessionSubtitle,
    required this.onPick,
    required this.onAgent,
  });

  final DaemonClient? client;
  final String newSessionSubtitle;
  final ValueChanged<MobileMenuPick> onPick;
  final ValueChanged<CoordinationAgent> onAgent;

  @override
  State<_MobileMenu> createState() => _MobileMenuState();
}

class _MobileMenuState extends State<_MobileMenu> {
  List<CoordinationAgent>? _agents;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    if (c != null) {
      c.coordinationAgents().then((a) {
        if (mounted) {
          setState(() => _agents =
              a.where((x) => !x.isMissionControl).toList());
        }
      }).catchError((_) {
        if (mounted) setState(() => _agents = const []);
      });
    }
  }

  Widget _row(String icon, String label, MobileMenuPick pick) => InkWell(
        onTap: () => widget.onPick(pick),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(children: [
              AppIcon(icon, size: 20, color: AppColors.fg2),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(label, style: sans(16, color: AppColors.fg1))),
              AppIcon('chevron-right', size: 13, color: AppColors.fg4),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final agents = _agents ?? const <CoordinationAgent>[];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: AppColors.fg1.withValues(alpha: 0.08), spreadRadius: 1),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.fg1.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.client != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Material(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onPick(MobileMenuPick.newSession),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: AppColors.accentFill,
                              shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: AppIcon('plus',
                              size: 18, color: AppColors.accentFg),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('New session',
                                  style: sans(16,
                                      weight: W.strong, color: AppColors.fg1)),
                              if (widget.newSessionSubtitle.isNotEmpty)
                                Text(widget.newSessionSubtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(13, color: AppColors.fg3)),
                            ],
                          ),
                        ),
                        AppIcon('chevron-right',
                            size: 13, color: AppColors.fg4),
                      ]),
                    ),
                  ),
                ),
              ),
            if (agents.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('AGENTS',
                      style: sans(12,
                          weight: W.label,
                          spacing: 0.7,
                          color: AppColors.fg4)),
                ),
              ),
              SizedBox(
                height: 82,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final a in agents)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => widget.onAgent(a),
                        child: SizedBox(
                          width: 80,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AgentMochi(a.id, size: 36),
                              const SizedBox(height: 8),
                              Text(
                                  a.displayName.isEmpty
                                      ? a.handle
                                      : a.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(13, color: AppColors.fg2)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 6),
              child: Divider(height: 1, thickness: 1, color: AppColors.line),
            ),
            if (widget.client != null) ...[
              _row('task', 'Tasks', MobileMenuPick.tasks),
              _row('agent', 'Agents', MobileMenuPick.agents),
              _row('analytics', 'Usage', MobileMenuPick.usage),
              _row('mic', 'Ambient listening', MobileMenuPick.ambient),
            ],
            _row('server', 'Machines', MobileMenuPick.machines),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }
}
