import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'dialog_widgets.dart';
import 'screens/mochi_color_picker.dart';
import 'crew_status.dart';
import 'mochi.dart';
import 'models.dart';
import 'notifications.dart' show onNotifTap;
import 'platform.dart';
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

Color crewColor(CrewState s) => switch (s) {
      CrewState.needsYou => AppColors.run,
      CrewState.working => AppColors.accent,
      CrewState.standingBy => AppColors.fg4,
    };

class CrewTile extends StatelessWidget {
  const CrewTile(this.entry, {super.key, this.size = 34});
  final CrewEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = crewColor(entry.state);
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(size * .29),
            border: Border.all(
                color: entry.state == CrewState.standingBy
                    ? AppColors.line
                    : c.withValues(alpha: .8)),
          ),
          alignment: Alignment.center,
          child: AgentMochi(entry.agent.id, size: size * .58),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bg, width: 2),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.lineStrong),
          borderRadius: BorderRadius.circular(R.xs + 2),
        ),
        child: Text(text, style: mono(11, color: AppColors.fg3)),
      );
}

/// Needs-you first, then working, then standing by; each group keeps the
/// agent order the daemon gave.
List<CrewEntry> crewOrdered(List<CrewEntry> c) => [
      for (final s in CrewState.values) ...c.where((e) => e.state == s),
    ];

class CrewRoster extends StatelessWidget {
  const CrewRoster({
    super.key,
    required this.entries,
    required this.onOpen,
    this.onMenu,
    this.columns = 2,
  });

  final List<CrewEntry> entries;
  final ValueChanged<CoordinationAgent> onOpen;
  final void Function(BuildContext, CoordinationAgent, Offset)? onMenu;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final list = crewOrdered(entries);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final e in list)
            SizedBox(
                width: w, child: _Bubble(e, () => onOpen(e.agent), onMenu)),
        ]);
      }),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.e, this.onTap, this.onMenu);
  final CrewEntry e;
  final VoidCallback onTap;
  final void Function(BuildContext, CoordinationAgent, Offset)? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = crewColor(e.state);
    final idle = e.state == CrewState.standingBy;
    final tip = [
      e.agent.displayName,
      e.line,
      if (e.extra > 0) '+${e.extra} more sessions',
      if (e.agent.profile != null) e.agent.profile!,
    ].join('\n');
    return Tooltip(
      message: tip,
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kMobile ? 16 : 12),
          side: BorderSide(
              color: idle ? AppColors.line : c.withValues(alpha: .8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: onMenu == null
              ? null
              : (d) => onMenu!(context, e.agent, d.globalPosition),
          onLongPress: onMenu == null
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox;
                  onMenu!(context, e.agent,
                      box.localToGlobal(box.size.center(Offset.zero)));
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Stack(clipBehavior: Clip.none, children: [
              SizedBox(
                  width: double.infinity,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(
                        opacity: idle ? .75 : 1,
                        child: AgentMochi(e.agent.id, size: 36)),
                    const SizedBox(height: 6),
                    Text(e.agent.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: sans(11.5,
                            color: idle ? AppColors.fg3 : AppColors.fg1)),
                  ])),
              Positioned(
                right: 2,
                top: -4,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class CrewBoard extends StatefulWidget {
  const CrewBoard({
    super.key,
    required this.entries,
    required this.client,
    required this.onOpen,
    this.onDeleted,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 96),
  });

  final List<CrewEntry> entries;
  final DaemonClient client;
  final ValueChanged<CoordinationAgent> onOpen;
  final VoidCallback? onDeleted;
  final EdgeInsets padding;

  @override
  State<CrewBoard> createState() => _CrewBoardState();
}

class _CrewBoardState extends State<CrewBoard> {
  CrewState? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.entries;
    final shown = crewOrdered(
        all.where((e) => _filter == null || e.state == _filter).toList());
    Widget pill(String label, CrewState? s, int n) {
      final on = _filter == s;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.pill),
          onTap: () => setState(() => _filter = s),
          child: Container(
            constraints: BoxConstraints(minHeight: kMobile ? 36 : 28),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.surface3 : null,
              border: Border.all(color: AppColors.lineStrong),
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text('$label $n',
                style: sans(12.5,
                    weight: W.label,
                    color: on ? AppColors.fg1 : AppColors.fg3)),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 720 ? 2 : 1;
      const gap = 10.0;
      final w =
          (box.maxWidth - widget.padding.horizontal - gap * (cols - 1)) / cols;
      return ListView(padding: widget.padding, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            pill('All', null, all.length),
            pill('Needs you', CrewState.needsYou,
                crewCount(all, CrewState.needsYou)),
            pill('Working', CrewState.working,
                crewCount(all, CrewState.working)),
            pill('Standing by', CrewState.standingBy,
                crewCount(all, CrewState.standingBy)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(kMobile ? 16 : 12),
          ),
          child: Row(children: [
            const MochiIcon(color: Color(0xFFB9C6FF), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mission Control',
                      style: sans(14, weight: W.label, color: AppColors.fg1)),
                  Text(crewSummary(all),
                      style: sans(12.5, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: gap, runSpacing: gap, children: [
          for (final e in shown)
            SizedBox(
              width: w,
              child: _CrewCard(
                  key: ValueKey('crew-${e.agent.id}'),
                  entry: e,
                  client: widget.client,
                  onDeleted: widget.onDeleted,
                  onOpen: () => widget.onOpen(e.agent)),
            ),
        ]),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
                child: Text('Nobody here right now',
                    style: sans(13, color: AppColors.fg3))),
          ),
      ]);
    });
  }
}

