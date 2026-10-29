import AVFoundation
import Carbon.HIToolbox
import Cocoa

import CoreText
import FlutterMacOS
import QuartzCore

struct NotchItem {
  var role = "assistant"
  var text = ""
  var meta = ""
  var type = "message"
  var live = false
  var state = ""
  var title = ""
  var url = ""
  var path = ""
  var id = ""
  var choices: [String] = []
  var answerKind = ""

  init(_ raw: [String: Any]) {
    role = raw["role"] as? String ?? role
    text = raw["text"] as? String ?? text
    meta = raw["meta"] as? String ?? meta
    type = raw["type"] as? String ?? type
    live = raw["live"] as? Bool ?? live
    state = raw["state"] as? String ?? state
    title = raw["title"] as? String ?? title
    url = raw["url"] as? String ?? url
    path = raw["path"] as? String ?? path
    id = raw["id"] as? String ?? id
    choices = (raw["choices"] as? [Any])?.compactMap { $0 as? String } ?? choices
    answerKind = raw["answerKind"] as? String ?? answerKind
  }
}

private func snippetHotKeyCallback(
  nextHandler: EventHandlerCallRef?,
  theEvent: EventRef?,
  userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData = userData else { return noErr }
  let window = Unmanaged<MainFlutterWindow>.fromOpaque(userData).takeUnretainedValue()
  DispatchQueue.main.async {
    window.triggerGlobalAmbientToggle()
  }
  return noErr
}

