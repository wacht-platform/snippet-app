import AVFoundation
import Cocoa
import CoreText
import FlutterMacOS
import QuartzCore

// MARK: - Snippet Theme & Bundled Font Loader (Geist + JetBrainsMono + Graphite Palette)

enum SnippetTheme {
  static var fontsRegistered = false

  static func ensureFontsRegistered() {
    guard !fontsRegistered else { return }
    fontsRegistered = true
    let candidates: [URL?] = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/App.framework/Resources/flutter_assets/assets/fonts"),
      Bundle.main.resourceURL?.appendingPathComponent("flutter_assets/assets/fonts"),
    ]
    let fm = FileManager.default
    for dirOpt in candidates {
      guard let dir = dirOpt, let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
        continue
      }
      for url in items where url.pathExtension.lowercased() == "ttf" {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }
    }
  }

  static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    ensureFontsRegistered()
    let name = weight.rawValue >= NSFont.Weight.medium.rawValue ? "Geist-Medium" : "Geist-Regular"
    if let font = NSFont(name: name, size: size) {
      return font
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
  }

  static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    ensureFontsRegistered()
    let name: String
    if weight.rawValue >= NSFont.Weight.semibold.rawValue {
      name = "JetBrainsMono-SemiBold"
    } else if weight.rawValue >= NSFont.Weight.medium.rawValue {
      name = "JetBrainsMono-Medium"
    } else {
      name = "JetBrainsMono-Regular"
    }
    if let font = NSFont(name: name, size: size) {
      return font
    }
    return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }

  // Exact Graphite (_amoled) palette from lib/theme.dart
  static let canvas = NSColor(srgbRed: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0D / 255.0, alpha: 1.0)
  static let bg = NSColor(srgbRed: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x12 / 255.0, alpha: 1.0)
  static let surface1 = NSColor(srgbRed: 0x17 / 255.0, green: 0x17 / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
  static let surface2 = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x22 / 255.0, alpha: 1.0)
  static let surface3 = NSColor(srgbRed: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
  static let border = NSColor(srgbRed: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
  static let border2 = NSColor(srgbRed: 0x32 / 255.0, green: 0x32 / 255.0, blue: 0x38 / 255.0, alpha: 1.0)
  static let fg1 = NSColor(srgbRed: 0xEE / 255.0, green: 0xEE / 255.0, blue: 0xF1 / 255.0, alpha: 1.0)
  static let fg2 = NSColor(srgbRed: 0xC4 / 255.0, green: 0xC4 / 255.0, blue: 0xCC / 255.0, alpha: 1.0)
  static let fg3 = NSColor(srgbRed: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x9B / 255.0, alpha: 1.0)
  static let fg4 = NSColor(srgbRed: 0x62 / 255.0, green: 0x62 / 255.0, blue: 0x6D / 255.0, alpha: 1.0)
  static let accent = NSColor(srgbRed: 0x8B / 255.0, green: 0x8D / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
  static let accentFill = NSColor(srgbRed: 0x5E / 255.0, green: 0x6A / 255.0, blue: 0xD2 / 255.0, alpha: 1.0)
  static let ok = NSColor(srgbRed: 0x4C / 255.0, green: 0xC3 / 255.0, blue: 0x8A / 255.0, alpha: 1.0)
  static let run = NSColor(srgbRed: 0xD9 / 255.0, green: 0x9E / 255.0, blue: 0x45 / 255.0, alpha: 1.0)
}

extension NSBezierPath {
  /// Exact quadratic Bezier curve using cubic control-point elevation so it works
  /// on every macOS deployment target (10.15+).
  func addQuadCurve(to endPoint: NSPoint, control controlPoint: NSPoint) {
    let startPoint = currentPoint
    let c1 = NSPoint(
      x: startPoint.x + (2.0 / 3.0) * (controlPoint.x - startPoint.x),
      y: startPoint.y + (2.0 / 3.0) * (controlPoint.y - startPoint.y)
    )
    let c2 = NSPoint(
      x: endPoint.x + (2.0 / 3.0) * (controlPoint.x - endPoint.x),
      y: endPoint.y + (2.0 / 3.0) * (controlPoint.y - endPoint.y)
    )
    curve(to: endPoint, controlPoint1: c1, controlPoint2: c2)
  }
}

// MARK: - Shared Mochi Vector Renderer (ported 1:1 from lib/mochi.dart)

enum MochiRenderer {
  /// Draws Snippet's Mochi mascot inside `rect` (in unflipped or flipped coordinates).
  private static func easeOut(_ t: CGFloat) -> CGFloat {
    let inv = 1.0 - t
    return 1.0 - inv * inv * inv
  }

  private static func easeIn(_ t: CGFloat) -> CGFloat {
    return t * t * t
  }

  /// Computes `WorkingMochi` bounce/squash/stretch/look/blink parameters from `phase` (in seconds).
  static func playMetrics(time: Double) -> (dy: CGFloat, sx: CGFloat, sy: CGFloat, look: CGFloat, blink: CGFloat) {
    let period = 1.4
    let t = CGFloat((time.truncatingRemainder(dividingBy: period)) / period)
    var dy: CGFloat = 0.0
    var sx: CGFloat = 1.0
    var sy: CGFloat = 1.0
    let h: CGFloat = 11.0
    if t < 0.18 {
      let e = easeOut(t / 0.18)
      sy = 1.0 - 0.15 * e
      sx = 1.0 + 0.11 * e
    } else if t < 0.50 {
      let p = (t - 0.18) / 0.32
      dy = -h * easeOut(p)
      sy = 1.0 + 0.09 * (1.0 - p)
      sx = 1.0 - 0.05 * (1.0 - p)
    } else if t < 0.72 {
      let p = (t - 0.50) / 0.22
      dy = -h * (1.0 - easeIn(p))
      sy = 1.0 + 0.05 * p
      sx = 1.0 - 0.03 * p
    } else if t < 0.86 {
      let k = CGFloat(sin(Double((t - 0.72) / 0.14) * Double.pi))
      sy = 1.0 - 0.16 * k
      sx = 1.0 + 0.12 * k
    }
    let blink: CGFloat = (t > 0.90 && t < 0.96) ? 1.0 : 0.0
    let look = CGFloat(sin(time / 0.9)) * 2.8
    return (dy: dy, sx: sx, sy: sy, look: look, blink: blink)
  }

  static func drawMochi(
    in rect: NSRect,
    bodyColor: NSColor,
    leafColor: NSColor,
    eyeColor: NSColor,
    blushColor: NSColor?,
    cutoutEyes: Bool = false,
    blink: CGFloat = 0.0,
    playTime: Double? = nil
  ) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    let metrics = playTime.map { playMetrics(time: $0) }
    let effBlink = metrics != nil ? max(blink, metrics!.blink) : blink
    let look = metrics?.look ?? 0.0
    let sx = metrics?.sx ?? 1.0
    let sy = metrics?.sy ?? 1.0
    let dy = metrics?.dy ?? 0.0

    // Map the 84x84 logical Mochi canvas into `rect` with bottom-center squash/stretch
    let scale = min(rect.width, rect.height) / 84.0
    ctx.translateBy(x: rect.midX, y: rect.minY)
    ctx.scaleBy(x: sx, y: sy)
    ctx.translateBy(x: -rect.width / 2.0, y: 0.0)
    ctx.translateBy(x: 0.0, y: rect.height)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -18.0, y: -22.0 + dy)

    // 1. Mochi dome body
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 20, y: 84))
    body.addCurve(
      to: CGPoint(x: 60, y: 38),
      control1: CGPoint(x: 20, y: 54),
      control2: CGPoint(x: 38, y: 38)
    )
    body.addCurve(
      to: CGPoint(x: 100, y: 84),
      control1: CGPoint(x: 82, y: 38),
      control2: CGPoint(x: 100, y: 54)
    )
    body.addCurve(
      to: CGPoint(x: 60, y: 100),
      control1: CGPoint(x: 100, y: 98),
      control2: CGPoint(x: 84, y: 100)
    )
    body.addCurve(
      to: CGPoint(x: 20, y: 84),
      control1: CGPoint(x: 36, y: 100),
      control2: CGPoint(x: 20, y: 98)
    )
    body.closeSubpath()

    ctx.addPath(body)
    ctx.setFillColor(bodyColor.cgColor)
    ctx.fillPath()

    // 2. Top sprout leaf
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 60, y: 37))
    leaf.addQuadCurve(to: CGPoint(x: 82, y: 24), control: CGPoint(x: 66, y: 21))
    leaf.addQuadCurve(to: CGPoint(x: 60, y: 37), control: CGPoint(x: 75, y: 39))
    leaf.closeSubpath()

    ctx.addPath(leaf)
    ctx.setFillColor(leafColor.cgColor)
    ctx.fillPath()

    // 3. Blush cheeks (for full-color rendering)
    if let blush = blushColor, !cutoutEyes {
      ctx.setFillColor(blush.cgColor)
      ctx.fillEllipse(in: CGRect(x: 39 - 7.5, y: 81 - 4.0, width: 15, height: 8))
      ctx.fillEllipse(in: CGRect(x: 81 - 7.5, y: 81 - 4.0, width: 15, height: 8))
    }

    // 4. Eyes + w-mouth
    let r: CGFloat = cutoutEyes ? 5.8 : 4.8
    let ry: CGFloat = max(1.2, r * (1.0 - effBlink * 0.85))
    let leftEye = CGRect(x: 48.0 + look - r, y: 72.0 - ry, width: r * 2, height: ry * 2)
    let rightEye = CGRect(x: 72.0 + look - r, y: 72.0 - ry, width: r * 2, height: ry * 2)

    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 54, y: 80))
    mouth.addQuadCurve(to: CGPoint(x: 60, y: 80), control: CGPoint(x: 57, y: 84))
    mouth.addQuadCurve(to: CGPoint(x: 66, y: 80), control: CGPoint(x: 63, y: 84))

    if cutoutEyes {
      ctx.setBlendMode(.clear)
      ctx.fillEllipse(in: leftEye)
      ctx.fillEllipse(in: rightEye)
      ctx.addPath(mouth)
      ctx.setLineWidth(3.2)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      ctx.strokePath()
      ctx.setBlendMode(.normal)
    } else {
      ctx.setFillColor(eyeColor.cgColor)
      ctx.fillEllipse(in: leftEye)
      ctx.fillEllipse(in: rightEye)
      ctx.addPath(mouth)
      ctx.setStrokeColor(eyeColor.cgColor)
      ctx.setLineWidth(3.0)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      ctx.strokePath()
    }

    ctx.restoreGState()
  }

  /// Pre-rendered 60fps frame table (84 frames = 1.4s loop at 60fps) so the menu bar
  /// animates at a locked 60fps with zero per-frame CGPath/NSImage allocation.
  private static let menuBarFrames: [NSImage] = {
    let count = 84
    let period = 1.4
    let size = NSSize(width: 20, height: 20)
    return (0..<count).map { i in
      let t = (Double(i) / Double(count)) * period
      let img = NSImage(size: size)
      img.lockFocus()
      drawMochi(
        in: NSRect(origin: .zero, size: size).insetBy(dx: 1.0, dy: 1.0),
        bodyColor: NSColor(srgbRed: 0.725, green: 0.776, blue: 1.0, alpha: 1.0),
        leafColor: NSColor(srgbRed: 0.498, green: 0.820, blue: 0.651, alpha: 1.0),
        eyeColor: NSColor(srgbRed: 0.082, green: 0.086, blue: 0.110, alpha: 1.0),
        blushColor: NSColor(srgbRed: 0.949, green: 0.655, blue: 0.627, alpha: 0.90),
        cutoutEyes: false,
        playTime: t
      )
      img.unlockFocus()
      img.isTemplate = false
      return img
    }
  }()

  static func makeMenuBarIcon(playTime: Double) -> NSImage {
    let period = 1.4
    let norm = (playTime.truncatingRemainder(dividingBy: period)) / period
    let idx = max(0, min(menuBarFrames.count - 1, Int(norm * Double(menuBarFrames.count))))
    return menuBarFrames[idx]
  }
}

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// Height of the title bar the app paints itself. Must match
  /// `kTitleBarHeight` in lib/platform.dart.
  private let paintedTitleBarHeight: CGFloat = 40

  private var statusItem: NSStatusItem?
  private var ambientMenuItem: NSMenuItem?
  private var notchHUD: NotchHUDController?
  private var notchChannel: FlutterMethodChannel?
  private var aecEngine: MacosVoiceProcessingEngine?
  private var blurView: NSVisualEffectView?
  private var backdropTimer: Timer?
  private var menuMochiTimer: Timer?
  private var isBackdropOpaque = false
  private var allowTerminate = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    self.contentViewController = flutterViewController
    // Floor for resizing: sidebar, a readable chat column and the session's
    // file tree side by side. Below this the desktop layout clips.
    self.minSize = NSSize(width: 1100, height: 700)
    self.isOpaque = false
    self.backgroundColor = .clear
    self.appearance = NSAppearance(named: .darkAqua)
    self.delegate = self

    let wrapper = flutterViewController.view
    let blur = NSVisualEffectView()
    blur.translatesAutoresizingMaskIntoConstraints = false
    blur.blendingMode = .behindWindow
    blur.material = .hudWindow
    blur.state = .active
    blur.appearance = NSAppearance(named: .darkAqua)
    wrapper.addSubview(blur, positioned: .below, relativeTo: nil)
    NSLayoutConstraint.activate([
      blur.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
      blur.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
      blur.topAnchor.constraint(equalTo: wrapper.topAnchor),
      blur.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])
    self.blurView = blur

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

    let notchChan = FlutterMethodChannel(
      name: "snippet/macos_notch",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.notchChannel = notchChan

    let hud = NotchHUDController(
      onActivateWindow: { [weak self] in
        self?.restoreFromMenuBar()
      },
      onOpenInApp: { [weak self] payload in
        self?.restoreFromMenuBar()
        if !payload.isEmpty {
          self?.notchChannel?.invokeMethod("onNotificationTap", arguments: payload)
        }
      },
      onOpenConversation: { [weak self] payload in
        self?.notchChannel?.invokeMethod("openConversation", arguments: payload)
      },
      onSendReply: { [weak self] text in
        self?.notchChannel?.invokeMethod("sendConversationReply", arguments: ["text": text])
      },
      onCloseConversation: { [weak self] in
        self?.notchChannel?.invokeMethod("closeConversation", arguments: nil)
      }
    )
    self.notchHUD = hud

    notchChan.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "updateAmbient":
        if let args = call.arguments as? [String: Any] {
          let active = args["active"] as? Bool ?? false
          let userSpeaking = args["userSpeaking"] as? Bool ?? false
          let assistantSpeaking = args["assistantSpeaking"] as? Bool ?? false
          let probability = args["probability"] as? Double ?? 0.0
          self.updateAmbientState(
            active: active,
            userSpeaking: userSpeaking,
            assistantSpeaking: assistantSpeaking,
            probability: probability
          )
        }
        result(nil)
      case "showNotification":
        if let args = call.arguments as? [String: Any] {
          let title = args["title"] as? String ?? "Snippet"
          let subtitle = args["subtitle"] as? String ?? ""
          let kind = args["kind"] as? String ?? ""
          let payload = args["payload"] as? String ?? ""
          let isMinimizedOrHidden = !self.isVisible || self.isMiniaturized
          if isMinimizedOrHidden {
            self.notchHUD?.presentNotification(
              title: title,
              subtitle: subtitle,
              kind: kind,
              payload: payload
            )
          }
        }
        result(nil)
      case "updateConversation":
        if let args = call.arguments as? [String: Any] {
          let title = args["title"] as? String ?? "Conversation"
          let status = args["status"] as? String ?? "idle"
          let rawMsgs = args["messages"] as? [[String: Any]] ?? []
          let messages: [(role: String, text: String, meta: String)] = rawMsgs.compactMap { m in
            guard let text = m["text"] as? String, !text.isEmpty else { return nil }
            let role = m["role"] as? String ?? "assistant"
            let meta = m["meta"] as? String ?? ""
            return (role: role, text: text, meta: meta)
          }
          self.notchHUD?.updateConversation(title: title, status: status, messages: messages)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let aec = MacosVoiceProcessingEngine()
    self.aecEngine = aec
    aec.register(with: flutterViewController.engine.binaryMessenger)

    setupMenuBarItem()

    super.awakeFromNib()

    self.isOpaque = false
    self.backgroundColor = .clear
    flutterViewController.backgroundColor = .clear
    self.appearance = NSAppearance(named: .darkAqua)

    centreTrafficLights()
    let events: [Notification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didMoveNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
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

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(onWindowLayoutChanged),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(onWindowLayoutChanged),
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil)

    SnippetTheme.ensureFontsRegistered()
    updateBackdropTransparency()
    backdropTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
      self?.updateBackdropTransparency()
    }
    menuMochiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      self.statusItem?.button?.image = MochiRenderer.makeMenuBarIcon(
        playTime: CACurrentMediaTime()
      )
    }
    if let timer = menuMochiTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  deinit {
    backdropTimer?.invalidate()
    menuMochiTimer?.invalidate()
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func onWillTerminate() {
    allowTerminate = true
  }

  // MARK: - NSWindowDelegate (Close / Minimize to Menu Bar & Notch)

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if allowTerminate {
      return true
    }
    self.orderOut(nil)
    notchHUD?.setWindowHidden(true)
    return false
  }

  func windowDidMiniaturize(_ notification: Notification) {
    notchHUD?.setWindowHidden(true)
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    notchHUD?.setWindowHidden(false)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    notchHUD?.setWindowHidden(false)
  }

  func restoreFromMenuBar() {
    if self.isMiniaturized {
      self.deminiaturize(nil)
    }
    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    notchHUD?.setWindowHidden(false)
  }

  // MARK: - Menu Bar Status Item

  private func setupMenuBarItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let btn = item.button {
      btn.image = MochiRenderer.makeMenuBarIcon(playTime: CACurrentMediaTime())
      btn.imagePosition = .imageOnly
      btn.toolTip = "Snippet"
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "Open Snippet",
      action: #selector(onMenuOpenSnippet),
      keyEquivalent: "o"
    )
    openItem.target = self
    menu.addItem(openItem)

    let mcNotchItem = NSMenuItem(
      title: "Mission Control Notch",
      action: #selector(onMenuOpenMissionControlNotch),
      keyEquivalent: "m"
    )
    mcNotchItem.target = self
    menu.addItem(mcNotchItem)

    menu.addItem(NSMenuItem.separator())

    let ambientItem = NSMenuItem(title: "Ambient Voice: Off", action: nil, keyEquivalent: "")
    ambientItem.isEnabled = false
    menu.addItem(ambientItem)
    self.ambientMenuItem = ambientItem

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit Snippet",
      action: #selector(onMenuQuitSnippet),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
    self.statusItem = item
  }

  @objc private func onMenuOpenSnippet() {
    restoreFromMenuBar()
  }

  @objc private func onMenuOpenMissionControlNotch() {
    if self.isVisible && !self.isMiniaturized {
      self.orderOut(nil)
      notchHUD?.setWindowHidden(true)
    }
    notchHUD?.openMissionControlConversation()
  }

  @objc private func onMenuQuitSnippet() {
    allowTerminate = true
    NSApp.terminate(nil)
  }

  private func updateAmbientState(
    active: Bool,
    userSpeaking: Bool,
    assistantSpeaking: Bool,
    probability: Double
  ) {
    if !active {
      ambientMenuItem?.title = "Ambient Voice: Off"
    } else if assistantSpeaking {
      ambientMenuItem?.title = "Ambient Voice: Speaking"
    } else if userSpeaking {
      ambientMenuItem?.title = "Ambient Voice: Hearing you"
    } else {
      ambientMenuItem?.title = "Ambient Voice: Listening"
    }
    notchHUD?.updateAmbient(
      active: active,
      userSpeaking: userSpeaking,
      assistantSpeaking: assistantSpeaking,
      probability: probability
    )
  }

  @objc private func onWindowLayoutChanged() {
    centreTrafficLights()
    updateBackdropTransparency()
  }

  /// Checks whether any normal on-screen application window sits behind this
  /// window's frame. When only the desktop wallpaper is behind Snippet, vibrancy
  /// and transparency stay active; when another window is behind us, the window
  /// switches to a solid opaque carbon backing so nothing bleeds through.
  private func hasApplicationWindowBehind() -> Bool {
    guard self.isVisible && !self.isMiniaturized && self.windowNumber > 0 else {
      return false
    }
    guard let primaryScreen = NSScreen.screens.first else {
      return false
    }
    let primaryH = primaryScreen.frame.height
    let f = self.frame
    // Convert AppKit bottom-left screen coordinates to CoreGraphics top-left screen coordinates.
    let cgSelfRect = CGRect(
      x: f.origin.x,
      y: primaryH - f.maxY,
      width: f.width,
      height: f.height
    ).insetBy(dx: 8, dy: 8)

    let options: CGWindowListOption = [.optionOnScreenBelowWindow, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, CGWindowID(self.windowNumber)) as? [[String: Any]] else {
      return false
    }
    let myPid = ProcessInfo.processInfo.processIdentifier
    for info in list {
      guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
            layer == 0 else {
        continue
      }
      if let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
         pid == myPid {
        continue
      }
      if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
         alpha <= 0.05 {
        continue
      }
      guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
            let winRect = CGRect(dictionaryRepresentation: boundsDict) else {
        continue
      }
      if winRect.width < 48 || winRect.height < 48 {
        continue
      }
      if cgSelfRect.intersects(winRect) {
        return true
      }
    }
    return false
  }

  private func updateBackdropTransparency() {
    let shouldBeOpaque = hasApplicationWindowBehind()
    guard shouldBeOpaque != isBackdropOpaque else { return }
    isBackdropOpaque = shouldBeOpaque
    if shouldBeOpaque {
      blurView?.isHidden = true
      self.backgroundColor = NSColor(srgbRed: 0x0D / 255.0, green: 0x0C / 255.0, blue: 0x0B / 255.0, alpha: 1.0)
    } else {
      blurView?.isHidden = false
      self.backgroundColor = .clear
    }
  }

  private func centreTrafficLights() {
    guard let closeButton = standardWindowButton(.closeButton),
          let container = closeButton.superview else { return }

    let containerHeight = container.bounds.height
    guard containerHeight > 0 else { return }

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

// MARK: - macOS Hardware Acoustic Echo Cancellation (VoiceProcessingIO) Engine
//
// Runs both 24kHz TTS playback (`AVAudioPlayerNode`) and 16kHz microphone
// capture (`inputNode`) on a single shared `AVAudioEngine` with
// `setVoiceProcessingEnabled(true)`. Apple's `VoiceProcessingIO` audio unit uses
// the engine's output bus as its reference signal and subtracts Snippet's spoken
// output from the microphone stream in hardware/kernel DSP before samples reach
// Flutter or Silero VAD.

final class MacosVoiceProcessingEngine: NSObject, FlutterStreamHandler {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let ttsFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
  private let lock = NSLock()

  private var configured = false
  private var micTapInstalled = false
  private var eventSink: FlutterEventSink?
  private var resamplePos: Double = 0.0
  private var scheduledFrames: Int = 0
  private var completedFrames: Int = 0

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "snippet/macos_aec",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "resetPlayer":
        if let args = call.arguments as? [String: Any],
           let vol = args["volume"] as? Double {
          self.setVolume(vol)
        }
        self.resetPlayer()
        result(nil)
      case "writeTts":
        if let args = call.arguments as? [String: Any],
           let typed = args["pcm"] as? FlutterStandardTypedData {
          if let vol = args["volume"] as? Double {
            self.setVolume(vol)
          }
          let head = self.writeTts(pcmData: typed.data)
          result(head)
        } else {
          result(self.currentHead())
        }
      case "setVolume":
        if let args = call.arguments as? [String: Any],
           let vol = args["volume"] as? Double {
          self.setVolume(vol)
        }
        result(nil)
      case "stopTts":
        self.stopTts()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "snippet/macos_aec_mic",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  private func ensureEngineRunning() throws {
    if !configured {
      engine.attach(playerNode)
      engine.connect(playerNode, to: engine.mainMixerNode, format: ttsFormat)

      // Enable Apple's hardware Acoustic Echo Canceller (VoiceProcessingIO) on
      // the shared engine so speaker output from `playerNode` is cancelled from
      // `inputNode` in real time.
      do {
        try engine.inputNode.setVoiceProcessingEnabled(true)
        engine.inputNode.isVoiceProcessingAGCEnabled = true
        if #available(macOS 14.0, *) {
          let duck = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: false,
            duckingLevel: .min
          )
          engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration = duck
        }
      } catch {
        // External audio interfaces that do not support VoiceProcessingIO fall back cleanly.
      }
      configured = true
    }
    if !engine.isRunning {
      engine.prepare()
      try engine.start()
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    do {
      try ensureEngineRunning()
      installMicTapIfNeeded()
      return nil
    } catch {
      return FlutterError(
        code: "AEC_ENGINE_ERROR",
        message: "Failed to start macOS voice processing audio engine: \(error.localizedDescription)",
        details: nil
      )
    }
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    removeMicTap()
    return nil
  }

  private func installMicTapIfNeeded() {
    guard !micTapInstalled else { return }
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    resamplePos = 0.0
    // Passing `format: nil` uses `input.outputFormat(forBus: 0)` (the post-AEC
    // output bus of VoiceProcessingIO), avoiding multi-channel input format mismatches.
    input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
      self?.handleMicBuffer(buffer)
    }
    micTapInstalled = true
  }

  private func removeMicTap() {
    guard micTapInstalled else { return }
    engine.inputNode.removeTap(onBus: 0)
    micTapInstalled = false
  }

  private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard eventSink != nil else { return }
    let frameLen = Int(buffer.frameLength)
    guard frameLen > 0 else { return }
    let inRate = buffer.format.sampleRate
    guard inRate > 0 else { return }

    // Extract channel 0 (the primary beamformed, echo-cancelled voice channel) as Float32
    var mono = [Float](repeating: 0, count: frameLen)
    if let floatData = buffer.floatChannelData {
      let ch0 = floatData[0]
      for i in 0..<frameLen {
        mono[i] = ch0[i]
      }
    } else if let int16Data = buffer.int16ChannelData {
      let ch0 = int16Data[0]
      for i in 0..<frameLen {
        mono[i] = Float(ch0[i]) / 32768.0
      }
    } else {
      return
    }

    // Resample from `inRate` (e.g. 48000 / 44100 Hz) to 16000 Hz s16le PCM
    let step = inRate / 16000.0
    var outBytes = Data()
    outBytes.reserveCapacity(Int(Double(frameLen) / step + 2) * 2)

    var pos = resamplePos
    while Int(pos) < frameLen {
      let idx = Int(pos)
      let frac = Float(pos - Double(idx))
      let s0 = mono[idx]
      let s1 = (idx + 1 < frameLen) ? mono[idx + 1] : s0
      let sample = s0 + (s1 - s0) * frac
      let clamped = max(-1.0, min(1.0, sample))
      let pcm16 = Int16(clamped * 32767.0)
      var le = pcm16.littleEndian
      withUnsafeBytes(of: &le) { ptr in
        outBytes.append(contentsOf: ptr)
      }
      pos += step
    }
    resamplePos = pos - Double(frameLen)

    if !outBytes.isEmpty {
      DispatchQueue.main.async { [weak self] in
        self?.eventSink?(FlutterStandardTypedData(bytes: outBytes))
      }
    }
  }

  private func resetPlayer() {
    lock.lock()
    scheduledFrames = 0
    completedFrames = 0
    lock.unlock()
    if playerNode.isPlaying {
      playerNode.stop()
    }
  }

  private func writeTts(pcmData: Data) -> Int {
    let sampleCount = pcmData.count / 2
    guard sampleCount > 0 else { return currentHead() }
    do {
      try ensureEngineRunning()
    } catch {
      return currentHead()
    }

    guard let pcmBuffer = AVAudioPCMBuffer(
      pcmFormat: ttsFormat,
      frameCapacity: AVAudioFrameCount(sampleCount)
    ), let dst = pcmBuffer.floatChannelData?[0] else {
      return currentHead()
    }
    pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)

    pcmData.withUnsafeBytes { rawPtr in
      guard let base = rawPtr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
      for i in 0..<sampleCount {
        let s = Int16(littleEndian: base[i])
        dst[i] = Float(s) / 32768.0
      }
    }

    lock.lock()
    scheduledFrames += sampleCount
    lock.unlock()

    playerNode.scheduleBuffer(pcmBuffer) { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      self.completedFrames += sampleCount
      self.lock.unlock()
    }
    if !playerNode.isPlaying {
      playerNode.play()
    }
    return currentHead()
  }

  private func currentHead() -> Int {
    lock.lock()
    let done = completedFrames
    let total = scheduledFrames
    lock.unlock()
    if playerNode.isPlaying,
       let nodeTime = playerNode.lastRenderTime,
       let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
      let hwSample = Int(playerTime.sampleTime)
      if hwSample > 0 {
        return min(total, max(done, hwSample))
      }
    }
    return min(total, done)
  }

  private func setVolume(_ vol: Double) {
    playerNode.volume = Float(max(0.0, min(1.0, vol)))
  }

  private func stopTts() {
    if playerNode.isPlaying {
      playerNode.stop()
    }
    lock.lock()
    completedFrames = scheduledFrames
    lock.unlock()
  }
}

