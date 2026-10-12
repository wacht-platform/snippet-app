import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_sync.dart';
import 'notifications.dart';
import 'theme.dart';
import 'platform.dart';
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

  Widget _stackedCard({required Widget child}) {
    final layers = (_pending.length - 1).clamp(0, 2);
    return Stack(children: [
      for (var layer = layers; layer > 0; layer--)
        Positioned.fill(
          top: layer * 5.0,
          left: layer * 5.0,
          right: layer * 5.0,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey('notification-backing-$layer'),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(kMobile ? 18 : 14),
                border: kMobile ? null : Border.all(color: AppColors.border2),
              ),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.only(bottom: layers * 5.0),
        child: child,
      ),
    ]);
  }

  Widget _leadingIcon(Map<String, dynamic> payload) {
    final kind = payload['kind']?.toString();
    final (fill, ink) = switch (kind) {
      'done' || 'completed' => (AppColors.okBg, AppColors.ok),
      'error' || 'failed' => (AppColors.dangerBg, AppColors.danger),
      'waiting' => (AppColors.runBg, AppColors.run),
      _ => (AppColors.accentBg, AppColors.accent),
    };
    return Container(
      width: kMobile ? 36 : 32,
      height: kMobile ? 36 : 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(kMobile ? 11 : 9),
      ),
      child: AppIcon(
        switch ((payload['destination'] as Map?)?['type']) {
          'session' => 'terminal',
          'task' => 'check-circle',
          'conversation' => 'message-circle',
          _ => 'info',
        },
        size: 16,
        color: ink,
      ),
    );
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
          _ => '',
        },
    };
    final body = payload['body']?.toString().trim() ?? '';
    return body.isEmpty ? label : (label.isEmpty ? body : '$label · $body');
  }

  @override
  void initState() {
    super.initState();
    _contentEntry = OverlayEntry(builder: _buildContent);
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
                            child: _stackedCard(
                                child: Material(
                              color: AppColors.surface3,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(kMobile ? 18 : 14),
                                side: kMobile
                                    ? BorderSide.none
                                    : BorderSide(color: AppColors.border2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onLongPress: () => _clearAll(payload),
                                onTap: () {
                                  _remove(payload, open: true, feedback: true);
                                },
                                child: Padding(
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                      12, kMobile ? 12 : 10, 4, kMobile ? 12 : 10),
                                  child: Row(children: [
                                    _leadingIcon(payload),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Semantics(
                                            label: _pending.length > 1
                                                ? '${_pending.length} notifications. Long press to clear all'
                                                : null,
                                            onLongPress: _pending.length > 1
                                                ? () => _clearAll(payload)
                                                : null,
                                            child: Text(
                                              payload['title']?.toString() ??
                                                  'New notification',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: sans(kMobile ? 15 : 14,
                                                  weight: W.label,
                                                  height: kMobile
                                                      ? 20 / 15
                                                      : 19 / 14,
                                                  color: AppColors.fg1),
                                            ),
                                          ),
                                          if (_contextLabel(payload)
                                              .isNotEmpty) ...[
                                            const SizedBox(height: S.s2),
                                            Text(_contextLabel(payload),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: sans(kMobile ? 13 : 12.5,
                                                    height: kMobile
                                                        ? 18 / 13
                                                        : 17 / 12.5,
                                                    color: AppColors.fg3)),
                                          ],
                                          if (!kMobile &&
                                              _pending.length > 1) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                                spacing: 10,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                              Text(
                                                  '+${_pending.length - 1} more',
                                                  style: sans(12,
                                                      color: AppColors.fg4)),
                                              InkWell(
                                                onTap: () =>
                                                    _clearAll(payload),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        R.xs),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4,
                                                      vertical: 2),
                                                  child: Text('Clear all',
                                                      style: sans(12,
                                                          weight: W.label,
                                                          color: AppColors
                                                              .accent)),
                                                ),
                                              ),
                                            ]),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Dismiss',
                                      style: const ButtonStyle(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                              width: 44, height: 36),
                                      icon: AppIcon('x',
                                          size: 14, color: AppColors.fg3),
                                      onPressed: () =>
                                          _remove(payload, feedback: true),
                                    ),
                                  ]),
                                ),
                              ),
                            )),
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
