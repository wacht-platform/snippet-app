import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// True on phones/tablets (Android/iOS). Desktop (macOS/Linux/Windows) and web
/// are false. Used to guard mobile-only plugins (foreground task, camera
/// permissions) that have no desktop support, and to pick the layout.
bool get kMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Desktop platforms where we watch /events in-process and raise native local
/// notifications (no foreground service — the app stays running). macOS + Linux.
bool get kDesktopNotify =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// True wherever the recorder can capture voice input. macOS uses the native
/// record_macos plugin and requests permission through AudioRecorder itself.
bool get kCanRecord => kMobile || kMacOS;

/// True wherever we can deliver session notifications at all.
bool get kCanNotify => kMobile || kDesktopNotify;

/// macOS specifically — the window draws full-size content, so the traffic-light
/// controls overlay the top-left; the shell insets its top to clear them.
bool get kMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Windows desktop. The runner builds and core features work, but a few
/// plugins have no Windows implementation (video_player, open_filex) — call
/// sites guard on this to fall back instead of throwing MissingPluginException.
bool get kWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Height to reserve at the top for the macOS window controls.
const double kMacTitlebar = 28.0;
const _windowStateChannel = MethodChannel('snippet/window_state');

/// Whether macOS is in native full-screen mode. Other platforms never need a
/// title-bar reservation here, and an unavailable native channel is safe to
/// treat as a normal window.
Future<bool> macOSIsFullscreen() async {
  if (!kMacOS) return false;
  try {
    return await _windowStateChannel.invokeMethod<bool>('isFullscreen') ??
        false;
  } catch (_) {
    return false;
  }
}

/// The desktop layout (sidebar + panes) kicks in at/above this logical width.
const double kDesktopBreakpoint = 900;

/// Below this shell width the persistent sidebar collapses into a drawer (the
/// desktop shell stays native — it never falls back to the phone UI).
const double kShellCompact = 720;