// MARK: - Key-Capable Non-Activating Notch Panel

final class NotchPanel: NSPanel {
  override var canBecomeKey: Bool { return true }
  override var canBecomeMain: Bool { return false }
}

final class FlippedDocumentView: NSView {
  override var isFlipped: Bool { return true }
}

// MARK: - Markdown Parser & Attributed Renderer for Notch HUD

/// Zero-inset text view backed by the exact `NSLayoutManager` that measures its
/// line fragments, eliminating `NSTextFieldCell` padding & re-wrapping mismatches.
final class NotchTextView: NSView {
  private let storage: NSTextStorage
  private let layoutManager: NSLayoutManager
  private let textContainer: NSTextContainer
  let measuredSize: NSSize

  override var isFlipped: Bool { true }

  init(attributedString: NSAttributedString, maxWidth: CGFloat) {
    let safeMaxW = max(16, floor(maxWidth))
    let ts = NSTextStorage(attributedString: attributedString)
    let lm = NSLayoutManager()
    let tc = NSTextContainer(size: NSSize(width: safeMaxW, height: .greatestFiniteMagnitude))
    tc.lineFragmentPadding = 0
    lm.addTextContainer(tc)
    ts.addLayoutManager(lm)
    lm.ensureLayout(for: tc)

    let glyphRange = lm.glyphRange(for: tc)
    let used = lm.usedRect(for: tc)
    let rawNS = attributedString.string as NSString
    var maxLineRight: CGFloat = 0

    lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
      var charRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
      while charRange.length > 0 {
        let lastChar = rawNS.character(at: charRange.location + charRange.length - 1)
        if let scalar = UnicodeScalar(lastChar), CharacterSet.whitespacesAndNewlines.contains(scalar) {
          charRange.length -= 1
        } else {
          break
        }
      }
      guard charRange.length > 0 else { return }
      let visGlyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
      let visBounds = lm.boundingRect(forGlyphRange: visGlyphRange, in: tc)
      let lineRight = min(usedRect.maxX, visBounds.maxX)
      if lineRight > maxLineRight {
        maxLineRight = lineRight
      }
    }