class _CrewCard extends StatefulWidget {
  const _CrewCard(
      {super.key,
      required this.entry,
      required this.client,
      required this.onOpen,
      this.onDeleted});
  final CrewEntry entry;
  final DaemonClient client;
  final VoidCallback onOpen;
  final VoidCallback? onDeleted;

  @override
  State<_CrewCard> createState() => _CrewCardState();
}

class _CrewCardState extends State<_CrewCard> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _send(QuickAction a) async {
    final s = widget.entry.lead;
    if (s == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await quickSend(client: widget.client, session: s.id, action: a);
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  void _openChat() {
    final s = widget.entry.lead;
    if (s == null) return widget.onOpen();
    onNotifTap?.call({
      'kind': 'waiting',
      'url': widget.client.baseUrl,
      'session': s.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final needs = e.state == CrewState.needsYou;
    final profile = e.agent.profile;
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kMobile ? 16 : 12),
        side: BorderSide(
            color:
                needs ? AppColors.run.withValues(alpha: .8) : AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        onSecondaryTapDown: (d) => showCrewAgentMenu(context,
            client: widget.client,
            agent: widget.entry.agent,
            point: d.globalPosition,
            onDeleted: widget.onDeleted),
        child: Padding(
          padding: EdgeInsets.all(kMobile ? 14 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CrewTile(e, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.agent.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(14, weight: W.label, color: AppColors.fg1)),
                      if (e.agent.role.trim().isNotEmpty)
                        Text(e.agent.role.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12.5, color: AppColors.fg3)),
                    ],
                  ),
                ),
                Builder(
                  builder: (ctx) => IconBtn('more-horizontal',
                      size: kMobile ? 36 : 28,
                      iconSize: 16,
                      tooltip: 'Agent actions',
                      onTap: () => showCrewAgentMenu(ctx,
                          client: widget.client,
                          agent: e.agent,
                          onDeleted: widget.onDeleted)),
                ),
              ]),
              const SizedBox(height: 10),
              Text(e.line,
                  maxLines: needs ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      height: 1.4,
                      color: needs ? AppColors.run : AppColors.fg2)),
              if (needs) ...[
                const SizedBox(height: 10),
                Wrap(spacing: S.s8, runSpacing: S.s8, children: [
                  if (e.isApproval) ...[
                    Btn('Approve',
                        small: true,
                        disabled: _busy,
                        onTap: () => _send(const QuickApprove())),
                    Btn('Deny',
                        small: true,
                        variant: BtnVariant.secondary,
                        disabled: _busy,
                        onTap: () => _send(const QuickDeny())),
                  ] else
                    Btn('Answer', small: true, onTap: _openChat),
                  if (e.isApproval)
                    Btn('Open chat',
                        small: true,
                        variant: BtnVariant.secondary,
                        onTap: _openChat),
                ]),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: S.s6),
                    child: Text("Couldn't send. Open chat",
                        style: sans(12, color: AppColors.danger)),
                  ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Text(
                    '${e.sessions.length} session${e.sessions.length == 1 ? '' : 's'}',
                    style: sans(12, color: AppColors.fg4)),
                const Spacer(),
                if (profile != null) _Chip(profile),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour and delete for one agent, from a right-click, long-press or the
