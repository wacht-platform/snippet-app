import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';

/// Centralized keyboard shortcut handler for the desktop shell.
class ShellShortcutsHandler {
  final void Function() onCloseActiveTab;
  final void Function() onNewSession;
  final void Function(int delta) onActivateRelativeTab;
  final void Function() onOpenActiveFiles;
  final void Function() onOpenMacGit;
  final void Function() onStopRunningTask;
  final void Function() onShowShortcuts;
  final void Function(int index) onActivateTab;

  const ShellShortcutsHandler({
    required this.onCloseActiveTab,
    required this.onNewSession,
    required this.onActivateRelativeTab,
    required this.onOpenActiveFiles,
    required this.onOpenMacGit,
    required this.onStopRunningTask,
    required this.onShowShortcuts,
    required this.onActivateTab,
  });

  static bool _mod(LogicalKeyboardKey left, LogicalKeyboardKey right) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(left) || keys.contains(right);
  }

  static bool get metaDown =>
      _mod(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight);
  static bool get ctrlDown =>
      _mod(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight);
  static bool get altDown =>
      _mod(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight);
  static bool get shiftDown =>
      _mod(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
  static bool get cmdOrCtrl => metaDown || ctrlDown;

  /// Handles global key events and invokes corresponding actions.
  /// Returns `true` if the event was handled.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!cmdOrCtrl) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyW && !shiftDown && !altDown) {
      onCloseActiveTab();
      return true;
    }
    if (key == LogicalKeyboardKey.keyT && !shiftDown && !altDown) {
      onNewSession();
      return true;
    }
    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.pageDown) &&
        ctrlDown &&
        !altDown &&
        !metaDown) {
      onActivateRelativeTab(shiftDown ? -1 : 1);
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp &&
        ctrlDown &&
        !altDown &&
        !metaDown) {
      onActivateRelativeTab(-1);
      return true;
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        altDown) {
      onActivateRelativeTab(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && shiftDown && !altDown) {
      onOpenActiveFiles();
      return true;
    }
    if (key == LogicalKeyboardKey.keyG && shiftDown && !altDown) {
      onOpenMacGit();
      return true;
    }
    if (key == LogicalKeyboardKey.period && !shiftDown && !altDown) {
      onStopRunningTask();
      return true;
    }
    if (key == LogicalKeyboardKey.slash && !shiftDown && !altDown) {
      onShowShortcuts();
      return true;
    }
    for (var i = 0; i < 9; i++) {
      if (key.keyId == LogicalKeyboardKey.digit1.keyId + i &&
          !shiftDown &&
          !altDown) {
        onActivateTab(i);
        return true;
      }
    }
    return false;
  }
}

/// Displays modal sheet with keyboard shortcuts.
void showDesktopShortcutsDialog(BuildContext context) {
  Widget shortcutRow(String keys, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label, style: sans(13, color: AppColors.fg1))),
          Text(keys, style: mono(11, color: AppColors.fg3)),
        ]),
      );

  showAppSheet(
    context,
    title: 'Keyboard shortcuts',
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      shortcutRow('⌘/Ctrl T', 'New session'),
      shortcutRow('⌘/Ctrl W', 'Close active tab'),
      shortcutRow('⌘/Ctrl 1–9', 'Switch to tab'),
      shortcutRow('⌘ ⌥ ← / → · Ctrl Tab · Ctrl PageUp/PageDown',
          'Previous / next tab'),
      shortcutRow('⌘/Ctrl ⇧ F', 'Browse files'),
      shortcutRow('⌘/Ctrl ⇧ G', 'Open Git'),
      shortcutRow('⌘/Ctrl .', 'Stop active run'),
      shortcutRow('⌘/Ctrl Enter', 'Send message'),
    ]),
  );
}