    let tightW = maxLineRight > 0 ? min(safeMaxW, ceil(maxLineRight)) : min(safeMaxW, ceil(used.width))
    let tightH = max(18, ceil(used.height))
    self.storage = ts
    self.layoutManager = lm
    self.textContainer = tc
    self.measuredSize = NSSize(width: tightW, height: tightH)
    super.init(frame: NSRect(x: 0, y: 0, width: tightW, height: tightH))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let glyphRange = layoutManager.glyphRange(for: textContainer)
    guard glyphRange.length > 0 else { return }
    layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
  }
}

enum NotchMarkdown {
  enum Block {
    case text(NSAttributedString)
    case code(language: String, code: String)
  }

  static func makeTextView(_ attr: NSAttributedString, maxWidth: CGFloat) -> NotchTextView {
    return NotchTextView(attributedString: attr, maxWidth: maxWidth)
  }

  /// Strips raw Markdown tokens for a clean 1-line notification banner preview.
  static func plainPreview(_ raw: String) -> String {
    var s = raw
    // Convert [label](url) -> label
    if let linkRe = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)") {
      s = linkRe.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
    }
    // Strip heading prefixes, fences, backticks, bold/italic markers
    if let tokenRe = try? NSRegularExpression(pattern: "(^#+\\s*|```[a-zA-Z0-9_-]*|`+|\\*\\*+|__+)") {
      s = tokenRe.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    s = s.replacingOccurrences(of: "\n", with: " ")
    while s.contains("  ") {
      s = s.replacingOccurrences(of: "  ", with: " ")
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Parses a Markdown message into rich text blocks and fenced code blocks.
  static func parseBlocks(_ markdown: String, isUser: Bool) -> [Block] {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = normalized.components(separatedBy: "\n")
    var blocks: [Block] = []
    var proseLines: [String] = []
    var inCode = false
    var codeLang = ""
    var codeLines: [String] = []

    func flushProse() {
      guard !proseLines.isEmpty else { return }
      let joined = proseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      proseLines.removeAll()
      guard !joined.isEmpty else { return }
      blocks.append(.text(renderProse(joined, isUser: isUser)))
    }

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if inCode {
          let codeText = codeLines.joined(separator: "\n")
          blocks.append(.code(language: codeLang, code: codeText))
          codeLines.removeAll()
          codeLang = ""
          inCode = false
        } else {
          flushProse()
          inCode = true
          codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
      } else if inCode {
        codeLines.append(line)
      } else {
        proseLines.append(line)
      }
    }
    if inCode && !codeLines.isEmpty {
      blocks.append(.code(language: codeLang, code: codeLines.joined(separator: "\n")))
    }
    flushProse()
    return blocks
  }

  private static func renderProse(_ text: String, isUser: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let lines = text.components(separatedBy: "\n")
    let baseColor = SnippetTheme.fg1

    for (idx, rawLine) in lines.enumerated() {
      if idx > 0 {
        result.append(NSAttributedString(string: "\n"))
      }
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        continue
      }

      var lineText = trimmed
      var fontSize: CGFloat = 13.5
      var baseWeight: NSFont.Weight = .regular
      var lineColor = baseColor
      var headIndent: CGFloat = 0
      var firstIndent: CGFloat = 0
      var spacingBefore: CGFloat = 0

      if lineText.hasPrefix("### ") {
        lineText = String(lineText.dropFirst(4))
        fontSize = 13.5
        baseWeight = .medium
        lineColor = SnippetTheme.fg1
        spacingBefore = idx > 0 ? 4 : 0
      } else if lineText.hasPrefix("## ") {
        lineText = String(lineText.dropFirst(3))
        fontSize = 14.5
        baseWeight = .medium
        lineColor = SnippetTheme.fg1
        spacingBefore = idx > 0 ? 5 : 0
      } else if lineText.hasPrefix("# ") {
        lineText = String(lineText.dropFirst(2))
        fontSize = 15.0
        baseWeight = .medium
        lineColor = SnippetTheme.fg1
        spacingBefore = idx > 0 ? 6 : 0
      } else if lineText.hasPrefix("- ") || lineText.hasPrefix("* ") || lineText.hasPrefix("+ ") {
        lineText = "•  " + String(lineText.dropFirst(2))
        headIndent = 14
        firstIndent = 2
      } else if lineText.hasPrefix("> ") {
        lineText = "▎ " + String(lineText.dropFirst(2))
        lineColor = SnippetTheme.fg3
        headIndent = 10
      } else if let dotRange = lineText.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
        let prefix = String(lineText[dotRange])
        let rest = String(lineText[dotRange.upperBound...])
        lineText = prefix + rest
        headIndent = 16
        firstIndent = 0
      }

      let pStyle = NSMutableParagraphStyle()
      pStyle.lineSpacing = 3.5
      pStyle.paragraphSpacing = 2.0
      pStyle.paragraphSpacingBefore = spacingBefore
      pStyle.headIndent = headIndent
      pStyle.firstLineHeadIndent = firstIndent

      let inlineAttr = renderInline(
        lineText,
        fontSize: fontSize,
        baseWeight: baseWeight,
        baseColor: lineColor,
        paragraphStyle: pStyle
      )
      result.append(inlineAttr)
    }
    return result
  }

  private static func renderInline(
    _ input: String,
    fontSize: CGFloat,
    baseWeight: NSFont.Weight,
    baseColor: NSColor,
    paragraphStyle: NSParagraphStyle
  ) -> NSAttributedString {
    var working = input
    if let linkRe = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)") {
      working = linkRe.stringByReplacingMatches(
        in: working,
        range: NSRange(working.startIndex..., in: working),
        withTemplate: "$1"
      )
    }

    let out = NSMutableAttributedString()
    let baseFont = SnippetTheme.sans(fontSize, weight: baseWeight)
    let boldFont = SnippetTheme.sans(fontSize, weight: .medium)
    let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    let codeFont = SnippetTheme.mono(max(12.0, fontSize - 1.0), weight: .regular)

    let defaultAttrs: [NSAttributedString.Key: Any] = [
      .font: baseFont,
      .foregroundColor: baseColor,
      .paragraphStyle: paragraphStyle,
    ]

    let pattern = "(`[^`]+`|\\*\\*[^*]+\\*\\*|__[^_]+__|\\*[^*]+\\*)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return NSAttributedString(string: working, attributes: defaultAttrs)
    }

    let ns = working as NSString
    let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
    var cursor = 0

    for m in matches {
      if m.range.location > cursor {
        let plain = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
        out.append(NSAttributedString(string: plain, attributes: defaultAttrs))
      }
      let token = ns.substring(with: m.range)
      if token.hasPrefix("`") && token.hasSuffix("`") && token.count >= 2 {
        let inner = String(token.dropFirst().dropLast())
        let codeAttrs: [NSAttributedString.Key: Any] = [
          .font: codeFont,
          .foregroundColor: SnippetTheme.fg1,
          .backgroundColor: SnippetTheme.surface2,
          .paragraphStyle: paragraphStyle,
        ]
        out.append(NSAttributedString(string: " \(inner) ", attributes: codeAttrs))
      } else if (token.hasPrefix("**") && token.hasSuffix("**")) || (token.hasPrefix("__") && token.hasSuffix("__")) {
        let inner = String(token.dropFirst(2).dropLast(2))
        let boldAttrs: [NSAttributedString.Key: Any] = [
          .font: boldFont,
          .foregroundColor: SnippetTheme.fg1,
          .paragraphStyle: paragraphStyle,
        ]
        out.append(NSAttributedString(string: inner, attributes: boldAttrs))
      } else if token.hasPrefix("*") && token.hasSuffix("*") && token.count >= 2 {
        let inner = String(token.dropFirst().dropLast())
        let itAttrs: [NSAttributedString.Key: Any] = [
          .font: italicFont,
          .foregroundColor: baseColor,
          .paragraphStyle: paragraphStyle,
        ]
        out.append(NSAttributedString(string: inner, attributes: itAttrs))
      } else {
        out.append(NSAttributedString(string: token, attributes: defaultAttrs))
      }
      cursor = m.range.location + m.range.length
    }

    if cursor < ns.length {
      let tail = ns.substring(from: cursor)
      out.append(NSAttributedString(string: tail, attributes: defaultAttrs))
    }
    return out
  }
}

