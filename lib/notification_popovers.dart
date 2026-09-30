import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_sync.dart';
import 'notifications.dart';
import 'theme.dart';
import 'widgets.dart';

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
    _expiry = Timer(const Duration(seconds: 5), () {
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

  String _contextLabel(Map<String, dynamic> payload) {
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
          _ => 'Tap to open',
        },
    };
    final body = payload['body']?.toString().trim() ?? '';
    return body.isEmpty ? label : '$label · $body';
  }

  @override
  void initState() {
    super.initState();
    _pending.addAll(foregroundNotifications.drain());
    visibleNotificationSession.addListener(_visibilityChanged);
    _subscription = foregroundNotifications.stream.listen((payload) {
      if (mounted) setState(() => _pending.add(payload));
    });
  }

  void _visibilityChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _pending.removeWhere(suppressVisibleNotification));
      }
    });
  }

  @override
  void dispose() {
    visibleNotificationSession.removeListener(_visibilityChanged);
    _subscription?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            alignment: Alignment.topCenter,
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
                    : Listener(
                        key: ObjectKey(payload),
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
                          direction:
                              Directionality.of(context) == TextDirection.rtl
                                  ? DismissDirection.startToEnd
                                  : DismissDirection.endToStart,
                          movementDuration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          resizeDuration: null,
                          onDismissed: (_) => _remove(payload, feedback: true),
                          child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: FractionalTranslation(
                                  translation: Offset(0, -.08 * (1 - value)),
                                  child: child,
                                ),
                              ),
                              child: Material(
                              color: AppColors.surface2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.card),
                              side: BorderSide(color: AppColors.lineStrong),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                _remove(payload, open: true, feedback: true);
                              },
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    S.s12, S.s8, S.s4, S.s8),
                                child: Row(children: [
                                  AppIcon(
                                    switch ((payload['destination']
                                        as Map?)?['type']) {
                                      'session' => 'terminal',
                                      'task' => 'check-circle',
                                      'conversation' => 'message-circle',
                                      _ => 'info',
                                    },
                                    size: 18,
                                    color: AppColors.fg3,
                                  ),
                                  const SizedBox(width: S.s12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          payload['title']?.toString() ??
                                              'New notification',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TS.label(AppColors.fg1),
                                        ),
                                        const SizedBox(height: S.s2),
                                        Text(_contextLabel(payload),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TS.caption()),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Dismiss',
                                    icon: AppIcon('x',
                                        size: 16, color: AppColors.fg3),
                                    onPressed: () =>
                                        _remove(payload, feedback: true),
                                  ),
                                ]),
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
