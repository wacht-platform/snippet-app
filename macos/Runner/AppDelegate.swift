import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let bundleID = Bundle.main.bundleIdentifier
    let duplicate = NSWorkspace.shared.runningApplications.first { app in
      app != NSRunningApplication.current &&
        bundleID != nil && app.bundleIdentifier == bundleID
    }
    if let duplicate {
      duplicate.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      NSApp.terminate(nil)
      return
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
