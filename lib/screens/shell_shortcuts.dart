import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';

/// Centralized keyboard shortcut handler for the desktop shell.
class ShellShortcutsHandler {
  final void Function() onCloseActiveTab;
  final void Function() onNewSession;
  final void Function(int delta) onActivateRelativeTab;
  final void Function(int index) onActivateTab;
  final void Function() onOpenActiveFiles;
  final void Function() onOpenMacGit;
  final void Function()? onToggleSidebar;
  final void Function()? onToggleRightPanel;
  final void Function()? onOpenCommandPalette;
  final void Function()? onFocusComposer;
  final void Function() onStopRunningTask;
  final void Function() onShowShortcuts;

  const ShellShortcutsHandler({
    required this.onCloseActiveTab,
    required this.onNewSession,
    required this.onActivateRelativeTab,
    required this.onActivateTab,
    required this.onOpenActiveFiles,
    required this.onOpenMacGit,
    this.onToggleSidebar,
    this.onToggleRightPanel,
    this.onOpenCommandPalette,
    this.onFocusComposer,
    required this.onStopRunningTask,
    required this.onShowShortcuts,
  });

  static bool get metaDown =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.metaRight) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.meta);

  static bool get ctrlDown =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlRight) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.control);

  static bool get altDown =>
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altRight) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.alt);

  static bool get shiftDown =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftRight) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shift);

  static bool get cmdOrCtrl => metaDown || ctrlDown;

  /// Handles global key events and invokes corresponding actions.
  /// Returns `true` if the event was handled.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    // 1. Tab navigation via Alt without Cmd/Ctrl (Linux/Windows standard)
    if (!cmdOrCtrl && altDown && !shiftDown) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        onActivateRelativeTab(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        onActivateRelativeTab(1);
        return true;
      }
      // Alt + 1..9 (Linux/Windows tab jumping)
      for (var i = 0; i < 9; i++) {
        if (key.keyId == LogicalKeyboardKey.digit1.keyId + i ||
            key.keyId == LogicalKeyboardKey.numpad1.keyId + i) {
          onActivateTab(i);
          return true;
        }
      }
    }

    // Help shortcut: F1 (without modifiers)
    if (key == LogicalKeyboardKey.f1 && !cmdOrCtrl && !altDown && !shiftDown) {
      onShowShortcuts();
      return true;
    }

    // Remaining shortcuts require Cmd (macOS) or Ctrl (Linux/Windows)
    if (!cmdOrCtrl) return false;

    // Close active tab: Cmd/Ctrl + W
    if (key == LogicalKeyboardKey.keyW && !shiftDown && !altDown) {
      onCloseActiveTab();
      return true;
    }

    // New session: Cmd/Ctrl + T
    if (key == LogicalKeyboardKey.keyT && !shiftDown && !altDown) {
      onNewSession();
      return true;
    }

    // Toggle Left Sidebar: Cmd/Ctrl + B
    if (key == LogicalKeyboardKey.keyB && !shiftDown && !altDown) {
      if (onToggleSidebar != null) {
        onToggleSidebar!();
        return true;
      }
    }

    // Toggle Secondary/Right Panel: Cmd/Ctrl + \
    if (key == LogicalKeyboardKey.backslash && !shiftDown && !altDown) {
      if (onToggleRightPanel != null) {
        onToggleRightPanel!();
        return true;
      }
    }

    // Command Palette: Cmd/Ctrl + K or Cmd/Ctrl + P
    if ((key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.keyP) &&
        !shiftDown &&
        !altDown) {
      if (onOpenCommandPalette != null) {
        onOpenCommandPalette!();
        return true;
      }
    }

    // Focus Composer: Cmd/Ctrl + L
    if (key == LogicalKeyboardKey.keyL && !shiftDown && !altDown) {
      if (onFocusComposer != null) {
        onFocusComposer!();
        return true;
      }
    }

    // Tab switching: Ctrl + Tab / Ctrl + Shift + Tab, Ctrl + PageUp / PageDown
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

    // Tab switching on macOS: Cmd + Shift + [ / ]
    if (metaDown && shiftDown && !altDown) {
      if (key == LogicalKeyboardKey.bracketLeft) {
        onActivateRelativeTab(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.bracketRight) {
        onActivateRelativeTab(1);
        return true;
      }
    }

    // Tab switching: Cmd/Ctrl + Alt + Left / Right
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        altDown) {
      onActivateRelativeTab(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      return true;
    }

    // File Tree: Cmd/Ctrl + Shift + E or Cmd/Ctrl + Shift + F
    if ((key == LogicalKeyboardKey.keyE || key == LogicalKeyboardKey.keyF) &&
        shiftDown &&
        !altDown) {
      onOpenActiveFiles();
      return true;
    }

    // Git Diff: Cmd/Ctrl + Shift + G
    if (key == LogicalKeyboardKey.keyG && shiftDown && !altDown) {
      onOpenMacGit();
      return true;
    }

    // Stop active running task: Cmd/Ctrl + .
    if (key == LogicalKeyboardKey.period && !shiftDown && !altDown) {
      onStopRunningTask();
      return true;
    }

    // Show shortcuts: Cmd/Ctrl + /
    if (key == LogicalKeyboardKey.slash && !shiftDown && !altDown) {
      onShowShortcuts();
      return true;
    }

    // Tab jumping: Cmd/Ctrl + 1..9
    for (var i = 0; i < 9; i++) {
      if ((key.keyId == LogicalKeyboardKey.digit1.keyId + i ||
              key.keyId == LogicalKeyboardKey.numpad1.keyId + i) &&
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
      shortcutRow('⌘/Ctrl 1–9 · Alt 1–9', 'Switch to tab'),
      shortcutRow('Ctrl Tab · Alt ← / → · ⌘ ⇧ [ / ]', 'Previous / next tab'),
      shortcutRow('⌘/Ctrl K · ⌘/Ctrl P', 'Command palette'),
      shortcutRow('⌘/Ctrl L', 'Focus message input'),
      shortcutRow('⌘/Ctrl B', 'Toggle sidebar'),
      shortcutRow('⌘/Ctrl \\', 'Toggle right panel'),
      shortcutRow('⌘/Ctrl ⇧ E · ⌘/Ctrl ⇧ F', 'File explorer'),
      shortcutRow('⌘/Ctrl ⇧ G', 'Git diff'),
      shortcutRow('⌘/Ctrl .', 'Stop active run'),
      shortcutRow('⌘/Ctrl / · F1', 'Show shortcuts'),
      shortcutRow('Enter · ⌘/Ctrl Enter', 'Send message'),
    ]),
  );
}
