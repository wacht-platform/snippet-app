import 'dart:async';
import 'package:flutter/material.dart';
import 'notification_sync.dart';
import 'notifications.dart';

class NotificationPopovers extends StatefulWidget {
  const NotificationPopovers({super.key, required this.child});
  final Widget child;
  @override
  State<NotificationPopovers> createState() => _NotificationPopoversState();
}

class _NotificationPopoversState extends State<NotificationPopovers> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<Map<String, dynamic>> _pending = [];
  @override
  void initState() {
    super.initState();
    _pending.addAll(foregroundNotifications.drain());
    _subscription = foregroundNotifications.stream.listen((payload) {
      if (mounted) setState(() => _pending.add(payload));
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_pending.isNotEmpty)
          Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: SafeArea(
                  child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  title: Text(_pending.first['title']?.toString() ??
                      'New notification'),
                  subtitle: const Text('Tap to open · saved in inbox'),
                  onTap: () {
                    final payload = _pending.first;
                    setState(() => _pending.removeAt(0));
                    onNotifTap?.call(payload);
                  },
                  trailing: IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _pending.removeAt(0))),
                ),
              ))),
      ]);
}
