import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'call_prompt_card.dart';
import 'call_tracking.dart';
import 'macos_notch.dart';
import 'notification_sync.dart';
import 'notifications.dart';
import 'theme.dart';
import 'platform.dart';
import 'notification_card.dart';
import 'notification_stack.dart';
import 'session_quick_send.dart' show resolveInstanceForPayload;

class NotificationPopovers extends StatefulWidget {
  const NotificationPopovers({super.key, required this.child});
  final Widget child;
  @override
  State<NotificationPopovers> createState() => _NotificationPopoversState();
}

class _NotificationPopoversState extends State<NotificationPopovers> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<Map<String, dynamic>> _pending = [];
  final _timers = <Map<String, dynamic>, Timer>{};
  bool _pointer = false;
  bool _cardHold = false;
  bool _expanded = false;
  late final OverlayEntry _contentEntry;

  bool get _held => _pointer || _cardHold || _expanded;

  // Clears the app bar (56 on phones, 44 on desktop panes) so toasts never cover header controls.
  static double get _anchorTop => kMobile ? M.appBarHeight + S.s12 : 44 + S.s8;

  Duration _life(Map<String, dynamic> p) {
    final base = kMobile ? 5 : 7;
    return Duration(seconds: needsYou(p) ? base * 3 : base);
  }

  List<Map<String, dynamic>> get _ordered {
    final l = _pending.reversed.toList();
    return [...l.where(needsYou), ...l.where((p) => !needsYou(p))];
  }

  void _arm() {
    _timers.removeWhere((p, t) {
      final gone = !_pending.any((q) => identical(q, p));
      if (gone || _held) t.cancel();
      return gone || _held;
    });
    if (_held) return;
    for (final p in _pending) {
      _timers.putIfAbsent(
          p,
          () => Timer(_life(p), () {
                _timers.remove(p);
                if (mounted) _remove(p);
              }));
    }
  }

  void _afterChange() {
    if (_pending.length < 2) _expanded = false;
    _arm();
  }

  void _setHold({bool? pointer, bool? card}) {
    _pointer = pointer ?? _pointer;
    _cardHold = card ?? _cardHold;
    _arm();
  }

  void _remove(Map<String, dynamic> payload,
      {bool open = false, bool feedback = false}) {
    if (!_pending.any((p) => identical(p, payload))) return;
    if (feedback) HapticFeedback.lightImpact();
    setState(() {
      _pending.removeWhere((p) => identical(p, payload));
      _afterChange();
    });
    if (open) onNotifTap?.call(payload);
  }

  void _clearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _pending.clear();
      _afterChange();
    });
  }

  String _contextLabel(Map<String, dynamic> payload) {
    // Preserve the daemon-facing subtitle used by the notch.
    final kind = payload['kind']?.toString().split('.').last;
    final label = switch (kind) {
      'idle' => 'Finished · standing by',
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
    _arm();
    for (final p in initial) {
      _forwardToMacNotch(p);
    }
    callTracker.state.addListener(_callChanged);
    visibleNotificationSession.addListener(_visibilityChanged);
    _subscription = foregroundNotifications.stream.listen((payload) {
      _forwardToMacNotch(payload);
      if (!mounted) return;
      setState(() => _pending.add(payload));
      _arm();
    });
  }

  void _callChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _callAction(CallStatus status, String action) async {
    final instance = await resolveInstanceForPayload({'url': status.url});
    if (instance == null) return false;
    return callTracker.act(
        DaemonClient(instance.url, instance.token), status.callId, action);
  }

  void _visibilityChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _pending.removeWhere(suppressVisibleNotification);
          _afterChange();
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    callTracker.state.removeListener(_callChanged);
    visibleNotificationSession.removeListener(_visibilityChanged);
    _subscription?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    _contentEntry.remove();
    _contentEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _contentEntry.markNeedsBuild();
    return Overlay(initialEntries: [_contentEntry]);
  }

  Widget _card(Map<String, dynamic> payload, bool embedded, bool lifted,
      bool reducedMotion) {
    return Dismissible(
      key: ObjectKey(payload),
      direction: DismissDirection.horizontal,
      movementDuration: reducedMotion ? Duration.zero : Motion.fast,
      resizeDuration: null,
      onDismissed: (_) => _remove(payload, feedback: true),
      child: NotificationMessageCard(
        key: ObjectKey(payload),
        payload: payload,
        embedded: embedded,
        lifted: lifted,
        onOpen: () => _remove(payload, open: true, feedback: true),
        onDismiss: () => _remove(payload, feedback: true),
        onHold: (hold) => _setHold(card: hold),
        onSent: () => _remove(payload),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    _pending.removeWhere(suppressVisibleNotification);
    final items = _ordered;
    final call = callTracker.state.value;
    final reducedMotion = reduceMotion(context);
    return Stack(children: [
      widget.child,
      if (call != null)
        Positioned(
            top: _anchorTop,
            left: S.s12,
            right: S.s12,
            child: SafeArea(
                child: Align(
              alignment: kMobile ? Alignment.topCenter : Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: CallPromptCard(
                    key: ValueKey('${call.callId}|${call.phase.name}'),
                    status: call,
                    onAction: (a) => _callAction(call, a)),
              ),
            )))
      else
        Positioned(
            top: _anchorTop,
            left: S.s12,
            right: S.s12,
            child: SafeArea(
                child: Align(
              alignment: kMobile ? Alignment.topCenter : Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: reducedMotion ? Duration.zero : Motion.open,
                  reverseDuration: reducedMotion ? Duration.zero : Motion.close,
                  switchInCurve: Motion.enter,
                  switchOutCurve: Motion.exit,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, -.08), end: Offset.zero)
                          .animate(animation),
                      child: ScaleTransition(
                        alignment:
                            kMobile ? Alignment.topCenter : Alignment.topRight,
                        scale: Tween(begin: .96, end: 1.0).animate(animation),
                        child: child,
                      ),
                    ),
                  ),
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : MouseRegion(
                          onEnter: (_) => _setHold(pointer: true),
                          onExit: (_) => _setHold(pointer: false),
                          child: Listener(
                            onPointerDown: (_) => _setHold(pointer: true),
                            onPointerUp: (_) => _setHold(pointer: false),
                            onPointerCancel: (_) => _setHold(pointer: false),
                            child: Semantics(
                              label: items.length > 1
                                  ? '${items.length} notifications'
                                  : null,
                              child: NotificationStack(
                                items: items,
                                expanded: _expanded,
                                onToggle: () => setState(() {
                                  _expanded = !_expanded;
                                  _setHold();
                                }),
                                onClearAll: _clearAll,
                                cardBuilder: (payload, embedded, lifted) =>
                                    _card(payload, embedded, lifted,
                                        reducedMotion),
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
