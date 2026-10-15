import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

const _routeDefs = <(String, String, String)>[
  (
    'mission',
    'Mission Control',
    'Plans work and dispatches it to sessions and agents.'
  ),
  ('inbox', 'Agent inboxes', 'Agents answering messages and claiming tasks.'),
  (
    'lanes',
    'Lanes',
    'Sub-tasks a session hands off. A session can still pick a model for one lane.'
  ),
  ('memory', 'Memory', 'Background tidying of project and global memory.'),
];

String limitLabel(int resetsAt) {
  final t = DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000);
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? '$hh:$mm' : '${t.month}/${t.day} $hh:$mm';
}

class RoutingScreen extends StatefulWidget {
  const RoutingScreen({
    super.key,
    required this.client,
    this.embedded = false,
    this.onBack,
  });

  final DaemonClient client;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  ServerConfig? _config;
  Object? _error;
  String? _open;
  final Map<String, List<String>> _routes = {};

  @override
  void initState() {
    super.initState();
    _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    try {
      final c = await widget.client.getConfig(force: force);
      if (!mounted) return;
      setState(() {
        _config = c;
        _error = null;
        _routes
          ..clear()
          ..addAll({
            for (final e in c.routing.entries) e.key: [...e.value]
          });
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(String route, List<String> next) async {
    final before = [...?_routes[route]];
    setState(() => _routes[route] = next);
    try {
      await widget.client.setRouting(route, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _routes[route] = before);
      toast(context, "Couldn't save the route: $e", danger: true);
    }
  }

  Widget _routeRow(String key, String title, String about) {
    final chosen = _routes[key] ?? const [];
    final open = _open == key;
    final limited = _config?.limited ?? const {};
    final summary = chosen.isEmpty
        ? (key == 'memory' || key == 'lanes'
            ? 'Not set. Uses the session\'s own model.'
            : 'Not set. Uses the active profile.')
        : chosen.join('  →  ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListRow(
        title: title,
        subtitle: summary,
        selected: open,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (chosen.any(limited.containsKey))
            const Padding(
              padding: EdgeInsets.only(right: S.s8),
              child: Tag('Limited', tone: Tone.run, dot: true),
            ),
          AppIcon(open ? 'chevron-up' : 'chevron-down',
              size: 16, color: AppColors.fg3),
        ]),
        onTap: () => setState(() => _open = open ? null : key),
      ),
      AnimatedSize(
        duration: Motion.fast,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? _editor(key, about, chosen)
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }

  Widget _editor(String key, String about, List<String> chosen) {
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final byName = {for (final p in profiles) p.name: p};
    final rest = [
      for (final p in profiles)
        if (!chosen.contains(p.name)) p.name
    ];
    final limited = _config?.limited ?? const {};
    Widget row(String name, int? index) {
      final p = byName[name];
      final on = index != null;
      final until = limited[name];
      return Container(
        key: ValueKey('$key-$name'),
        height: kMobile ? 48 : 36,
        padding: const EdgeInsets.only(left: S.s16, right: S.s8),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _save(
                  key, on ? ([...chosen]..remove(name)) : [...chosen, name]),
              child: Row(children: [
                SelectCheck(on, size: 16),
                const SizedBox(width: S.s8),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13.5,
                          color: on ? AppColors.fg1 : AppColors.fg3)),
                ),
                if (p != null) ...[
                  const SizedBox(width: S.s8),
                  Flexible(
                    child: Text(p.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg4)),
                  ),
                ],
              ]),
            ),
          ),
          if (until != null)
            Tag('Limited until ${limitLabel(until)}', tone: Tone.run),
          if (on)
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.all(S.s8),
                  child: AppIcon('grip', size: 14, color: AppColors.fg4),
                ),
              ),
            )
          else
            const SizedBox(width: 30),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: S.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s8),
          child: Text(about, style: TS.meta()),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, __) => Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.md),
            child: child,
          ),
          onReorderItem: (from, to) {
            final next = [...chosen];
            final item = next.removeAt(from);
            next.insert(to, item);
            _save(key, next);
          },
          children: [
            for (var i = 0; i < chosen.length; i++) row(chosen[i], i),
          ],
        ),
        for (final name in rest) row(name, null),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_config == null) {
      body = _error == null
          ? const ListSkeleton()
          : EmptyState(
              icon: 'alert-triangle',
              title: "Couldn't load routing",
              body: '$_error',
              action:
                  Btn('Retry', small: true, onTap: () => _load(force: true)),
            );
    } else {
      body = PageBody(children: [
        ListGroup(children: [
          for (final (key, title, about) in _routeDefs)
            _routeRow(key, title, about),
        ]),
        const SettingsNote(
            'The first model in a route does the work. When it hits a usage limit, the work moves to the next one and stays there. Chats you are in ask you before switching.'),
      ]);
    }
    if (widget.embedded && widget.onBack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavBackRow(title: 'Routing', onBack: widget.onBack!),
          Expanded(child: body),
        ],
      );
    }
    return body;
  }
}