/// card's more button. Deleting is refused by the daemon while the agent is
/// still on an unfinished task, and its message is shown as is.
Future<void> showCrewAgentMenu(
  BuildContext context, {
  required DaemonClient client,
  required CoordinationAgent agent,
  Offset? point,
  VoidCallback? onDeleted,
}) async {
  final name =
      agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
  final picked = await showAppMenu<String>(
    context,
    point: point,
    anchor: point == null ? context : null,
    items: [
      appMenuItem(
          value: 'nickname',
          icon: 'pencil',
          label: agent.nickname == null ? 'Set nickname' : 'Edit nickname'),
      appMenuItem(value: 'color', icon: 'sparkles', label: 'Change colour'),
      appMenuItem(value: 'model', icon: 'cpu', label: 'Change model'),
      appMenuItem(
          value: 'delete', icon: 'trash', label: 'Delete agent', danger: true),
    ],
  );
  if (!context.mounted) return;
  if (picked == 'nickname') {
    final next = await promptText(context,
        title:
            'Nickname for ${agent.fullName.trim().isEmpty ? agent.id : agent.fullName.trim()}',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name');
    if (next == null || next == (agent.nickname ?? '')) return;
    try {
      await client.setAgentNickname(agent.id, next.isEmpty ? null : next);
      onDeleted?.call();
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  } else if (picked == 'color') {
    await showMochiColorPicker(context, client, agent.id, name, point: point);
  } else if (picked == 'model') {
    await _pickCrewModel(context, client, agent, name, point, onDeleted);
  } else if (picked == 'delete') {
    final ok = await confirmAction(context,
        title: 'Delete $name?',
        body:
            "This removes the agent, its identity and its notes. Its past task history loses it too. This can't be undone.",
        confirmLabel: 'Delete agent');
    if (!ok || !context.mounted) return;
    try {
      await client.deleteAgent(agent.id);
      if (context.mounted) toast(context, 'Deleted $name');
      onDeleted?.call();
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  }
}

Future<void> _pickCrewModel(
    BuildContext context,
    DaemonClient client,
    CoordinationAgent agent,
    String name,
    Offset? point,
    VoidCallback? onChanged) async {
  ServerConfig cfg;
  try {
    cfg = await client.getConfig();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return;
  }
  if (!context.mounted) return;
  if (cfg.profiles.isEmpty) {
    toast(context, 'No models configured');
    return;
  }
  String? picked;
  if (kMobile) {
    final c = Completer<String?>();
    showAppSheet(context,
        title: '$name works on',
        child: SheetActions([
          SheetAction('sparkles', "Session's own model", () {
            Navigator.pop(context);
            c.complete('');
          }),
          for (final p in cfg.profiles)
            SheetAction('provider:${p.provider}',
                p.name == agent.profile ? '${p.name}  (current)' : p.name, () {
              Navigator.pop(context);
              c.complete(p.name);
            }),
        ])).whenComplete(() {
      if (!c.isCompleted) c.complete(null);
    });
    picked = await c.future;
  } else {
    picked = await showAppMenu<String>(
      context,
      point: point,
      anchor: point == null ? context : null,
      minWidth: 260,
      maxWidth: 360,
      items: [
        appMenuHeading<String>('Works on'),
        appMenuRow<String>(
            value: '',
            icon: 'sparkles',
            label: "Session's own model",
            selected: agent.profile == null),
        for (final p in cfg.profiles)
          appMenuRow<String>(
              value: p.name,
              icon: 'provider:${p.provider}',
              label: p.name,
              description: '${p.provider} \u00b7 ${p.model}',
              selected: p.name == agent.profile),
      ],
    );
  }
  if (picked == null || picked == (agent.profile ?? '')) return;
  try {
    await client.setAgentProfile(agent.id, picked.isEmpty ? null : picked);
    if (context.mounted) toast(context, 'Model updated');
    onChanged?.call();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
  }
}

/// Collapsed crew: overlapping avatars that open the roster in a popover on
/// hover or tap.
class CrewStack extends StatefulWidget {
  const CrewStack({
    super.key,
    required this.entries,
    required this.onOpen,
    this.onMenu,
    this.onNew,
  });

  final List<CrewEntry> entries;
  final ValueChanged<CoordinationAgent> onOpen;
  final Future<void> Function(BuildContext, CoordinationAgent, Offset)? onMenu;
  final VoidCallback? onNew;

  @override
  State<CrewStack> createState() => _CrewStackState();
}

class _CrewStackState extends State<CrewStack> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;
  bool _pinned = false;

  void _show() {
    _hide?.cancel();
    if (!_portal.isShowing) _portal.show();
  }

  void _later() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 220), () {
      if (mounted && !_pinned && _portal.isShowing) _portal.hide();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = crewOrdered(widget.entries);
    final shown = list.take(4).toList();
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(14, -6),
          child: Align(
            alignment: Alignment.topLeft,
            child: MouseRegion(
              onEnter: (_) => _show(),
              onExit: (_) => _later(),
              child: Material(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                elevation: 0,
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.lineStrong),
                  ),
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final e in list)
                      _CrewTile(
                        e,
                        onTap: () {
                          _portal.hide();
                          widget.onOpen(e.agent);
                        },
                        onMenu: widget.onMenu == null
                            ? null
                            : (ctx, a, p) async {
                                _pinned = true;
                                _hide?.cancel();
                                try {
                                  await widget.onMenu!(ctx, a, p);
                                } finally {
                                  _pinned = false;
                                  if (mounted) _later();
                                }
                              },
                      ),
                    if (widget.onNew != null)
                      _NewAgentTile(onTap: () {
                        _portal.hide();
                        widget.onNew!();
                      }),
                  ]),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _later(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: SizedBox(
                height: 22,
                width: 22.0 + 14 * (shown.length.clamp(1, 4) - 1),
                child: Stack(children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: 14.0 * i,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppColors.bg, shape: BoxShape.circle),
                        child: AgentMochi(shown[i].agent.id, size: 18),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewTile extends StatelessWidget {
  const _CrewTile(this.e, {required this.onTap, this.onMenu});
  final CrewEntry e;
  final VoidCallback onTap;
  final void Function(BuildContext, CoordinationAgent, Offset)? onMenu;

  @override
  Widget build(BuildContext context) {
    final idle = e.state == CrewState.standingBy;
    return SizedBox(
      width: 191,
      height: 124,
      child: HoverSurface(
        rest: AppColors.surface3,
        hoverColor: Color.lerp(AppColors.surface3, AppColors.fg1, 0.07),
        radius: 10,
        onTap: onTap,
        onSecondaryTapDown: onMenu == null
            ? null
            : (d) => onMenu!(context, e.agent, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                  opacity: idle ? .85 : 1,
                  child: AgentMochi(e.agent.id, size: 44)),
              const Spacer(),
              Text(e.agent.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13.5, weight: W.label, color: AppColors.fg1)),
              if (e.line.isNotEmpty)
                Text(e.line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12,
                        color: idle ? AppColors.fg4 : crewColor(e.state))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewAgentTile extends StatelessWidget {
  const _NewAgentTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 191,
        height: 124,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.lineStrong),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AppIcon('plus', size: 18, color: AppColors.fg3),
              const SizedBox(height: 6),
              Text('New agent', style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ),
      );
}
