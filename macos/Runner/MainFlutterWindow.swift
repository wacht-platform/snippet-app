import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let flutterTitlebarHeight: CGFloat = 38

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.minSize = NSSize(width: 720, height: 500)
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
  }

}
