/// Mission Control screen — the public entry. Picks the right layout (mobile
/// or desktop) based on the available width and shows the agent surface.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../panel.dart';
import '../session.dart';
import 'mission_control_state.dart';
import 'mobile/mobile_mc.dart';
import 'desktop/desktop_mc.dart';

class MissionControlScreen extends StatefulWidget {
  const MissionControlScreen({super.key, required this.client});
  final DaemonClient client;

  @override
  State<MissionControlScreen> createState() => _MissionControlScreenState();
}

class _MissionControlScreenState extends State<MissionControlScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MissionControlState>(
      create: (_) => MissionControlState(client: widget.client)..start(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          return isWide
              ? const DesktopMissionControl()
              : const MobileMissionControl();
        },
      ),
    );
  }
}

/// Minimal ChangeNotifier Provider — keeps the rewrite local to this
/// directory without pulling in `provider` as a new dependency.
class ChangeNotifierProvider<T extends ChangeNotifier> extends StatefulWidget {
  const ChangeNotifierProvider({
    super.key,
    required this.create,
    required this.child,
  });
  final T Function(BuildContext) create;
  final Widget child;

  static T of<T extends ChangeNotifier>(BuildContext context) {
    final inh = context
        .dependOnInheritedWidgetOfExactType<_InheritedNotifierProvider<T>>();
    assert(inh != null, 'No ChangeNotifierProvider<$T> in context');
    return inh!.notifier;
  }

  @override
  State<ChangeNotifierProvider<T>> createState() =>
      _ChangeNotifierProviderState<T>();
}

class _ChangeNotifierProviderState<T extends ChangeNotifier>
    extends State<ChangeNotifierProvider<T>> {
  late T notifier;

  @override
  void initState() {
    super.initState();
    notifier = widget.create(context);
    notifier.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    notifier.removeListener(_onChanged);
    notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedNotifierProvider<T>(
        notifier: notifier, child: widget.child);
  }
}

class _InheritedNotifierProvider<T extends ChangeNotifier>
    extends InheritedWidget {
  const _InheritedNotifierProvider(
      {required this.notifier, required super.child});
  final T notifier;

  @override
  bool updateShouldNotify(_InheritedNotifierProvider<T> oldWidget) =>
      oldWidget.notifier != notifier;
}

/// Open the Mission Control conversation as a panel from anywhere with a client.
void openMissionControl(BuildContext context, DaemonClient client) {
  unawaited(client.mcOpen());
  presentScreen(
    context,
    builder: (_, close) => SessionScreen(
      client: client,
      sessionId: 'mission-control',
      title: 'Mission Control',
      onMenu: close,
    ),
  );
}
