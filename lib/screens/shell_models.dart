import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../share_inbound.dart';
import 'mission_control.dart';

/// Which pane a tab lives in. Both panes are tab containers, so this is a
/// property OF a tab, not of the shell — dragging a tab across the divider is
/// what moves it.
enum ShellPane { left, right }

/// Which top-level place the phone home is showing. The floating action bar
/// switches this; desktop keeps its sidebar rail instead, so this is phone-only.
enum MobileHome {
  agents('Agents', 'agent'),
  chats('Chats', 'chat-thread'),
  settings('Settings', 'settings');

  const MobileHome(this.label, this.icon);
  final String label;
  final String icon;
}

/// Floating action bar geometry. Kept local: it is the only floating surface in
/// the app, so it has not earned a shared token — but the radius is deliberately
/// larger than `R.card` so it reads as a float rather than another card.
const double kMobileBarHeight = 58;
const double kMobileBarRadius = 18;

/// One open tab in the shell — a live chat session, an opened file, a single git
/// change, or a terminal, on a given instance.
///
/// Terminals are tabs like anything else, because the nested space is a tab
/// container: opening a second terminal gives you a second tab, not a second
/// app-wide pane.
class ShellTab {
  final DaemonClient client;
  final String instanceUrl;
  final String? sessionId;
  final String? filePath;
  String title;
  String? profile;
  SharedInbound? inboundShare;

  /// Which pane this tab is shown in. Mutable: this is what a drag changes.
  ShellPane pane;

  /// The locked conversation root of the inner tab group this item belongs to.
  /// A group shows exactly one session root; its files, diffs and terminals sit
  /// alongside it in the full-width strip. Null is only valid for a session
  /// root itself, or for a legacy item that will be adopted by the active root.
  String? groupSessionKey;

  /// Set only for a diff tab: the changed file plus the view it should show.
  /// A staged-only file reads the index diff; an untracked one shows as an add.
  final String? diffPath;
  final bool diffStaged;
  final bool diffUntracked;

  /// Set only for a terminal tab.
  ///
  /// [termSessionKey] is the shell key of the session that owns the pty when the
  /// shell is SESSION-scoped. It is NULL for a daemon-wide shell, which belongs
  /// to the machine rather than a conversation — those render from
  /// `ShellsController` over `/shells`.
  final String? termId;
  final String? termSessionKey;

  ShellTab.session({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.title,
    this.profile,
    this.inboundShare,
    this.pane = ShellPane.left,
    this.groupSessionKey,
  })  : filePath = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false,
        termId = null,
        termSessionKey = null;

  ShellTab.file({
    required this.client,
    required this.instanceUrl,
    required this.filePath,
    required this.title,
    this.pane = ShellPane.left,
    this.groupSessionKey,
  })  : sessionId = null,
        profile = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false,
        termId = null,
        termSessionKey = null;

  ShellTab.diff({
    required this.client,
    required this.instanceUrl,
    required this.sessionId,
    required this.diffPath,
    required this.title,
    required this.diffStaged,
    required this.diffUntracked,
    this.pane = ShellPane.left,
    this.groupSessionKey,
  })  : filePath = null,
        profile = null,
        termId = null,
        termSessionKey = null;

  ShellTab.terminal({
    required this.client,
    required this.instanceUrl,
    required this.termId,
    required this.title,
    this.termSessionKey,
    this.pane = ShellPane.left,
    this.groupSessionKey,
  })  : sessionId = null,
        filePath = null,
        profile = null,
        diffPath = null,
        diffStaged = false,
        diffUntracked = false;

  bool get isFile => filePath != null;
  bool get isDiff => diffPath != null;
  bool get isTerminal => termId != null;
  bool get isMissionControl =>
      !isFile &&
      !isDiff &&
      !isTerminal &&
      isMissionControlTab(sessionId: sessionId, title: title);
  String get key => isTerminal
      ? '$instanceUrl|term|${termSessionKey ?? 'global'}|$termId'
      : isDiff
          ? '$instanceUrl|diff|$diffPath|$diffStaged'
          : isFile
              ? '$instanceUrl|file|$filePath'
              : isMissionControl
                  ? '$instanceUrl|mission-control'
                  : '$instanceUrl|$sessionId';
}

/// Icon for a tab, by kind. One helper so the four call sites that render a
/// tab (top bar, desktop strip, split header, tab menu) cannot drift.
String tabIconKind(ShellTab t) => t.isMissionControl
    ? 'layers'
    : t.isTerminal
        ? 'terminal'
        : t.isDiff
            ? 'git-branch'
            : t.isFile
                ? 'file'
                : 'chat-thread';

class MacSessionStatus {
  final HarnessState? state;
  final bool running;
  const MacSessionStatus(this.state, this.running);
}

class MacSessionControls {
  final VoidCallback stop;
  final void Function(String action, [String? extra]) performAction;
  const MacSessionControls(this.stop, this.performAction);
}

/// Session readouts that render in the secondary pane.
///
/// These were drawers. A drawer covers the transcript, but Lanes / Checkpoints
/// are exactly the things you check WHILE reading a session — so they belong
/// beside it, and tapping the same band button again closes the pane.
///
/// Usage is deliberately NOT here. It is a per-provider, account-wide view, so
/// it lives in Settings → Usage rather than being reachable from a single
/// conversation.
enum RightPanel {
  none('', ''),
  lanes('Lanes', 'layers'),
  tasks('Tasks', 'layers'),
  recurring('Scheduled', 'scheduled'),
  checkpoints('Checkpoints', 'history');

  const RightPanel(this.label, this.icon);
  final String label;
  final String icon;
}

/// One tab in the secondary pane's readout strip.
///
/// Readouts are a LIST, not a single selection. Lanes, Checkpoints, Usage and a
/// named agent are independent things you may want open at the same time;
/// keeping one meant closing one to open another, which is why they are tabs
/// here rather than one exclusive mode.
class RightTab {
  RightTab.panel(this.panel)
      : agent = null,
        pane = ShellPane.right;
  RightTab.agent(CoordinationAgent this.agent)
      : panel = RightPanel.none,
        pane = ShellPane.right;

  final RightPanel panel;
  final CoordinationAgent? agent;

  /// Which pane holds this readout.
  ///
  /// Mutable, and the reason a readout is a TAB rather than a read-only panel:
  /// anything in a pane's strip can be dragged to the other pane. Without this
  /// the secondary pane had nothing draggable at all when it held a readout,
  /// so right-to-left drags simply never started.
  ShellPane pane;

  bool get isAgent => agent != null;

  /// Stable identity, so re-opening a panel focuses its tab instead of adding
  /// a duplicate.
  String get key => isAgent ? 'agent|${agent!.id}' : 'panel|${panel.name}';

  String get label {
    final a = agent;
    if (a == null) return panel.label;
    return a.displayName.trim().isEmpty ? a.id : a.displayName;
  }

  String get icon => isAgent ? 'users' : panel.icon;
}