// MARK: - DynamicNotchKit / boring.notch Style Notch HUD Controller

final class NotchHUDController {
  private let panel: NotchPanel
  private let hudView: NotchHUDView
  private let onActivateWindow: () -> Void
  private let onOpenInApp: (String) -> Void
  private let onOpenConversation: (String) -> Void
  private let onSendReply: (String) -> Void
  private let onCloseConversation: () -> Void

  private var windowHidden = false
  private var ambientActive = false
  private var userSpeaking = false
  private var assistantSpeaking = false
  private var speechProbability: Double = 0.0

  private var notifTitle: String?
  private var notifSubtitle: String?
  private var notifKind: String?
  private var notifPayload: String?
  private var notifDismissTimer: Timer?
  private var waveTimer: Timer?

  private var conversationExpanded = false
  private var activePayload: String = ""

  init(
    onActivateWindow: @escaping () -> Void,
    onOpenInApp: @escaping (String) -> Void,
    onOpenConversation: @escaping (String) -> Void,
    onSendReply: @escaping (String) -> Void,
    onCloseConversation: @escaping () -> Void
  ) {
    self.onActivateWindow = onActivateWindow
    self.onOpenInApp = onOpenInApp
    self.onOpenConversation = onOpenConversation
    self.onSendReply = onSendReply
    self.onCloseConversation = onCloseConversation

    let initialRect = NSRect(x: 0, y: 0, width: 300, height: 38)
    let p = NotchPanel(
      contentRect: initialRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    p.isFloatingPanel = true
    p.becomesKeyOnlyIfNeeded = true
    p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    p.isOpaque = false
    p.backgroundColor = .clear
    // Crucial: disable window-server rectangular shadow so top concave ears blend
    // seamlessly into the screen bezel with zero halo.
    p.hasShadow = false
    p.hidesOnDeactivate = false

    let v = NotchHUDView(frame: initialRect)
    p.contentView = v
    self.panel = p
    self.hudView = v

    v.onBannerTap = { [weak self] in
      self?.handleBannerTap()
    }
    v.onCloseBar = { [weak self] in
      self?.collapseConversation()
    }
    v.onOpenFullApp = { [weak self] in
      guard let self = self else { return }
      let payload = self.activePayload
      self.collapseConversation()
      self.onOpenInApp(payload)
    }
    v.onSubmitReply = { [weak self] text in
      self?.onSendReply(text)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onScreenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    notifDismissTimer?.invalidate()
    waveTimer?.invalidate()
  }

  @objc private func onScreenParametersChanged() {
    refreshHUD(animated: false)
  }

  func setWindowHidden(_ hidden: Bool) {
    windowHidden = hidden
    if !hidden {
      notifDismissTimer?.invalidate()
      notifTitle = nil
      notifSubtitle = nil
      notifKind = nil
      notifPayload = nil
      if conversationExpanded {
        collapseConversation()
        return
      }
    }
    refreshHUD(animated: true)
  }

  func updateAmbient(
    active: Bool,
    userSpeaking: Bool,
    assistantSpeaking: Bool,
    probability: Double
  ) {
    self.ambientActive = active
    self.userSpeaking = userSpeaking
    self.assistantSpeaking = assistantSpeaking
    self.speechProbability = probability
    refreshHUD(animated: true)
  }

  func presentNotification(
    title: String,
    subtitle: String,
    kind: String,
    payload: String
  ) {
    notifTitle = title
    notifSubtitle = subtitle
    notifKind = kind
    notifPayload = payload

    notifDismissTimer?.invalidate()
    if !conversationExpanded {
      notifDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
        self?.clearNotification()
      }
    }
    refreshHUD(animated: true)
  }

  func updateConversation(
    title: String,
    status: String,
    messages: [(role: String, text: String, meta: String)]
  ) {
    hudView.setConversationData(title: title, status: status, messages: messages)
  }

  func openMissionControlConversation() {
    let defaultPayload = "{\"session\":\"mission-control\",\"title\":\"Mission Control\"}"
    activePayload = defaultPayload
    notifDismissTimer?.invalidate()
    notifTitle = nil
    notifSubtitle = nil
    notifKind = nil
    notifPayload = nil
    conversationExpanded = true
    hudView.setConversationExpanded(true)
    hudView.setConversationData(
      title: "Mission Control",
      status: "loading",
      messages: []
    )
    refreshHUD(animated: true)
    onOpenConversation(defaultPayload)
  }

  private func clearNotification() {
    notifTitle = nil
    notifSubtitle = nil
    notifKind = nil
    notifPayload = nil
    refreshHUD(animated: true)
  }

  private func handleBannerTap() {
    if conversationExpanded {
      return
    }
    if let payload = notifPayload, !payload.isEmpty {
      let title = notifTitle ?? "Mission Control"
      let sub = notifSubtitle ?? ""
      activePayload = payload
      notifDismissTimer?.invalidate()
      notifTitle = nil
      notifSubtitle = nil
      notifKind = nil
      notifPayload = nil
      conversationExpanded = true
      hudView.setConversationExpanded(true)
      hudView.setConversationData(
        title: title,
        status: "loading",
        messages: sub.isEmpty ? [] : [(role: "assistant", text: sub, meta: "")]
      )
      refreshHUD(animated: true)
      onOpenConversation(payload)
    } else {
      openMissionControlConversation()
    }
  }

  private func collapseConversation() {
    guard conversationExpanded else { return }
    conversationExpanded = false
    activePayload = ""
    hudView.setConversationExpanded(false)
    onCloseConversation()
    refreshHUD(animated: true)
  }

  /// Reads the exact hardware cutout dimensions from NSScreen.
  private func measureHardwareNotch(on screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
    let screenFrame = screen.frame
    var width: CGFloat = 185
    var height: CGFloat = 32
    if #available(macOS 12.0, *) {
      let topInset = screen.safeAreaInsets.top
      if topInset > 0 {
        height = max(topInset, 32)
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
          let gap = screenFrame.width - left.width - right.width
          if gap > 80 && gap < 340 {
            width = gap
          }
        }
      } else {
        height = max(NSStatusBar.system.thickness, 28)
      }
    }
    return (width: width, height: height)
  }

  private func refreshHUD(animated: Bool) {
    let hasNotif = notifTitle != nil
    let showAmbient = windowHidden && (ambientActive || assistantSpeaking || userSpeaking)
    let shouldShow = windowHidden && (conversationExpanded || hasNotif || showAmbient)

    if !shouldShow {
      waveTimer?.invalidate()
      waveTimer = nil
      if panel.isVisible {
        panel.orderOut(nil)
      }
      return
    }

    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let screenFrame = screen.frame
    let hw = measureHardwareNotch(on: screen)

    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let targetWidth: CGFloat
    let targetHeight: CGFloat

    if conversationExpanded {
      topCornerRadius = 14
      bottomCornerRadius = 20
      targetWidth = max(hw.width + 292, 480) + topCornerRadius * 2
      targetHeight = hw.height + 380
    } else if hasNotif {
      topCornerRadius = 8
      bottomCornerRadius = 14
      targetWidth = max(hw.width + 116, 296) + topCornerRadius * 2
      targetHeight = hw.height + 26
    } else if assistantSpeaking || userSpeaking {
      topCornerRadius = 6
      bottomCornerRadius = 14
      targetWidth = hw.width + 92 + topCornerRadius * 2
      targetHeight = hw.height
    } else {
      topCornerRadius = 6
      bottomCornerRadius = 14
      targetWidth = hw.width + 84 + topCornerRadius * 2
      targetHeight = hw.height
    }

    let targetX = round(screenFrame.midX - targetWidth / 2)
    let targetY = round(screenFrame.maxY - targetHeight)
    let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)

    hudView.configure(
      notifTitle: notifTitle,
      notifSubtitle: notifSubtitle,
      notifKind: notifKind,
      ambientActive: ambientActive,
      userSpeaking: userSpeaking,
      assistantSpeaking: assistantSpeaking,
      probability: speechProbability,
      hwNotchWidth: hw.width,
      hwNotchHeight: hw.height,
      topCornerRadius: topCornerRadius,
      bottomCornerRadius: bottomCornerRadius
    )

    if !panel.isVisible {
      let closedW = hw.width + topCornerRadius * 2
      let startFrame = NSRect(
        x: round(screenFrame.midX - closedW / 2),
        y: round(screenFrame.maxY - hw.height),
        width: closedW,
        height: hw.height
      )
      panel.setFrame(startFrame, display: false)
      panel.orderFrontRegardless()
    }

    if animated {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = conversationExpanded ? 0.32 : 0.26
        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        panel.animator().setFrame(targetFrame, display: true)
      }
    } else {
      panel.setFrame(targetFrame, display: true)
    }

    let needsWaveTimer = !conversationExpanded && (ambientActive || assistantSpeaking || userSpeaking)
    if needsWaveTimer {
      if waveTimer == nil {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
          self?.hudView.stepAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        waveTimer = timer
      }
    } else {
      waveTimer?.invalidate()
      waveTimer = nil
    }
  }
}

