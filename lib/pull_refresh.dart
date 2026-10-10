import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// Refresh by pulling past the top of a list.
///
/// Phones get the standard pull-down. Desktop has nothing to pull, so a hard
/// scroll upward while already at the top (wheel or trackpad) refreshes; a
/// gentle scroll that merely reaches the top does not.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  static const _threshold = 260.0;
  static const _window = Duration(milliseconds: 450);

  bool _atTop = true;
  double _pull = 0;
  DateTime _lastPull = DateTime.fromMillisecondsSinceEpoch(0);
  bool _refreshing = false;

  void _addPull(double amount) {
    if (_refreshing || amount <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastPull) > _window) _pull = 0;
    _lastPull = now;
    _pull += amount;
    if (_pull >= _threshold) {
      _pull = 0;
      unawaited(_run());
    }
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    _atTop = m.pixels <= m.minScrollExtent + 0.5;
    if (n is OverscrollNotification && n.overscroll < 0) {
      _addPull(-n.overscroll);
    } else if (n is ScrollUpdateNotification &&
        m.pixels < m.minScrollExtent &&
        (n.scrollDelta ?? 0) < 0) {
      _addPull(-(n.scrollDelta ?? 0));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (kMobile) {
      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: widget.onRefresh,
        child: widget.child,
      );
    }
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && _atTop && e.scrollDelta.dy < 0) {
          _addPull(-e.scrollDelta.dy);
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) {
            if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
              _atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 0.5;
            }
            return false;
          },
          child: Stack(children: [
            widget.child,
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: !_refreshing
                        ? const SizedBox.shrink()
                        : Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surface3,
                              shape: BoxShape.circle,
                            ),
                            child: Spinner(size: 14, color: AppColors.accent),
                          ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
