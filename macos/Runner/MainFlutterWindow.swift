import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Height of the title bar the app paints itself. Must match
  /// `kTitleBarHeight` in lib/platform.dart.
  private let paintedTitleBarHeight: CGFloat = 40

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Floor for resizing. Below this the three-pane desktop layout
    // (sidebar 300 + chat + secondary pane 280) has no room and the chrome
    // starts clipping, so the window refuses to go smaller.
    //
    // Deliberately BELOW the Flutter desktop breakpoint (900) so the
    // narrow-desktop drawer layout stays reachable between 800 and 900 —
    // pinning the floor at 900 would make that path dead code on macOS.
    self.minSize = NSSize(width: 800, height: 600)
    // Use the native traffic lights, but let Flutter paint a cohesive title
    // surface beneath them instead of leaving a separate blank title strip.
    self.title = "snippet"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    // Drag only the painted title surface. Leaving this false prevents a drag
    // from stealing clicks, text selection, and scrolling from the app body.
    self.isMovableByWindowBackground = false
    // Start maximized within the current display's usable frame (below the
    // menu bar and above the Dock), rather than using the small template size.
    if let visibleFrame = NSScreen.main?.visibleFrame {
      self.setFrame(visibleFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    let windowStateChannel = FlutterMethodChannel(
      name: "snippet/window_state",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowStateChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "isFullscreen" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.styleMask.contains(.fullScreen) ?? false)
    }

    super.awakeFromNib()

    // AppKit sizes the native titlebar for a ~28pt band and centres the traffic
    // lights in it. The app paints a taller bar, so the lights would sit high
    // in it. Re-centre them for the painted height, and re-apply on relayout.
    centreTrafficLights()
    let events: [Notification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
    ]
    for name in events {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(onWindowLayoutChanged),
        name: name,
        object: self)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func onWindowLayoutChanged() {
    centreTrafficLights()
  }

  /// Move the standard window buttons so they are vertically centred in the
  /// height the app paints, rather than in AppKit's own shorter titlebar band.
  ///
  /// Each button is offset by the delta between its current centre and the
  /// desired one, so the call is idempotent and self-correcting if AppKit
  /// re-lays-out the buttons on its own.
  private func centreTrafficLights() {
    guard let closeButton = standardWindowButton(.closeButton),
          let container = closeButton.superview else { return }

    let containerHeight = container.bounds.height
    guard containerHeight > 0 else { return }

    // AppKit's titlebar container is normally unflipped (origin bottom-left),
    // but handle both so the offset can never be applied in the wrong direction.
    let centreFromTop = paintedTitleBarHeight / 2
    let targetCentreY = container.isFlipped
      ? centreFromTop
      : containerHeight - centreFromTop

    let types: [NSWindow.ButtonType] = [
      .closeButton, .miniaturizeButton, .zoomButton,
    ]
    for type in types {
      guard let button = standardWindowButton(type) else { continue }
      var frame = button.frame
      let delta = targetCentreY - frame.midY
      if abs(delta) < 0.5 { continue }
      frame.origin.y += delta
      button.frame = frame
    }
  }
}