// MARK: - Notch HUD View (DynamicNotchKit Shape + Camera-Aware Wing & Chin Layout)

final class NotchHUDView: NSView, NSTextFieldDelegate {
  var onBannerTap: (() -> Void)?
  var onCloseBar: (() -> Void)?
  var onOpenFullApp: (() -> Void)?
  var onSubmitReply: ((String) -> Void)?

  private var notifTitle: String?
  private var notifSubtitle: String?
  private var notifKind: String?
  private var ambientActive = false
  private var userSpeaking = false
  private var assistantSpeaking = false
  private var probability: Double = 0.0
  private var hwNotchWidth: CGFloat = 185.0
  private var hwNotchHeight: CGFloat = 32.0
  private var topCornerRadius: CGFloat = 6.0
  private var bottomCornerRadius: CGFloat = 14.0
  private var phase: CGFloat = 0.0

  private var conversationExpanded = false
  private var convTitle = "Conversation"
  private var convStatus = "idle"
  private var convMessages: [(role: String, text: String, meta: String)] = []

  private let containerView = NSView()
  private let titleField = NSTextField(labelWithString: "Conversation")
  private let statusField = NSTextField(labelWithString: "")
  private let openAppButton = NSButton(title: "Open ↗", target: nil, action: nil)
  private let closeButton = NSButton(title: "✕", target: nil, action: nil)
  private let scrollView = NSScrollView()
  private let documentView = FlippedDocumentView()
  private let replyContainer = NSView()
  private let replyField = NSTextField()
  private let sendButton = NSButton(title: "↑", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupConversationSubviews()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupConversationSubviews()
  }

