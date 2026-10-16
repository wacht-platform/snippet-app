import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../settings_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

const _routeDefs = <(String, String, String)>[
  ('mission', 'Mission Control', 'Plans and dispatches work'),
  ('inbox', 'Agent inboxes', 'Answers messages and claims tasks'),
  ('lanes', 'Lanes', 'Work a session hands off'),
  ('memory', 'Memory', 'Reflection and compaction notes'),
];

const _limitRules = <(String, String, String)>[
  ('In your chats', 'A limit in a session you are watching', 'Ask me'),
  ('In the background', 'Lanes, agents and Mission Control', 'Switch automatically'),
  ('After the limit resets', 'Where work continues', 'Stay on the fallback'),
];

String limitLabel(int resetsAt) {
  final t = DateTime.fromMillisecondsSinceEpoch(resetsAt * 1000);
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  if (sameDay) return '$hh:$mm';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[t.month - 1]} ${t.day}, $hh:$mm';
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

  Future<void> _addFallbackMenu(
      BuildContext anchor, String key, List<String> chosen) async {
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final available = [
      for (final p in profiles)
        if (!chosen.contains(p.name)) p
    ];
    if (available.isEmpty) {
      toast(context, 'All profiles are already in this route');
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 230,
      maxWidth: 320,
      items: [
        appMenuHeading<String>(
            chosen.isEmpty ? 'Select primary profile' : 'Add fallback profile'),
        for (final p in available)
          appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} · ${p.model}',
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await _save(key, [...chosen, picked]);
  }

  Future<void> _pillMenu(
      BuildContext anchor, String key, List<String> chosen, int index) async {
    final name = chosen[index];
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final unused = [
      for (final p in profiles)
        if (!chosen.contains(p.name)) p
    ];
    final action = await showAppMenu<String>(
      context,
      anchor: anchor,
      minWidth: 220,
      maxWidth: 300,
      items: [
        appMenuHeading<String>(index == 0 ? 'Primary model' : 'Fallback #$index'),
        if (index > 0)
          appMenuItem<String>(
              value: 'primary', icon: 'sparkles', label: 'Make primary'),
        if (index > 0)
          appMenuItem<String>(
              value: 'left', icon: 'arrow-left', label: 'Move earlier'),
        if (index < chosen.length - 1)
          appMenuItem<String>(
              value: 'right', icon: 'arrow-right', label: 'Move later'),
        for (final p in unused)
          appMenuRow<String>(
            value: 'swap:${p.name}',
            icon: 'provider:${p.provider}',
            label: 'Replace with ${p.name}',
            description: p.model,
          ),
        appMenuItem<String>(
            value: 'remove',
            icon: 'trash',
            label: 'Remove from route',
            danger: true),
      ],
    );
    if (action == null || !mounted) return;
    final next = [...chosen];
    if (action == 'primary') {
      next.removeAt(index);
      next.insert(0, name);
    } else if (action == 'left' && index > 0) {
      next.removeAt(index);
      next.insert(index - 1, name);
    } else if (action == 'right' && index < next.length - 1) {
      next.removeAt(index);
      next.insert(index + 1, name);
    } else if (action.startsWith('swap:')) {
      next[index] = action.substring(5);
    } else if (action == 'remove') {
      next.removeAt(index);
    }
    await _save(key, next);
  }

  Widget _chainWrap(String key, List<String> chosen) {
    final profiles = _config?.profiles ?? const <InferenceProfile>[];
    final byName = {for (final p in profiles) p.name: p};
    final limited = _config?.limited ?? const {};
    final hasMoreProfiles = chosen.length < profiles.length;
    final defaultLabel =
        key == 'lanes' || key == 'memory' ? 'Session model' : 'Active profile';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (chosen.isEmpty)
          Builder(
            builder: (anchor) => Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () => _addFallbackMenu(anchor, key, chosen),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(defaultLabel,
                        style: sans(12.5, color: AppColors.fg3)),
                  ]),
                ),
              ),
            ),
          ),
        for (var i = 0; i < chosen.length; i++) ...[
          if (i > 0)
            AppIcon('chevron-right', size: 12, color: AppColors.fg4),
          Builder(
            builder: (anchor) {
              final name = chosen[i];
              final p = byName[name];
              final isPrimary = i == 0;
              final until = limited[name];
              return Tooltip(
                message: until != null
                    ? 'Limited until ${limitLabel(until)}'
                    : (isPrimary ? 'Primary · tap to edit' : 'Fallback · tap to edit'),
                child: Material(
                  color: isPrimary ? AppColors.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => _pillMenu(anchor, key, chosen, i),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ProviderLogo(p?.provider ?? name, size: 12),
                        const SizedBox(width: 7),
                        Text(
                          name,
                          style: sans(
                            12.5,
                            color: isPrimary ? AppColors.fg1 : AppColors.fg3,
                          ),
                        ),
                        if (until != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.run,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        if (hasMoreProfiles)
          Builder(
            builder: (anchor) => Tooltip(
              message: chosen.isEmpty ? 'Set profile' : 'Add fallback',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _addFallbackMenu(anchor, key, chosen),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    alignment: Alignment.center,
                    child: AppIcon('plus', size: 13, color: AppColors.fg3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopRouteRow(String key, String title, String about) {
    final chosen = _routes[key] ?? const [];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sans(13.5, color: AppColors.fg1)),
                const SizedBox(height: 2),
                Text(about, style: sans(12, color: AppColors.fg4)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: _chainWrap(key, chosen)),
        ],
      ),
    );
  }

  Widget _mobileRouteRow(String key, String title, String about, bool isLast) {
    final chosen = _routes[key] ?? const [];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: sans(15, color: AppColors.fg1)),
          const SizedBox(height: 2),
          Text(about, style: sans(12.5, color: AppColors.fg4)),
          const SizedBox(height: 10),
          _chainWrap(key, chosen),
        ],
      ),
    );
  }

  Widget _limitRulePill(String value) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.center,
        child: Text(value, style: sans(12.5, color: AppColors.fg2)),
      );

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
    } else if (kMobile) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              'Which model does each kind of work, and who steps in when it hits a limit.',
              style: sans(13, height: 1.5, color: AppColors.fg3),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _routeDefs.length; i++)
                  _mobileRouteRow(
                    _routeDefs[i].$1,
                    _routeDefs[i].$2,
                    _routeDefs[i].$3,
                    i == _routeDefs.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          SettingsGroup(
            header: 'When the preferred model hits a limit',
            children: [
              for (final (name, sub, val) in _limitRules)
                SettingsRow(
                  label: name,
                  sub: sub,
                  trailing: Text(val, style: sans(13, color: AppColors.fg3)),
                ),
            ],
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
        children: [
          Text(
            'Which model does each kind of work, and who steps in when it hits a limit.',
            style: sans(13.5, height: 1.55, color: AppColors.fg3),
          ),
          const SizedBox(height: 18),
          for (final (key, title, about) in _routeDefs)
            _desktopRouteRow(key, title, about),
          const SizedBox(height: 32),
          Text(
            'WHEN THE PREFERRED MODEL HITS A LIMIT',
            style: sans(11, spacing: 0.8, color: AppColors.fg4),
          ),
          const SizedBox(height: 8),
          for (final (name, sub, val) in _limitRules)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: sans(13.5, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Text(sub, style: sans(12, color: AppColors.fg4)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _limitRulePill(val),
              ]),
            ),
        ],
      );
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
