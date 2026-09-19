import 'package:flutter/material.dart';

import 'shell_models.dart';
import 'shell_nav.dart' show kPaneMinWidth;
import 'shell_pane_view.dart';
import 'shell_rail.dart' show kSidebarWidth;

/// The two-pane desktop body row with drag-and-drop between split panes.
class ShellSplitView extends StatefulWidget {
  const ShellSplitView({
    super.key,
    required this.sidebar,
    required this.paneWidth,
    required this.leftCollapsed,
    required this.rightCollapsed,
    required this.leftTabs,
    required this.rightTabs,
    required this.readouts,
    required this.activeKey,
    required this.focusedPane,
    required this.statusForTab,
    required this.canCloseTab,
    required this.tabBodyBuilder,
    required this.readoutBodyBuilder,
    required this.fallbackBuilder,
    required this.onPaneResize,
    required this.onExpandPane,
    required this.onMoveTab,
    required this.onMoveReadout,
    required this.onActivateTab,
    required this.onActivateReadout,
    required this.onDismissTab,
    required this.onCloseReadout,
  });

  final Widget sidebar;
  final double paneWidth;
  final bool leftCollapsed;
  final bool rightCollapsed;
  final List<ShellTab> leftTabs;
  final List<ShellTab> rightTabs;
  final List<RightTab> readouts;
  final Map<ShellPane, String> activeKey;
  final ShellPane focusedPane;
  final String? Function(ShellTab tab) statusForTab;
  final bool Function(ShellTab tab) canCloseTab;
  final Widget Function(ShellTab tab, bool primary) tabBodyBuilder;
  final Widget Function(RightTab readout) readoutBodyBuilder;
  final Widget Function(ShellPane pane) fallbackBuilder;
  final ValueChanged<double> onPaneResize;
  final ValueChanged<ShellPane> onExpandPane;
  final void Function(ShellPane pane, ShellTab tab) onMoveTab;
  final void Function(ShellPane pane, RightTab readout) onMoveReadout;
  final void Function(ShellPane pane, ShellTab tab) onActivateTab;
  final void Function(ShellPane pane, RightTab readout) onActivateReadout;
  final void Function(ShellPane pane, ShellTab tab) onDismissTab;
  final ValueChanged<RightTab> onCloseReadout;

  @override
  State<ShellSplitView> createState() => _ShellSplitViewState();
}

class _ShellSplitViewState extends State<ShellSplitView> {
  ShellPane? _dragOverPane;
  bool _dragActive = false;

  ShellPane? _dragOriginOf(Object? data) {
    if (data is ShellTab) return data.pane;
    if (data is RightTab) return data.pane;
    return null;
  }

  Widget _dropOn(ShellPane p, Widget child) => DragTarget<Object>(
        onWillAcceptWithDetails: (d) => _dragOriginOf(d.data) != p,
        onAcceptWithDetails: (d) {
          setState(() => _dragOverPane = null);
          final data = d.data;
          if (data is ShellTab) {
            widget.onMoveTab(p, data);
          } else if (data is RightTab) {
            widget.onMoveReadout(p, data);
          }
        },
        onLeave: (_) {
          if (_dragOverPane == p) setState(() => _dragOverPane = null);
        },
        onMove: (d) {
          if (_dragOriginOf(d.data) != p && _dragOverPane != p) {
            setState(() => _dragOverPane = p);
          }
        },
        builder: (_, __, ___) => child,
      );

  Widget _paneView(ShellPane p, {bool roundRight = false}) {
    final list = p == ShellPane.left ? widget.leftTabs : widget.rightTabs;
    final readouts = [
      for (final r in widget.readouts)
        if (r.pane == p) r
    ];
    final key = widget.activeKey[p];

    final selectedTab = list.where((t) => t.key == key).firstOrNull;
    RightTab? selectedReadout;
    for (final r in readouts) {
      if (r.key == key) selectedReadout = r;
    }
    final shownTab = selectedTab ??
        (selectedReadout == null && list.isNotEmpty ? list.first : null);
    final shownReadout = selectedReadout ??
        (shownTab == null && readouts.isNotEmpty ? readouts.first : null);

    Widget content;
    if (list.isEmpty && readouts.isEmpty) {
      content = widget.fallbackBuilder(p);
    } else {
      content = Stack(children: [
        for (final t in list)
          Offstage(
            offstage: t != shownTab,
            child: widget.tabBodyBuilder(
              t,
              t == shownTab && widget.focusedPane == p,
            ),
          ),
        if (shownReadout != null) widget.readoutBodyBuilder(shownReadout),
      ]);
    }

    return PaneSurface(
      pane: p,
      roundRight: roundRight,
      droppable: _dragOverPane == p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isNotEmpty || readouts.isNotEmpty)
            PaneStrip(
              pane: p,
              tabs: list,
              readouts: readouts,
              activeKey: key,
              statusForTab: widget.statusForTab,
              canDismissTab: (t) => widget.canCloseTab(t) || t.isTerminal,
              onActivateTab: (t) => widget.onActivateTab(p, t),
              onDismissTab: (t) => widget.onDismissTab(p, t),
              onActivateReadout: (r) => widget.onActivateReadout(p, r),
              onCloseReadout: widget.onCloseReadout,
              onDragStarted: () => setState(() => _dragActive = true),
              onDragEnd: (_) {
                if (_dragActive || _dragOverPane != null) {
                  setState(() {
                    _dragActive = false;
                    _dragOverPane = null;
                  });
                }
              },
            ),
          Expanded(child: content),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showRight = _dragActive ||
        (!widget.rightCollapsed &&
            (widget.rightTabs.isNotEmpty ||
                widget.readouts.any((r) => r.pane == ShellPane.right)));
    final showLeft = !(widget.leftCollapsed && widget.leftTabs.isNotEmpty);

    return Expanded(
      child: Row(children: [
        SizedBox(
          width: kSidebarWidth,
          child: widget.sidebar,
        ),
        if (showLeft)
          Expanded(
            child: _dropOn(
              ShellPane.left,
              _paneView(ShellPane.left, roundRight: !showRight),
            ),
          )
        else
          Expanded(
            child: CollapsedPaneStub(
              pane: ShellPane.left,
              onExpand: () => widget.onExpandPane(ShellPane.left),
            ),
          ),
        if (showRight) ...[
          PaneResizeHandle(
            joinBaseline: showLeft,
            onResize: widget.onPaneResize,
          ),
          SizedBox(
            width: widget.paneWidth.clamp(kPaneMinWidth, double.infinity),
            child: _dropOn(
              ShellPane.right,
              _paneView(ShellPane.right, roundRight: true),
            ),
          ),
        ],
      ]),
    );
  }
}
