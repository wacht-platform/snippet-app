import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'media_views.dart';

enum ShellPanelPurpose {
  lanes,
  checkpoints,
  recurring,
  processes,
  files,
  browser,
  task,
  tasks,
  agents,
  agent,
  conversation,
  inbox,
  generic,
}

class ShellPanelRequest {
  ShellPanelRequest(
      {required this.purpose,
      required this.id,
      required this.client,
      this.sessionId,
      required this.builder});

  final ShellPanelPurpose purpose;
  final String id;
  final DaemonClient? client;
  final String? sessionId;
  final Widget Function(BuildContext, VoidCallback) builder;
  final Completer<Object?> dismissed = Completer<Object?>();
  final navigatorKey = GlobalKey<NavigatorState>();
  String get key => 'request|${client?.baseUrl}|$sessionId|${purpose.name}|$id';
  String get label => switch (purpose) {
        ShellPanelPurpose.task => 'Task',
        ShellPanelPurpose.agents => 'Agents',
        ShellPanelPurpose.conversation => 'Conversation',
        _ => '${purpose.name[0].toUpperCase()}${purpose.name.substring(1)}',
      };
  void complete() {
    if (!dismissed.isCompleted) dismissed.complete();
  }
}

class ShellPanelScope extends InheritedWidget {
  const ShellPanelScope(
      {super.key,
      required this.open,
      this.client,
      this.sessionId,
      required super.child});
  final Future<Object?> Function(ShellPanelRequest) open;
  final DaemonClient? client;
  final String? sessionId;
  static ShellPanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellPanelScope>();
  @override
  bool updateShouldNotify(ShellPanelScope old) =>
      old.open != open || old.client != client || old.sessionId != sessionId;
}

class ShellPanelBody extends StatelessWidget {
  const ShellPanelBody(
      {super.key, required this.request, required this.onClose});
  final ShellPanelRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final host = ShellPanelScope.maybeOf(context)!;
    Widget body = Navigator(
      key: request.navigatorKey,
      pages: [
        MaterialPage<void>(
          key: ValueKey(request.key),
          child: Builder(
              builder: (context) =>
                  Material(child: request.builder(context, onClose))),
        )
      ],
      onDidRemovePage: (_) => onClose(),
    );
    final client = request.client;
    if (client != null) body = DaemonScope(client: client, child: body);
    return ShellPanelScope(
        open: host.open,
        client: client,
        sessionId: request.sessionId,
        child: body);
  }
}