  private func setupConversationSubviews() {
    containerView.isHidden = true
    addSubview(containerView)

    titleField.font = SnippetTheme.sans(13.5, weight: .medium)
    titleField.textColor = SnippetTheme.fg1
    titleField.lineBreakMode = .byTruncatingTail
    containerView.addSubview(titleField)

    statusField.font = SnippetTheme.mono(10.0, weight: .medium)
    statusField.textColor = SnippetTheme.accent
    containerView.addSubview(statusField)

    openAppButton.isBordered = false
    openAppButton.wantsLayer = true
    openAppButton.layer?.backgroundColor = SnippetTheme.surface1.cgColor
    openAppButton.layer?.cornerRadius = 8
    openAppButton.layer?.borderWidth = 1
    openAppButton.layer?.borderColor = SnippetTheme.border.cgColor
    openAppButton.font = SnippetTheme.sans(11.5, weight: .medium)
    openAppButton.contentTintColor = SnippetTheme.fg2
    openAppButton.target = self
    openAppButton.action = #selector(handleOpenAppTap)
    containerView.addSubview(openAppButton)

    closeButton.isBordered = false
    closeButton.wantsLayer = true
    closeButton.layer?.backgroundColor = SnippetTheme.surface1.cgColor
    closeButton.layer?.cornerRadius = 8
    closeButton.layer?.borderWidth = 1
    closeButton.layer?.borderColor = SnippetTheme.border.cgColor
    closeButton.font = SnippetTheme.sans(11.5, weight: .medium)
    closeButton.contentTintColor = SnippetTheme.fg3
    closeButton.target = self
    closeButton.action = #selector(handleCloseTap)
    containerView.addSubview(closeButton)

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.documentView = documentView
    containerView.addSubview(scrollView)

    replyContainer.wantsLayer = true
    replyContainer.layer?.backgroundColor = SnippetTheme.surface1.cgColor
    replyContainer.layer?.cornerRadius = 14
    replyContainer.layer?.borderWidth = 1
    replyContainer.layer?.borderColor = SnippetTheme.border.cgColor
    containerView.addSubview(replyContainer)

    replyField.isBordered = false
    replyField.drawsBackground = false
    replyField.focusRingType = .none
    replyField.font = SnippetTheme.sans(13.0, weight: .regular)
    replyField.textColor = SnippetTheme.fg1
    replyField.placeholderString = "Message Mission Control…"
    replyField.delegate = self
    replyField.target = self
    replyField.action = #selector(handleSendTap)
    replyContainer.addSubview(replyField)

    sendButton.isBordered = false
    sendButton.wantsLayer = true
    sendButton.layer?.backgroundColor = SnippetTheme.accentFill.cgColor
    sendButton.layer?.cornerRadius = 13
    sendButton.font = SnippetTheme.sans(13.0, weight: .medium)
    sendButton.contentTintColor = NSColor.white
    sendButton.target = self
    sendButton.action = #selector(handleSendTap)
    replyContainer.addSubview(sendButton)
  }

  @objc private func handleOpenAppTap() {
    onOpenFullApp?()
  }

  @objc private func handleCloseTap() {
    onCloseBar?()
  }

