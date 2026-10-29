import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'macos_notch.dart';
import 'notification_sync.dart';
import 'notifications.dart';
import 'theme.dart';
import 'platform.dart';
import 'notification_card.dart';

class NotificationPopovers extends StatefulWidget {
  const NotificationPopovers({super.key, required this.child});
  final Widget child;
  @override
  State<NotificationPopovers> createState() => _NotificationPopoversState();
}

class _NotificationPopoversState extends State<NotificationPopovers> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<Map<String, dynamic>> _pending = [];
  Timer? _expiry;
  Map<String, dynamic>? _timedPayload;
  bool _pressed = false;
  late final OverlayEntry _contentEntry;

  void _syncExpiry() {
    final payload = _pending.firstOrNull;
    if (identical(payload, _timedPayload)) return;
    _expiry?.cancel();
    _timedPayload = payload;
    _pressed = false;
    _armExpiry();
  }

  void _armExpiry() {
    _expiry?.cancel();
    final payload = _timedPayload;
    if (payload == null || _pressed) return;
    _expiry = Timer(Duration(seconds: kMobile ? 5 : 7), () {
      if (mounted && identical(_pending.firstOrNull, payload)) {
        _remove(payload);
      }
    });
  }

  void _remove(Map<String, dynamic> payload,
      {bool open = false, bool feedback = false}) {
    if (!identical(_pending.firstOrNull, payload)) return;
    if (feedback) HapticFeedback.lightImpact();
    setState(() {
      _pending.removeAt(0);
      _syncExpiry();
    });
    if (open) onNotifTap?.call(payload);
  }

  void _clearAll(Map<String, dynamic> payload) {
    if (!identical(_pending.firstOrNull, payload)) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _pending.clear();
      _syncExpiry();
    });
  }

  String _contextLabel(Map<String, dynamic> payload) {
    // Preserve the daemon-facing subtitle used by the notch.
    final kind = payload['kind']?.toString().split('.').last;
    final label = switch (kind) {
      'idle' => 'Stopped',
      'waiting' => 'Needs your input',
      'error' || 'failed' => 'Failed',
      'done' || 'completed' => 'Completed',
      'term' || 'message' => 'New message',
      _ => switch ((payload['destination'] as Map?)?['type']) {
          'task' => 'Task update',
          'conversation' => 'New message',
          _ => '',
        },
    };
    final body = payload['body']?.toString().trim() ?? '';
    return body.isEmpty ? label : (label.isEmpty ? body : '$label · $body');
  }

  void _forwardToMacNotch(Map<String, dynamic> payload) {
    if (!kMacOS) return;
    MacosNotch.showNotification(
      title: payload['title']?.toString() ?? 'Snippet',
      subtitle: _contextLabel(payload),
      kind: payload['kind']?.toString() ?? '',
      payload: payload,
    );
  }

  @override
  void initState() {
    super.initState();
    MacosNotch.ensureInitialized();
    _contentEntry = OverlayEntry(builder: _buildContent);
    final initial = foregroundNotifications.drain();
    _pending.addAll(initial);
    for (final p in initial) {
      _forwardToMacNotch(p);
    }
    visibleNotificationSession.addListener(_visibilityChanged);
    _subscription = foregroundNotifications.stream.listen((payload) {
      _forwardToMacNotch(payload);
      if (mounted) setState(() => _pending.add(payload));
    });
  }

  void _visibilityChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _pending.removeWhere(suppressVisibleNotification));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    visibleNotificationSession.removeListener(_visibilityChanged);
    _subscription?.cancel();
    _expiry?.cancel();
    _contentEntry.remove();
    _contentEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _contentEntry.markNeedsBuild();
    return Overlay(initialEntries: [_contentEntry]);
  }

  Widget _buildContent(BuildContext context) {
    _pending.removeWhere(suppressVisibleNotification);
    _syncExpiry();
    final payload = _pending.firstOrNull;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(children: [
      widget.child,
      Positioned(
          top: S.s8,
          left: S.s12,
          right: S.s12,
          child: SafeArea(
              child: Align(
            alignment: kMobile ? Alignment.topCenter : Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, -.08), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                child: payload == null
                    ? const SizedBox.shrink()
                    : MouseRegion(
                        key: ObjectKey(payload),
                        onEnter: (_) {
                          _pressed = true;
                          _expiry?.cancel();
                        },
                        onExit: (_) {
                          _pressed = false;
                          _armExpiry();
                        },
                        child: Listener(
                        onPointerDown: (_) {
                          _pressed = true;
                          _expiry?.cancel();
                        },
                        onPointerUp: (_) {
                          _pressed = false;
                          _armExpiry();
                        },
                        onPointerCancel: (_) {
                          _pressed = false;
                          _armExpiry();
                        },
                        child: Dismissible(
                          key: ObjectKey(payload),
                          direction: DismissDirection.horizontal,
                          movementDuration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          resizeDuration: null,
                          onDismissed: (_) => _remove(payload, feedback: true),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: reducedMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: FractionalTranslation(
                                translation: Offset(0, -.08 * (1 - value)),
                                child: child,
                              ),
                            ),
                            child: Semantics(
                              label: _pending.length > 1
                                  ? '${_pending.length} notifications. Long press to clear all'
                                  : null,
                              onLongPress: _pending.length > 1
                                  ? () => _clearAll(payload)
                                  : null,
                              child: NotificationMessageCard(
                                payload: payload,
                                rest: _pending.skip(1).toList(),
                                onOpen: () => _remove(payload,
                                    open: true, feedback: true),
                                onDismiss: () =>
                                    _remove(payload, feedback: true),
                                onClearAll: () => _clearAll(payload),
                                onHold: (hold) {
                                  _pressed = hold;
                                  hold ? _expiry?.cancel() : _armExpiry();
                                },
                                onSent: () => _remove(payload),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
              ),
            ),
          ))),
    ]);
  }
}