// MARK: - Snippet Theme & Bundled Font Loader (JetBrainsMono + Graphite Palette)

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

  static func symbol(_ name: String, _ label: String, size: CGFloat, weight: NSFont.Weight = .medium) -> NSImage? {
    guard #available(macOS 11.0, *) else { return nil }
    return NSImage(systemSymbolName: name, accessibilityDescription: label)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
  }

  static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
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
  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
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
    hud.onNotchAction = { [weak self] action, text in
      self?.notchChannel?.invokeMethod("notchAction", arguments: ["action": action, "text": text])
    }
    hud.onCallAction = { [weak self] action in
      self?.notchChannel?.invokeMethod("callAction", arguments: ["action": action])
    }
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
      case "callPrompt":
        if let args = call.arguments as? [String: Any] {
          let expiresAtMs = (args["expiresAtMs"] as? NSNumber)?.doubleValue ?? 0
          let seconds = expiresAtMs > 0 ? expiresAtMs / 1000 - Date().timeIntervalSince1970 : 120
          self.notchHUD?.presentCallPrompt(
            callId: args["callId"] as? String ?? "",
            title: args["title"] as? String ?? "Call",
            message: args["message"] as? String ?? "Track this call?",
            seconds: seconds)
        }
        result(nil)
      case "callTracking":
        self.notchHUD?.presentCallTracking(callId: (call.arguments as? [String: Any])?["callId"] as? String ?? "")
        result(nil)
      case "callClear":
        self.notchHUD?.clearCall()
        result(nil)
      case "openInApp":
        if let args = call.arguments as? [String: Any], let payloadData = try? JSONSerialization.data(withJSONObject: args), let payload = String(data: payloadData, encoding: .utf8) {
          self.notchHUD?.openPayloadInApp(payload)
        }
        result(nil)
      case "updateConversation":
        if let args = call.arguments as? [String: Any] {
          let title = args["title"] as? String ?? "Conversation"
          let status = args["status"] as? String ?? "idle"
          let rawMsgs = args["messages"] as? [[String: Any]] ?? []
          let messages = rawMsgs.compactMap { m -> NotchItem? in
            let item = NotchItem(m)
            guard !item.text.isEmpty else { return nil }
            return item
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
    registerGlobalAmbientHotKey()

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
    if let hk = hotKeyRef {
      UnregisterEventHotKey(hk)
    }
    if let hh = hotKeyHandlerRef {
      RemoveEventHandler(hh)
    }
    backdropTimer?.invalidate()
    menuMochiTimer?.invalidate()
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  /// Registers Option + Shift + Space (`⌥⇧Space`) as a system-wide global hotkey
  /// that toggles Ambient Voice on/off even when Snippet is minimized or in the background.
  private func registerGlobalAmbientHotKey() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      snippetHotKeyCallback,
      1,
      &eventType,
      selfPtr,
      &hotKeyHandlerRef
    )
    let hotKeyID = EventHotKeyID(signature: OSType(0x534E5054), id: 1) // 'SNPT'
    let modifiers = UInt32(optionKey | shiftKey)
    RegisterEventHotKey(
      UInt32(kVK_Space),
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  func triggerGlobalAmbientToggle() {
    notchChannel?.invokeMethod("toggleAmbient", arguments: nil)
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
    NSApp.setActivationPolicy(.accessory)
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
    NSApp.setActivationPolicy(.regular)
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

    let ambientItem = NSMenuItem(
      title: "Ambient Voice: Off (⌥⇧Space)",
      action: #selector(onMenuToggleAmbient),
      keyEquivalent: " "
    )
    ambientItem.keyEquivalentModifierMask = [.option, .shift]
    ambientItem.target = self
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

  @objc private func onMenuToggleAmbient() {
    triggerGlobalAmbientToggle()
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
      ambientMenuItem?.title = "Ambient Voice: Off (⌥⇧Space)"
    } else if assistantSpeaking {
      ambientMenuItem?.title = "Ambient Voice: Speaking (⌥⇧Space)"
    } else if userSpeaking {
      ambientMenuItem?.title = "Ambient Voice: Hearing you (⌥⇧Space)"
    } else {
      ambientMenuItem?.title = "Ambient Voice: Listening (⌥⇧Space)"
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
  private var ttsPaused = false

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
      case "pauseTts":
        self.ttsPaused = true
        self.playerNode.pause()
        result(nil)
      case "resumeTts":
        if self.ttsPaused {
          self.ttsPaused = false
          self.playerNode.play()
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
    if playerNode.isPlaying || ttsPaused {
      playerNode.stop()
    }
    ttsPaused = false
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
    if !playerNode.isPlaying && !ttsPaused {
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
    if playerNode.isPlaying || ttsPaused {
      playerNode.stop()
    }
    ttsPaused = false
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
    addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openLink(_:))))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func openLink(_ recognizer: NSClickGestureRecognizer) {
    let point = recognizer.location(in: self)
    let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
    let character = layoutManager.characterIndexForGlyph(at: glyph)
    if character < storage.length, let url = storage.attribute(.link, at: character, effectiveRange: nil) as? URL {
      NSWorkspace.shared.open(url)
    }
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

    var lineIndex = 0
    while lineIndex < lines.count {
      let line = lines[lineIndex]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !inCode, trimmed.contains("|"), lineIndex + 1 < lines.count, lines[lineIndex + 1].contains("---") {
        flushProse()
        var tableRows = [line]
        lineIndex += 2
        while lineIndex < lines.count, lines[lineIndex].contains("|") {
          tableRows.append(lines[lineIndex])
          lineIndex += 1
        }
        let text = tableRows.map { row in
          row.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "   │   ")
        }.joined(separator: "\n")
        let attrs: [NSAttributedString.Key: Any] = [.font: SnippetTheme.mono(11.5, weight: .regular), .foregroundColor: SnippetTheme.fg2]
        blocks.append(.text(NSAttributedString(string: text, attributes: attrs)))
        continue
      }
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
      lineIndex += 1
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
      } else if lineText.range(of: "^\\s+([-*+]\\s+|\\d+\\.\\s+)", options: .regularExpression) != nil {
        let leading = lineText.prefix(while: { $0 == " " }).count
        lineText = String(repeating: "  ", count: leading / 2) + "•  " + lineText.drop(while: { $0 == " " }).dropFirst(2)
        headIndent = CGFloat(14 + leading * 5)
        firstIndent = 2
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
    var linkPairs: [(String, String)] = []
    if let linkRe = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)") {
      let ns = working as NSString
      for match in linkRe.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed() {
        linkPairs.append((ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2))))
      }
      working = linkRe.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "$1")
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

    let pattern = "(`[^`]+`|\\*\\*[^*]+\\*\\*|~~[^~]+~~|__[^_]+__|_[^_]+_|\\*[^*]+\\*)"
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
      } else if token.hasPrefix("~~") && token.hasSuffix("~~") {
        let inner = String(token.dropFirst(2).dropLast(2))
        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: baseColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .paragraphStyle: paragraphStyle]
        out.append(NSAttributedString(string: inner, attributes: attrs))
      } else if (token.hasPrefix("_") && token.hasSuffix("_")) || (token.hasPrefix("*") && token.hasSuffix("*") && token.count >= 2) {
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
    for (label, target) in linkPairs {
      let range = (out.string as NSString).range(of: label)
      if range.location != NSNotFound, let url = URL(string: target) {
        out.addAttribute(.link, value: url, range: range)
        out.addAttribute(.foregroundColor, value: SnippetTheme.accent, range: range)
      }
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
  var onNotchAction: ((String, String) -> Void)?
  var onCallAction: ((String) -> Void)?
  private let onCloseConversation: () -> Void

  private var callMode: String?
  private var callTimer: Timer?
  private var callDuration: TimeInterval = 120

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
  private var notifStartedAt: TimeInterval = 0
  private let notifDuration: TimeInterval = 3.5
  private var hasUnreadNotification = false

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
    v.onNotchAction = { [weak self] action, text in
      self?.onNotchAction?(action, text)
    }
    v.onCallAction = { [weak self] action in
      self?.onCallAction?(action)
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
      hasUnreadNotification = false
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
    if assistantSpeaking && notifTitle != nil {
      notifDismissTimer?.invalidate()
      notifTitle = nil
      notifSubtitle = nil
      notifKind = nil
      notifPayload = nil
      hasUnreadNotification = false
    }
    refreshHUD(animated: true)
  }

  func presentNotification(
    title: String,
    subtitle: String,
    kind: String,
    payload: String
  ) {
    // Do not show a notification banner while Snippet is speaking aloud
    if assistantSpeaking || callMode == "prompt" {
      return
    }
    notifTitle = title
    notifSubtitle = subtitle
    notifKind = kind
    notifPayload = payload
    hasUnreadNotification = false
    notifStartedAt = CACurrentMediaTime()

    notifDismissTimer?.invalidate()
    if !conversationExpanded {
      notifDismissTimer = Timer.scheduledTimer(withTimeInterval: notifDuration, repeats: false) { [weak self] _ in
        self?.clearNotification()
      }
    }
    refreshHUD(animated: true)
  }

  func updateConversation(
    title: String,
    status: String,
    messages: [NotchItem]
  ) {
    hudView.setConversationData(title: title, status: status, messages: messages)
  }

  func openPayloadInApp(_ payload: String) {
    activePayload = payload
    onOpenInApp(payload)
  }

  func openMissionControlConversation() {
    let defaultPayload = "{\"session\":\"mission-control\",\"title\":\"Mission Control\"}"
    activePayload = defaultPayload
    notifDismissTimer?.invalidate()
    notifTitle = nil
    notifSubtitle = nil
    notifKind = nil
    notifPayload = nil
    hasUnreadNotification = false
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

  func presentCallPrompt(callId: String, title: String, message: String, seconds: TimeInterval) {
    guard seconds > 0 else { return }
    callTimer?.invalidate()
    notifDismissTimer?.invalidate()
    callMode = "prompt"
    callDuration = seconds
    notifTitle = title
    notifSubtitle = message
    notifKind = "call"
    notifPayload = ""
    hasUnreadNotification = false
    notifStartedAt = CACurrentMediaTime()
    callTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
      self?.clearCall()
    }
    refreshHUD(animated: true)
  }

  func presentCallTracking(callId: String) {
    callTimer?.invalidate()
    if callMode == "prompt" {
      notifTitle = nil
      notifSubtitle = nil
      notifKind = nil
      notifPayload = nil
    }
    callMode = "tracking"
    refreshHUD(animated: true)
  }

  func clearCall() {
    callTimer?.invalidate()
    if callMode == "prompt" {
      notifTitle = nil
      notifSubtitle = nil
      notifKind = nil
      notifPayload = nil
    }
    callMode = nil
    refreshHUD(animated: true)
  }

  private func clearNotification() {
    notifTitle = nil
    notifSubtitle = nil
    notifKind = nil
    notifPayload = nil
    hasUnreadNotification = true
    refreshHUD(animated: true)
  }

  private func handleBannerTap() {
    if conversationExpanded || callMode == "prompt" {
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
      hasUnreadNotification = false
      conversationExpanded = true
      hudView.setConversationExpanded(true)
      hudView.setConversationData(
        title: title,
        status: "loading",
        messages: sub.isEmpty ? [] : [NotchItem(["role": "assistant", "text": sub])]
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
    let shouldShow = windowHidden && (conversationExpanded || hasNotif || hasUnreadNotification || showAmbient || callMode != nil)

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
      topCornerRadius = 6
      bottomCornerRadius = 18
      targetWidth = hw.width + 120 + topCornerRadius * 2
      targetHeight = hw.height + (callMode == "prompt" ? 92 : 62)
    } else if callMode == "tracking" {
      topCornerRadius = 6
      bottomCornerRadius = 16
      targetWidth = hw.width + 120 + topCornerRadius * 2
      targetHeight = hw.height + 34
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
      bottomCornerRadius: bottomCornerRadius,
      hasUnreadNotification: hasUnreadNotification,
      notifStartedAt: notifStartedAt,
      notifDuration: callMode == "prompt" ? callDuration : notifDuration,
      callMode: callMode
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

    let needsWaveTimer = !conversationExpanded && (ambientActive || assistantSpeaking || userSpeaking || hasNotif)
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
  var onNotchAction: ((String, String) -> Void)?
  var onCallAction: ((String) -> Void)?

  private var callMode: String?
  private let trackButton = NSButton(title: "Track", target: nil, action: nil)
  private let ignoreButton = NSButton(title: "Ignore", target: nil, action: nil)
  private let stopButton = NSButton(title: "Stop", target: nil, action: nil)

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
  private var hasUnreadNotification = false
  private var notifStartedAt: TimeInterval = 0
  private var notifDuration: TimeInterval = 3.5

  private var conversationExpanded = false
  private var convTitle = "Conversation"
  private var convStatus = "idle"
  private var convMessages: [NotchItem] = []
  private var selectedChoices = Set<String>()

  private let containerView = NSView()
  private let titleField = NSTextField(labelWithString: "Conversation")
  private let statusField = NSTextField(labelWithString: "")
  private let openAppButton = NSButton(title: "Open ↗", target: nil, action: nil)
  private let closeButton = NSButton(title: "✕", target: nil, action: nil)
  private let scrollView = NSScrollView()
  private let documentView = FlippedDocumentView()
  private let replyContainer = NSView()
  private let cardContainer = NSView()
  private let replyField = NSTextField()
  private let sendButton = NSButton(title: "↑", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupConversationSubviews()
    setupCallButtons()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupConversationSubviews()
    setupCallButtons()
  }

  private func setupCallButtons() {
    styleCallButton(trackButton, action: #selector(handleTrackTap), filled: true)
    styleCallButton(ignoreButton, action: #selector(handleIgnoreTap), filled: false)
    styleCallButton(stopButton, action: #selector(handleStopTap), filled: false)
  }

  private func setupConversationSubviews() {
    containerView.isHidden = true
    addSubview(containerView)

    titleField.font = SnippetTheme.sans(13.5, weight: .medium)
    titleField.textColor = SnippetTheme.fg1
    titleField.lineBreakMode = .byTruncatingTail
    containerView.addSubview(titleField)

    statusField.font = SnippetTheme.mono(10.0, weight: .medium)
    statusField.textColor = SnippetTheme.fg3
    containerView.addSubview(statusField)

    openAppButton.isBordered = false
    openAppButton.wantsLayer = true
    openAppButton.layer?.cornerRadius = 8
    openAppButton.image = SnippetTheme.symbol("arrow.up.forward.square", "Open in app", size: 13, weight: .medium)
    openAppButton.title = openAppButton.image == nil ? "Open" : ""
    openAppButton.contentTintColor = NSColor(srgbRed: 0.604, green: 0.604, blue: 0.635, alpha: 1)
    openAppButton.target = self
    openAppButton.action = #selector(handleOpenAppTap)
    containerView.addSubview(openAppButton)

    closeButton.isBordered = false
    closeButton.wantsLayer = true
    closeButton.layer?.cornerRadius = 8
    closeButton.image = SnippetTheme.symbol("xmark", "Close conversation", size: 13, weight: .medium)
    closeButton.title = closeButton.image == nil ? "✕" : ""
    closeButton.contentTintColor = NSColor(srgbRed: 0.604, green: 0.604, blue: 0.635, alpha: 1)
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
    replyContainer.layer?.backgroundColor = NSColor(srgbRed: 0.086, green: 0.086, blue: 0.094, alpha: 1).cgColor
    replyContainer.layer?.cornerRadius = 18
    containerView.addSubview(replyContainer)
    cardContainer.wantsLayer = true
    cardContainer.layer?.backgroundColor = SnippetTheme.surface1.cgColor
    cardContainer.layer?.cornerRadius = 10
    containerView.addSubview(cardContainer)

    replyField.isBordered = false
    replyField.drawsBackground = false
    replyField.focusRingType = .none
    replyField.font = SnippetTheme.sans(13.0, weight: .regular)
    replyField.textColor = SnippetTheme.fg1
    replyField.placeholderString = "Reply to Mission Control"
    replyField.delegate = self
    replyField.target = self
    replyField.action = #selector(handleSendTap)
    replyContainer.addSubview(replyField)

    sendButton.isBordered = false
    sendButton.wantsLayer = true
    sendButton.image = SnippetTheme.symbol("arrow.up", "Send reply", size: 12, weight: .semibold)
    sendButton.title = sendButton.image == nil ? "↑" : ""
    sendButton.layer?.backgroundColor = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.188, alpha: 1).cgColor
    sendButton.layer?.cornerRadius = 14
    sendButton.contentTintColor = NSColor(srgbRed: 0.816, green: 0.816, blue: 0.839, alpha: 1)
    sendButton.target = self
    sendButton.action = #selector(handleSendTap)
    replyContainer.addSubview(sendButton)
  }

  private func styleCallButton(_ button: NSButton, action: Selector, filled: Bool) {
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.cornerRadius = 6
    button.layer?.backgroundColor = (filled ? SnippetTheme.accentFill : NSColor(srgbRed: 0.165, green: 0.165, blue: 0.188, alpha: 1)).cgColor
    button.attributedTitle = NSAttributedString(string: button.title, attributes: [
      .font: SnippetTheme.sans(11.5, weight: .medium),
      .foregroundColor: SnippetTheme.fg1,
    ])
    button.target = self
    button.action = action
    button.isHidden = true
    addSubview(button)
  }

  @objc private func handleTrackTap() { onCallAction?("track") }
  @objc private func handleIgnoreTap() { onCallAction?("ignore") }
  @objc private func handleStopTap() { onCallAction?("stop") }

  private func layoutCallButtons() {
    let b = bounds
    let showPrompt = callMode == "prompt" && notifTitle != nil && !conversationExpanded
    let showStop = callMode == "tracking" && notifTitle == nil && !conversationExpanded
    trackButton.isHidden = !showPrompt
    ignoreButton.isHidden = !showPrompt
    stopButton.isHidden = !showStop
    let left = b.minX + topCornerRadius + 16
    trackButton.frame = NSRect(x: left, y: b.minY + 10, width: 64, height: 24)
    ignoreButton.frame = NSRect(x: left + 72, y: b.minY + 10, width: 64, height: 24)
    stopButton.frame = NSRect(x: b.maxX - topCornerRadius - 16 - 56, y: b.minY + 6, width: 56, height: 22)
  }

  @objc private func handleOpenAppTap() {
    onOpenFullApp?()
  }

  @objc private func handleCloseTap() {
    onCloseBar?()
  }

  @objc private func handleArtifactTap(_ sender: NSButton) {
    onNotchAction?("openArtifact", sender.identifier?.rawValue ?? "")
  }

  @objc private func handleImageTap(_ recognizer: NSClickGestureRecognizer) {
    guard let view = recognizer.view as? NSImageView else { return }
    onNotchAction?("openImage", view.identifier?.rawValue ?? "")
  }

  @objc private func handleChoice(_ sender: NSButton) {
    let answer = sender.identifier?.rawValue ?? sender.title
    if convMessages.contains(where: { $0.type == "question" && $0.answerKind == "multi" }) {
      if selectedChoices.contains(answer) { selectedChoices.remove(answer) } else { selectedChoices.insert(answer) }
      sender.state = selectedChoices.contains(answer) ? .on : .off
    } else {
      onNotchAction?("answer", answer)
    }
  }

  @objc private func handleSendChoices() {
    onNotchAction?("answer", selectedChoices.sorted().joined(separator: ", "))
    selectedChoices.removeAll()
  }

  @objc private func handleNotchAction(_ sender: NSButton) {
    let action = sender.identifier?.rawValue ?? "reply"
    onNotchAction?(action, replyField.stringValue)
  }

  @objc private func handleSendTap() {
    let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    replyField.stringValue = ""
    let questionPending = convMessages.contains(where: { $0.type == "question" })
    convMessages.append(NotchItem(["role": "user", "text": text]))
    rebuildMessageViews(scrollToBottom: true)
    if questionPending { onNotchAction?("answer", text) } else { onSubmitReply?(text) }
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
    messages: [NotchItem]
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
    layoutCallButtons()
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
    closeButton.frame = NSRect(x: contentRect.width - 28, y: headerY, width: 28, height: 28)
    openAppButton.frame = NSRect(x: contentRect.width - 28 - 4 - 28, y: headerY, width: 28, height: 28)

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
    let hasPendingCard = convMessages.contains(where: { $0.type == "question" || $0.type == "approval" })
    let cardH: CGFloat = hasPendingCard ? 72 : 0
    cardContainer.isHidden = !hasPendingCard
    cardContainer.frame = NSRect(x: 0, y: replyH + 8, width: contentRect.width, height: cardH)
    replyContainer.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: replyH)
    sendButton.frame = NSRect(x: contentRect.width - 32, y: 4, width: 28, height: 28)
    replyField.frame = NSRect(x: 14, y: 7, width: max(60, contentRect.width - 54), height: 22)

    let scrollY = replyH + 10 + cardH + (hasPendingCard ? 8 : 0)
    let scrollH = max(40, headerY - 10 - scrollY)
    scrollView.frame = NSRect(x: 0, y: scrollY, width: contentRect.width, height: scrollH)
    rebuildMessageViews(scrollToBottom: false)
  }

  private func rebuildMessageViews(scrollToBottom: Bool) {
    guard conversationExpanded else { return }
    for sub in documentView.subviews {
      sub.removeFromSuperview()
    }
    for sub in cardContainer.subviews { sub.removeFromSuperview() }
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
        if msg.type == "artifact" {
          let row = NSButton(title: "▣  \(msg.title.isEmpty ? msg.text : msg.title)  artifact", target: self, action: #selector(handleArtifactTap(_:)))
          row.identifier = NSUserInterfaceItemIdentifier(msg.id.isEmpty ? msg.url : msg.id)
          row.attributedTitle = NSAttributedString(string: row.title, attributes: [.font: SnippetTheme.sans(11.5, weight: .medium), .foregroundColor: SnippetTheme.fg2])
          row.frame = NSRect(x: 8, y: y, width: width - 16, height: 28)
          row.wantsLayer = true
          row.layer?.backgroundColor = SnippetTheme.surface1.cgColor
          row.layer?.cornerRadius = 10
          row.isBordered = false
          documentView.addSubview(row)
          y += 34
          continue
        }
        if msg.type == "image" {
          let image = NSImage(contentsOfFile: msg.path)
          if let image = image {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.frame = NSRect(x: 8, y: y, width: 72, height: 48)
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
            view.layer?.masksToBounds = true
            view.identifier = NSUserInterfaceItemIdentifier(msg.path.isEmpty ? msg.url : msg.path)
            view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleImageTap(_:))))
            documentView.addSubview(view)
            y += 54
          }
          continue
        }
        if msg.type == "activity" {
          let dot = NSView(frame: NSRect(x: 8, y: y + 5, width: 5, height: 5))
          dot.wantsLayer = true
          dot.layer?.backgroundColor = (msg.live ? SnippetTheme.accent : SnippetTheme.fg4).cgColor
          dot.layer?.cornerRadius = 2.5
          documentView.addSubview(dot)
          let line = NSTextField(labelWithString: msg.text)
          line.font = SnippetTheme.sans(11.5, weight: .regular)
          line.textColor = SnippetTheme.fg4
          line.frame = NSRect(x: 18, y: y, width: width - 28, height: 16)
          documentView.addSubview(line)
          y += 19
          continue
        }
        if msg.type == "lane" {
          let line = NSTextField(labelWithString: "\(msg.title.isEmpty ? msg.text : msg.title) · \(msg.state) · \(msg.text)")
          line.font = SnippetTheme.sans(11.5, weight: .regular)
          line.textColor = SnippetTheme.fg3
          line.frame = NSRect(x: 10, y: y, width: width - 20, height: 18)
          documentView.addSubview(line)
          y += 21
          continue
        }
        if msg.type == "question" || msg.type == "approval" {
          if msg.type == "question" || convMessages.last(where: { $0.type == "approval" })?.id == msg.id {
            let title = NSTextField(labelWithString: msg.text)
            title.font = SnippetTheme.sans(12, weight: .medium)
            title.textColor = SnippetTheme.fg1
            title.lineBreakMode = .byTruncatingTail
            title.frame = NSRect(x: 10, y: cardContainer.bounds.height - 26, width: cardContainer.bounds.width - 20, height: 18)
            cardContainer.addSubview(title)
            if msg.type == "question", !msg.choices.isEmpty {
              for (index, choice) in msg.choices.prefix(3).enumerated() {
                let button = NSButton(title: choice, target: self, action: #selector(handleChoice(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(choice)
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 10 + CGFloat(index) * 92, y: 8, width: 86, height: 28)
                if msg.answerKind == "multi" {
                  button.setButtonType(.pushOnPushOff)
                  button.state = selectedChoices.contains(choice) ? .on : .off
                }
                cardContainer.addSubview(button)
              }
              if msg.answerKind == "multi" {
                let send = NSButton(title: "Send", target: self, action: #selector(handleSendChoices))
                send.bezelStyle = .rounded
                send.keyEquivalent = "\r"
                send.frame = NSRect(x: cardContainer.bounds.width - 76, y: 8, width: 64, height: 28)
                cardContainer.addSubview(send)
              }
            }
            if msg.type == "approval" {
              let approve = NSButton(title: "Approve", target: self, action: #selector(handleNotchAction(_:)))
              approve.identifier = NSUserInterfaceItemIdentifier("approve")
              approve.bezelStyle = .rounded
              approve.frame = NSRect(x: cardContainer.bounds.width - 150, y: 8, width: 68, height: 28)
              let deny = NSButton(title: "Deny", target: self, action: #selector(handleNotchAction(_:)))
              deny.identifier = NSUserInterfaceItemIdentifier("deny")
              deny.bezelStyle = .rounded
              deny.frame = NSRect(x: cardContainer.bounds.width - 76, y: 8, width: 64, height: 28)
              cardContainer.addSubview(approve)
              cardContainer.addSubview(deny)
            }
          }
          continue
        }
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
          // Plain full-width Markdown aligned left in SF Pro 13.5pt (#EEEEF1), with NO left-side blue ribbon.
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
    bottomCornerRadius: CGFloat,
    hasUnreadNotification: Bool,
    notifStartedAt: TimeInterval,
    notifDuration: TimeInterval,
    callMode: String?
  ) {
    self.callMode = callMode
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
    self.hasUnreadNotification = hasUnreadNotification
    self.notifStartedAt = notifStartedAt
    self.notifDuration = notifDuration
    needsLayout = true
    needsDisplay = true
  }

  func stepAnimation() {
    phase += 0.08
    if notifTitle != nil && !conversationExpanded {
      setNeedsDisplay(NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 3))
    }
    guard !conversationExpanded && notifTitle == nil && (ambientActive || assistantSpeaking || userSpeaking) else {
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
    if !conversationExpanded && callMode == nil {
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

    NSColor.black.setFill()
    b.fill()
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
      return
    }

    let topBandMidY = b.maxY - hwNotchHeight / 2
    if hasUnreadNotification && notifTitle == nil {
      let barsShown = ambientActive || assistantSpeaking || userSpeaking
      let dot: NSRect
      if barsShown {
        let cameraLeft = b.midX - hwNotchWidth / 2
        let leftWingX = b.minX + topCornerRadius
        let mochiX = leftWingX + (max(24, cameraLeft - leftWingX) - 18) / 2
        dot = NSRect(x: mochiX + 14, y: topBandMidY + 4, width: 6, height: 6)
      } else {
        let cameraRight = b.midX + hwNotchWidth / 2
        let wingWidth = max(24, b.maxX - topCornerRadius - cameraRight)
        dot = NSRect(x: cameraRight + (wingWidth - 7) / 2, y: topBandMidY - 3.5, width: 7, height: 7)
      }
      SnippetTheme.accent.setFill()
      NSBezierPath(ovalIn: dot).fill()
    }
    if callMode == "tracking" && notifTitle == nil {
      let left = b.minX + topCornerRadius + 16
      let rowMidY = b.minY + 17
      NSColor(srgbRed: 0.90, green: 0.45, blue: 0.40, alpha: 1).setFill()
      NSBezierPath(ovalIn: NSRect(x: left, y: rowMidY - 3, width: 6, height: 6)).fill()
      ("Tracking call" as NSString).draw(
        at: NSPoint(x: left + 14, y: rowMidY - 8),
        withAttributes: [.font: SnippetTheme.sans(12, weight: .medium), .foregroundColor: SnippetTheme.fg2])
    }
    if let title = notifTitle {
      drawNotificationDrop(in: b, title: title)
      let progress = CGFloat(max(0, min(1, 1 - (CACurrentMediaTime() - notifStartedAt) / notifDuration)))
      let inset = topCornerRadius + bottomCornerRadius
      let width = max(0, b.width - 2 * inset)
      NSGraphicsContext.current?.saveGraphicsState()
      shapePath.addClip()
      NSColor.white.withAlphaComponent(0.28).setFill()
      NSBezierPath(rect: NSRect(x: b.minX + inset, y: b.minY, width: width * progress, height: 1.5)).fill()
      NSGraphicsContext.current?.restoreGraphicsState()
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

    // Left Wing: Mochi icon only (never draw chat title text here since it crops)
    let leftWingX = b.minX + topCornerRadius
    let leftWingW = max(24, cameraLeft - leftWingX)
    let mochiSize: CGFloat = 18
    let mochiX = leftWingX + (leftWingW - mochiSize) / 2
    let mochiRect = NSRect(
      x: mochiX,
      y: topBandMidY - mochiSize / 2,
      width: mochiSize,
      height: mochiSize
    )
    do {
      MochiRenderer.drawMochi(
        in: mochiRect,
        bodyColor: userSpeaking ? matcha : periwinkle,
        leafColor: matcha,
        eyeColor: ink,
        blushColor: blush
      )
    }

    // Right Wing: 5-bar listening/speaking equalizer ONLY when listening/speaking is actually active
    if notifTitle == nil && (ambientActive || assistantSpeaking || userSpeaking) {
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

  private func drawNotificationDrop(in b: NSRect, title: String) {
    let left = b.minX + topCornerRadius + 16
    let width = max(0, b.maxX - topCornerRadius - 16 - left)
    let top = b.maxY - hwNotchHeight - 6

    let channelStyle = NSMutableParagraphStyle()
    channelStyle.lineBreakMode = .byTruncatingTail
    let channelAttrs: [NSAttributedString.Key: Any] = [
      .font: SnippetTheme.sans(11.5, weight: .medium),
      .foregroundColor: SnippetTheme.fg3,
      .paragraphStyle: channelStyle,
    ]
    (title as NSString).draw(
      in: NSRect(x: left, y: top - 15, width: width, height: 15),
      withAttributes: channelAttrs)

    let rawPreview = NotchMarkdown.plainPreview(notifSubtitle ?? "")
    let preview = rawPreview.isEmpty ? title : rawPreview
    let messageStyle = NSMutableParagraphStyle()
    messageStyle.lineBreakMode = .byWordWrapping
    let messageAttrs: [NSAttributedString.Key: Any] = [
      .font: SnippetTheme.sans(12.5, weight: .regular),
      .foregroundColor: SnippetTheme.fg1,
      .paragraphStyle: messageStyle,
    ]
    let messageTop = top - 17
    let messageRect = NSRect(x: left, y: b.minY + 6, width: width, height: max(0, messageTop - b.minY - 6))
    (preview as NSString).draw(
      with: messageRect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: messageAttrs)
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

}