  @objc private func handleSendTap() {
    let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    replyField.stringValue = ""
    convMessages.append((role: "user", text: text, meta: ""))
    rebuildMessageViews(scrollToBottom: true)
    onSubmitReply?(text)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      handleSendTap()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      onCloseBar?()
      return true
    }
    return false
  }

  func setConversationExpanded(_ expanded: Bool) {
    conversationExpanded = expanded
    containerView.isHidden = !expanded
    needsLayout = true
    needsDisplay = true
    if expanded {
      window?.makeFirstResponder(replyField)
    }
  }

  func setConversationData(
    title: String,
    status: String,
    messages: [(role: String, text: String, meta: String)]
  ) {
    convTitle = title
    convStatus = status
    convMessages = messages
    titleField.stringValue = title
    statusField.stringValue = status == "running" ? "WORKING" : (status == "loading" ? "LOADING" : "")
    rebuildMessageViews(scrollToBottom: true)
    needsLayout = true
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    guard conversationExpanded else { return }
    let b = bounds
    let innerX = topCornerRadius + 16
    let innerW = max(120, b.width - (topCornerRadius + 16) * 2)
    let topClearance = hwNotchHeight + 6
    let contentRect = NSRect(
      x: innerX,
      y: 16,
      width: innerW,
      height: max(80, b.height - topClearance - 16)
    )
    containerView.frame = contentRect

    let headerH: CGFloat = 28
    let headerY = contentRect.height - headerH
    closeButton.frame = NSRect(x: contentRect.width - 26, y: headerY + 2, width: 26, height: 24)
    openAppButton.frame = NSRect(x: contentRect.width - 26 - 6 - 72, y: headerY + 2, width: 72, height: 24)

    let statusW: CGFloat = statusField.stringValue.isEmpty ? 0 : 62
    if statusW > 0 {
      statusField.frame = NSRect(
        x: openAppButton.frame.minX - statusW - 8,
        y: headerY + 6,
        width: statusW,
        height: 15
      )
    } else {
      statusField.frame = .zero
    }

    let titleMaxX = (statusW > 0 ? statusField.frame.minX : openAppButton.frame.minX) - 8
    titleField.frame = NSRect(x: 24, y: headerY + 4, width: max(60, titleMaxX - 24), height: 20)

    let replyH: CGFloat = 36
    replyContainer.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: replyH)
    sendButton.frame = NSRect(x: contentRect.width - 31, y: 5, width: 26, height: 26)
    replyField.frame = NSRect(x: 14, y: 7, width: max(60, contentRect.width - 52), height: 22)

    let scrollY = replyH + 10
    let scrollH = max(40, headerY - 10 - scrollY)
    scrollView.frame = NSRect(x: 0, y: scrollY, width: contentRect.width, height: scrollH)
    rebuildMessageViews(scrollToBottom: false)
  }

  private func rebuildMessageViews(scrollToBottom: Bool) {
    guard conversationExpanded else { return }
    for sub in documentView.subviews {
      sub.removeFromSuperview()
    }
    let width = max(200, scrollView.contentSize.width)
    var y: CGFloat = 8

    if convMessages.isEmpty {
      let empty = NSTextField(labelWithString: convStatus == "loading" ? "Loading Mission Control…" : "No messages yet.")
      empty.font = SnippetTheme.sans(12.5, weight: .regular)
      empty.textColor = SnippetTheme.fg3
      empty.frame = NSRect(x: 8, y: 18, width: width - 16, height: 20)
      documentView.addSubview(empty)
      y = 48
    } else {
      for msg in convMessages {
        let isUser = msg.role == "user"
        let blocks = NotchMarkdown.parseBlocks(msg.text, isUser: isUser)
        if blocks.isEmpty { continue }

        if isUser {
          // Matches Bubble(mine: true) in lib/widgets.dart:
          // padding: EdgeInsets.fromLTRB(14, 9, 14, 10), color: AppColors.surface2 (#1E1E22), no border
          let maxBubbleW = floor(width * 0.82)
          let padX: CGFloat = 14
          let padTop: CGFloat = 9
          let padBot: CGFloat = 10
          let attr = blocks.compactMap { b -> NSAttributedString? in
            if case let .text(a) = b { return a }
            return nil
          }.first ?? NSAttributedString(string: msg.text)

          let textView = NotchMarkdown.makeTextView(attr, maxWidth: maxBubbleW - padX * 2)
          let textSize = textView.measuredSize
          let bubbleW = min(maxBubbleW, textSize.width + padX * 2)
          let bubbleH = textSize.height + padTop + padBot
          let bubbleX = width - bubbleW - 4

          let bubble = NSView(frame: NSRect(x: bubbleX, y: y, width: bubbleW, height: bubbleH))
          bubble.wantsLayer = true
          bubble.layer?.backgroundColor = SnippetTheme.surface2.cgColor
          bubble.layer?.cornerRadius = 14

          textView.frame = NSRect(x: padX, y: padTop, width: textSize.width, height: textSize.height)
          bubble.addSubview(textView)
          documentView.addSubview(bubble)

          y += bubbleH + 4
          if !msg.meta.isEmpty {
            let metaField = NSTextField(labelWithString: msg.meta)
            metaField.font = SnippetTheme.sans(11.5, weight: .regular)
            metaField.textColor = SnippetTheme.fg4
            metaField.alignment = .right
            metaField.frame = NSRect(x: 8, y: y, width: width - 12, height: 15)
            documentView.addSubview(metaField)
            y += 16
          }
          y += 8
        } else {
          // Matches Bubble(mine: false) in lib/widgets.dart:
          // Plain full-width Markdown aligned left in Geist 13.5pt (#EEEEF1), with NO left-side blue ribbon.
          let turnX: CGFloat = 4
          let turnW = width - turnX - 8
          if !msg.meta.isEmpty {
            let badgeField = NSTextField(labelWithString: msg.meta)
            badgeField.font = SnippetTheme.sans(11.5, weight: .medium)
            badgeField.textColor = SnippetTheme.fg3
            badgeField.frame = NSRect(x: turnX, y: y, width: turnW, height: 15)
            documentView.addSubview(badgeField)
            y += 17
          }

          for block in blocks {
            switch block {
            case .text(let attr):
              let textView = NotchMarkdown.makeTextView(attr, maxWidth: turnW)
              let sz = textView.measuredSize
              textView.frame = NSRect(x: turnX, y: y, width: sz.width, height: sz.height)
              documentView.addSubview(textView)
              y += sz.height + 6

            case .code(let lang, let code):
              let codeFont = SnippetTheme.mono(12.0, weight: .regular)
              let pStyle = NSMutableParagraphStyle()
              pStyle.lineSpacing = 3.0
              let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: codeFont,
                .foregroundColor: SnippetTheme.fg2,
                .paragraphStyle: pStyle,
              ]
              let codeAttr = NSAttributedString(string: code, attributes: codeAttrs)
              let codeTextW = turnW - 24
              let codeView = NotchMarkdown.makeTextView(codeAttr, maxWidth: codeTextW)
              let sz = codeView.measuredSize
              let headerH: CGFloat = lang.isEmpty ? 0 : 18
              let boxH = sz.height + 16 + headerH
              let box = NSView(frame: NSRect(x: turnX, y: y, width: turnW, height: boxH))
              box.wantsLayer = true
              box.layer?.backgroundColor = SnippetTheme.surface1.cgColor
              box.layer?.cornerRadius = 8
              box.layer?.borderWidth = 1
              box.layer?.borderColor = SnippetTheme.border.cgColor

              if !lang.isEmpty {
                let langLabel = NSTextField(labelWithString: lang)
                langLabel.font = SnippetTheme.mono(10.5, weight: .medium)
                langLabel.textColor = SnippetTheme.fg3
                langLabel.frame = NSRect(x: 12, y: 5, width: codeTextW, height: 14)
                box.addSubview(langLabel)
              }

              codeView.frame = NSRect(x: 12, y: 8 + headerH, width: sz.width, height: sz.height)
              box.addSubview(codeView)
              documentView.addSubview(box)
              y += boxH + 8
            }
          }
          y += 8
        }
      }
    }

    let docH = max(scrollView.contentSize.height, y + 6)
    documentView.frame = NSRect(x: 0, y: 0, width: width, height: docH)
    if scrollToBottom {
      let bottomPoint = NSPoint(x: 0, y: max(0, docH - scrollView.contentSize.height))
      documentView.scroll(bottomPoint)
    }
  }

  func configure(
    notifTitle: String?,
    notifSubtitle: String?,
    notifKind: String?,
    ambientActive: Bool,
    userSpeaking: Bool,
    assistantSpeaking: Bool,
    probability: Double,
    hwNotchWidth: CGFloat,
    hwNotchHeight: CGFloat,
    topCornerRadius: CGFloat,
    bottomCornerRadius: CGFloat
  ) {
    self.notifTitle = notifTitle
    self.notifSubtitle = notifSubtitle
    self.notifKind = notifKind
    self.ambientActive = ambientActive
    self.userSpeaking = userSpeaking
    self.assistantSpeaking = assistantSpeaking
    self.probability = probability
    self.hwNotchWidth = hwNotchWidth
    self.hwNotchHeight = hwNotchHeight
    self.topCornerRadius = topCornerRadius
    self.bottomCornerRadius = bottomCornerRadius
    needsLayout = true
    needsDisplay = true
  }

  func stepAnimation() {
    phase += 0.08
    guard !conversationExpanded && (ambientActive || assistantSpeaking || userSpeaking) else {
      return
    }
    // Invalidate only the right-wing waveform rect instead of repainting the entire Notch
    let b = bounds
    let cameraRight = b.midX + hwNotchWidth / 2
    let waveRect = NSRect(
      x: cameraRight,
      y: b.maxY - hwNotchHeight,
      width: max(24, b.maxX - cameraRight),
      height: hwNotchHeight
    )
    setNeedsDisplay(waveRect)
  }

  override func mouseDown(with event: NSEvent) {
    if !conversationExpanded {
      onBannerTap?()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let b = bounds
    guard b.width > 20 && b.height > 16 else { return }

    let shapePath = Self.dynamicNotchPath(
      in: b,
      topCornerRadius: topCornerRadius,
      bottomCornerRadius: bottomCornerRadius
    )

    let periwinkle = NSColor(srgbRed: 0.73, green: 0.78, blue: 1.0, alpha: 1.0)
    let matcha = NSColor(srgbRed: 0.50, green: 0.82, blue: 0.65, alpha: 1.0)
    let ink = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0)
    let blush = NSColor(srgbRed: 0.95, green: 0.65, blue: 0.63, alpha: 0.85)
    let now = CACurrentMediaTime()

    NSGraphicsContext.current?.saveGraphicsState()
    shapePath.addClip()

    if conversationExpanded {
      // Match Snippet's exact #101012 (AppColors.bg) for the expanded panel while
      // keeping the top hardware camera band pitch-black so the bezel seam is invisible.
      SnippetTheme.bg.setFill()
      b.fill()
      NSColor.black.setFill()
      NSRect(x: b.minX, y: b.maxY - hwNotchHeight, width: b.width, height: hwNotchHeight).fill()
    } else {
      NSColor.black.setFill()
      b.fill()
    }

    let borderStroke = Self.dynamicNotchBorderPath(
      in: b,
      topCornerRadius: topCornerRadius,
      bottomCornerRadius: bottomCornerRadius
    )
    (conversationExpanded ? SnippetTheme.border : SnippetTheme.border2).setStroke()
    borderStroke.lineWidth = 1.5
    borderStroke.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Always render the Mochi + 5-bar listening/speaking indicator in the top notch wings
    drawAmbientWings(
      in: b,
      periwinkle: periwinkle,
      matcha: matcha,
      ink: ink,
      blush: blush,
      now: now
    )

    if conversationExpanded {
      let headerMochiRect = NSRect(
        x: topCornerRadius + 16,
        y: b.height - hwNotchHeight - 6 - 24,
        width: 18,
        height: 18
      )
      MochiRenderer.drawMochi(
        in: headerMochiRect,
        bodyColor: periwinkle,
        leafColor: matcha,
        eyeColor: ink,
        blushColor: blush
      )

      let sepY = b.height - hwNotchHeight - 6 - 32
      let sep = NSBezierPath()
      sep.move(to: NSPoint(x: topCornerRadius + 16, y: sepY))
      sep.line(to: NSPoint(x: b.width - topCornerRadius - 16, y: sepY))
      SnippetTheme.border.setStroke()
      sep.lineWidth = 1.0
      sep.stroke()
      return
    }

    if let title = notifTitle {
      drawNotification(
        in: b,
        title: title,
        subtitle: notifSubtitle ?? "",
        periwinkle: periwinkle,
        matcha: matcha,
        ink: ink,
        blush: blush
      )
    }
  }

  /// Renders the left wing (Mochi mascot + notification title when active) and
  /// right wing (5-bar audio listening/speaking equalizer) inside the top `hwNotchHeight` band.
  private func drawAmbientWings(
    in b: NSRect,
    periwinkle: NSColor,
    matcha: NSColor,
    ink: NSColor,
    blush: NSColor,
    now: Double
  ) {
    let topBandMinY = b.maxY - hwNotchHeight
    let topBandMidY = topBandMinY + hwNotchHeight / 2
    let cameraLeft = b.midX - hwNotchWidth / 2
    let cameraRight = b.midX + hwNotchWidth / 2

    let leftWingX = b.minX + topCornerRadius
    let leftWingW = max(24, cameraLeft - leftWingX)
    let mochiSize: CGFloat = 18

    if let title = notifTitle, !conversationExpanded {
      let mochiRect = NSRect(
        x: leftWingX + 10,
        y: topBandMidY - mochiSize / 2,
        width: mochiSize,
        height: mochiSize
      )
      MochiRenderer.drawMochi(
        in: mochiRect,
        bodyColor: userSpeaking ? matcha : periwinkle,
        leafColor: matcha,
        eyeColor: ink,
        blushColor: blush
      )
      let titleX = mochiRect.maxX + 6
      let titleW = max(20, cameraLeft - titleX - 6)
      let pStyle = NSMutableParagraphStyle()
      pStyle.lineBreakMode = .byTruncatingTail
      let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: SnippetTheme.sans(11.5, weight: .medium),
        .foregroundColor: SnippetTheme.fg1,
        .paragraphStyle: pStyle,
      ]
      (title as NSString).draw(
        in: NSRect(x: titleX, y: topBandMidY - 7.5, width: titleW, height: 15),
        withAttributes: titleAttrs
      )
    } else {
      let mochiRect = NSRect(
        x: leftWingX + (leftWingW - mochiSize) / 2,
        y: topBandMidY - mochiSize / 2,
        width: mochiSize,
        height: mochiSize
      )
      MochiRenderer.drawMochi(
        in: mochiRect,
        bodyColor: userSpeaking ? matcha : periwinkle,
        leafColor: matcha,
        eyeColor: ink,
        blushColor: blush
      )
    }

    // Right Wing: 5-bar listening/speaking equalizer ONLY when listening/speaking is actually active
    if ambientActive || assistantSpeaking || userSpeaking {
      let rightWingX = cameraRight
      let rightWingW = max(24, (b.maxX - topCornerRadius) - rightWingX)
      let barCount = 5
      let barW: CGFloat = 2.5
      let barGap: CGFloat = 2.6
      let totalBarsW = CGFloat(barCount) * barW + CGFloat(barCount - 1) * barGap
      let startX = notifTitle != nil && !conversationExpanded
        ? (b.maxX - topCornerRadius - 12 - totalBarsW)
        : (rightWingX + (rightWingW - totalBarsW) / 2)

      let waveColor = userSpeaking ? SnippetTheme.ok : SnippetTheme.accent
      for i in 0..<barCount {
        let wave = sin(Double(phase) + Double(i) * 0.9)
        let amp: CGFloat = assistantSpeaking
          ? 1.0
          : (userSpeaking ? max(CGFloat(probability), 0.6) : 0.22)
        let barH = max(3.5, 3.5 + 11.5 * amp * CGFloat(0.5 + 0.5 * wave))
        let bx = startX + CGFloat(i) * (barW + barGap)
        let by = topBandMidY - barH / 2
        let barRect = NSRect(x: bx, y: by, width: barW, height: barH)
        waveColor.withAlphaComponent(assistantSpeaking || userSpeaking ? 0.95 : 0.70).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 1.25, yRadius: 1.25).fill()
      }
    }
  }

  /// Uses the top notch wing space for the Mochi + notification title and the right wing
  /// for the 5-bar listening indicator, while rendering the message preview + Reply pill
  /// in a tight 1-line row directly below.
  private func drawNotification(
    in b: NSRect,
    title: String,
    subtitle: String,
    periwinkle: NSColor,
    matcha: NSColor,
    ink: NSColor,
    blush: NSColor
  ) {
    let topBandMinY = b.maxY - hwNotchHeight
    let rowRect = NSRect(
      x: b.minX + topCornerRadius + 10,
      y: 4,
      width: b.width - (topCornerRadius + 10) * 2,
      height: max(18, topBandMinY - 4)
    )

    let pillW: CGFloat = 40
    let pillH: CGFloat = 17
    let pillRect = NSRect(
      x: rowRect.maxX - pillW,
      y: rowRect.midY - pillH / 2,
      width: pillW,
      height: pillH
    )
    SnippetTheme.accentFill.setFill()
    NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5).fill()

    let pillStyle = NSMutableParagraphStyle()
    pillStyle.alignment = .center
    let pillAttrs: [NSAttributedString.Key: Any] = [
      .font: SnippetTheme.sans(10.0, weight: .medium),
      .foregroundColor: NSColor.white,
      .paragraphStyle: pillStyle,
    ]
    ("Reply" as NSString).draw(
      in: NSRect(x: pillRect.minX, y: pillRect.minY + 1.5, width: pillW, height: 14),
      withAttributes: pillAttrs
    )

    let cleanSub = NotchMarkdown.plainPreview(subtitle)
    let previewText = cleanSub.isEmpty ? title : cleanSub
    let textW = max(36, pillRect.minX - rowRect.minX - 8)
    let pStyle = NSMutableParagraphStyle()
    pStyle.lineBreakMode = .byTruncatingTail
    let subAttrs: [NSAttributedString.Key: Any] = [
      .font: SnippetTheme.sans(11.0, weight: .regular),
      .foregroundColor: SnippetTheme.fg2,
      .paragraphStyle: pStyle,
    ]
    (previewText as NSString).draw(
      in: NSRect(x: rowRect.minX, y: rowRect.midY - 7, width: textW, height: 14),
      withAttributes: subAttrs
    )
  }

  /// Exact `DynamicNotchKit` / `boring.notch` silhouette in AppKit coordinates
  /// (`maxY` = top bezel, `minY` = bottom of notch), with concave quadratic Bezier
  /// top ears (`topCornerRadius`) and smooth quadratic bottom corners (`bottomCornerRadius`).
  private static func dynamicNotchPath(
    in rect: NSRect,
    topCornerRadius topR: CGFloat,
    bottomCornerRadius botR: CGFloat
  ) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.addQuadCurve(
      to: NSPoint(x: rect.minX + topR, y: rect.maxY - topR),
      control: NSPoint(x: rect.minX + topR, y: rect.maxY)
    )
    path.line(to: NSPoint(x: rect.minX + topR, y: rect.minY + botR))
    path.addQuadCurve(
      to: NSPoint(x: rect.minX + topR + botR, y: rect.minY),
      control: NSPoint(x: rect.minX + topR, y: rect.minY)
    )
    path.line(to: NSPoint(x: rect.maxX - topR - botR, y: rect.minY))
    path.addQuadCurve(
      to: NSPoint(x: rect.maxX - topR, y: rect.minY + botR),
      control: NSPoint(x: rect.maxX - topR, y: rect.minY)
    )
    path.line(to: NSPoint(x: rect.maxX - topR, y: rect.maxY - topR))
    path.addQuadCurve(
      to: NSPoint(x: rect.maxX, y: rect.maxY),
      control: NSPoint(x: rect.maxX - topR, y: rect.maxY)
    )
    path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.close()
    return path
  }

  /// Open border path covering only the side walls and bottom curve (never the top bezel).
  private static func dynamicNotchBorderPath(
    in rect: NSRect,
    topCornerRadius topR: CGFloat,
    bottomCornerRadius botR: CGFloat
  ) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.addQuadCurve(
      to: NSPoint(x: rect.minX + topR, y: rect.maxY - topR),
      control: NSPoint(x: rect.minX + topR, y: rect.maxY)
    )
    path.line(to: NSPoint(x: rect.minX + topR, y: rect.minY + botR))
    path.addQuadCurve(
      to: NSPoint(x: rect.minX + topR + botR, y: rect.minY),
      control: NSPoint(x: rect.minX + topR, y: rect.minY)
    )
    path.line(to: NSPoint(x: rect.maxX - topR - botR, y: rect.minY))
    path.addQuadCurve(
      to: NSPoint(x: rect.maxX - topR, y: rect.minY + botR),
      control: NSPoint(x: rect.maxX - topR, y: rect.minY)
    )
    path.line(to: NSPoint(x: rect.maxX - topR, y: rect.maxY - topR))
    path.addQuadCurve(
      to: NSPoint(x: rect.maxX, y: rect.maxY),
      control: NSPoint(x: rect.maxX - topR, y: rect.maxY)
    )
    return path
  }
}
