import Cocoa
import FlutterMacOS
import QuartzCore

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// Height of the title bar the app paints itself. Must match
  /// `kTitleBarHeight` in lib/platform.dart.
  private let paintedTitleBarHeight: CGFloat = 40

  private var statusItem: NSStatusItem?
  private var ambientMenuItem: NSMenuItem?
  private var notchHUD: NotchHUDController?
  private var notchChannel: FlutterMethodChannel?
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
    let blurView = NSVisualEffectView()
    blurView.translatesAutoresizingMaskIntoConstraints = false
    blurView.blendingMode = .behindWindow
    blurView.material = .hudWindow
    blurView.state = .active
    blurView.appearance = NSAppearance(named: .darkAqua)
    wrapper.addSubview(blurView, positioned: .below, relativeTo: nil)
    NSLayoutConstraint.activate([
      blurView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
      blurView.topAnchor.constraint(equalTo: wrapper.topAnchor),
      blurView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

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
          let isMinimizedOrHidden = !self.isVisible || self.isMiniaturized || !NSApp.isActive
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
          let messages: [(role: String, text: String)] = rawMsgs.compactMap { m in
            guard let text = m["text"] as? String, !text.isEmpty else { return nil }
            let role = m["role"] as? String ?? "assistant"
            return (role: role, text: text)
          }
          self.notchHUD?.updateConversation(title: title, status: status, messages: messages)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    setupMenuBarItem()

    super.awakeFromNib()

    self.isOpaque = false
    self.backgroundColor = .clear
    flutterViewController.backgroundColor = .clear
    self.appearance = NSAppearance(named: .darkAqua)

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

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil)
  }

  deinit {
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
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let btn = item.button {
      btn.image = Self.makeMochiMenuBarIcon()
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

  private static func makeMochiMenuBarIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let img = NSImage(size: size, flipped: false) { _ in
      NSColor.labelColor.setFill()
      let dotR: CGFloat = 1.7
      let cols: [CGFloat] = [4.5, 9.0, 13.5]
      let rows: [CGFloat] = [6.2, 11.8]
      for x in cols {
        for y in rows {
          let r = NSRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
          NSBezierPath(ovalIn: r).fill()
        }
      }
      return true
    }
    img.isTemplate = true
    return img
  }

  @objc private func onWindowLayoutChanged() {
    centreTrafficLights()
  }

  /// Move the standard window buttons so they are vertically centred in the
  /// height the app paints, rather than in AppKit's own shorter titlebar band.
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

// MARK: - Key-Capable Non-Activating Notch Panel

final class NotchPanel: NSPanel {
  override var canBecomeKey: Bool { return true }
  override var canBecomeMain: Bool { return false }
}

// MARK: - Flipped Document View for Conversation Scroll

final class FlippedDocumentView: NSView {
  override var isFlipped: Bool { return true }
}

// MARK: - Dynamic Island / Notch HUD Controller

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

    let initialRect = NSRect(x: 0, y: 0, width: 260, height: 36)
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
    p.hasShadow = true
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
  }

  deinit {
    notifDismissTimer?.invalidate()
    waveTimer?.invalidate()
  }

  func setWindowHidden(_ hidden: Bool) {
    windowHidden = hidden
    if !hidden && conversationExpanded {
      collapseConversation()
      return
    }
    refreshHUD()
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
    refreshHUD()
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
      notifDismissTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { [weak self] _ in
        self?.clearNotification()
      }
    }
    refreshHUD()
  }

  func updateConversation(
    title: String,
    status: String,
    messages: [(role: String, text: String)]
  ) {
    hudView.setConversationData(title: title, status: status, messages: messages)
  }

  private func clearNotification() {
    notifTitle = nil
    notifSubtitle = nil
    notifKind = nil
    notifPayload = nil
    refreshHUD()
  }

  private func handleBannerTap() {
    if conversationExpanded {
      return
    }
    if let payload = notifPayload, !payload.isEmpty {
      let title = notifTitle ?? "Conversation"
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
        messages: sub.isEmpty ? [] : [(role: "assistant", text: sub)]
      )
      refreshHUD()
      onOpenConversation(payload)
    } else {
      onActivateWindow()
    }
  }

  private func collapseConversation() {
    guard conversationExpanded else { return }
    conversationExpanded = false
    activePayload = ""
    hudView.setConversationExpanded(false)
    onCloseConversation()
    refreshHUD()
  }

  private func refreshHUD() {
    let hasNotif = notifTitle != nil
    let showAmbient = ambientActive && (windowHidden || assistantSpeaking || userSpeaking)
    let shouldShow = conversationExpanded || hasNotif || showAmbient

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

    var hwNotchWidth: CGFloat = 186
    var hwNotchHeight: CGFloat = 32
    if #available(macOS 12.0, *) {
      let topInset = screen.safeAreaInsets.top
      if topInset > 0 {
        hwNotchHeight = max(topInset, 32)
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
          let gap = screenFrame.width - left.width - right.width
          if gap > 80 && gap < 320 {
            hwNotchWidth = gap
          }
        }
      }
    }

    let targetWidth: CGFloat
    let targetHeight: CGFloat
    if conversationExpanded {
      targetWidth = max(hwNotchWidth + 274, 460)
      targetHeight = 420
    } else if hasNotif {
      targetWidth = max(hwNotchWidth + 184, 376)
      targetHeight = max(hwNotchHeight + 36, 68)
    } else if assistantSpeaking || userSpeaking {
      targetWidth = max(hwNotchWidth + 132, 316)
      targetHeight = max(hwNotchHeight + 12, 44)
    } else {
      targetWidth = max(hwNotchWidth + 92, 268)
      targetHeight = max(hwNotchHeight, 34)
    }

    let targetX = screenFrame.midX - targetWidth / 2
    let targetY = screenFrame.maxY - targetHeight
    let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)

    hudView.configure(
      notifTitle: notifTitle,
      notifSubtitle: notifSubtitle,
      notifKind: notifKind,
      ambientActive: ambientActive,
      userSpeaking: userSpeaking,
      assistantSpeaking: assistantSpeaking,
      probability: speechProbability,
      topSafeInset: hwNotchHeight
    )

    if !panel.isVisible {
      let startFrame = NSRect(
        x: screenFrame.midX - hwNotchWidth / 2,
        y: screenFrame.maxY - hwNotchHeight,
        width: hwNotchWidth,
        height: hwNotchHeight
      )
      panel.setFrame(startFrame, display: false)
      panel.orderFrontRegardless()
    }

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = conversationExpanded ? 0.26 : 0.22
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(targetFrame, display: true)
    }

    if waveTimer == nil {
      waveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        self?.hudView.stepAnimation()
      }
    }
  }
}

// MARK: - Notch HUD View (Banner + Expandable Conversation Bar)

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
  private var topSafeInset: CGFloat = 32.0
  private var phase: CGFloat = 0.0

  private var conversationExpanded = false
  private var convTitle = "Conversation"
  private var convStatus = "idle"
  private var convMessages: [(role: String, text: String)] = []

  private let containerView = NSView()
  private let titleField = NSTextField(labelWithString: "Conversation")
  private let statusField = NSTextField(labelWithString: "")
  private let openAppButton = NSButton(title: "Open in Snippet ↗", target: nil, action: nil)
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

    titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    titleField.textColor = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
    titleField.lineBreakMode = .byTruncatingTail
    containerView.addSubview(titleField)

    statusField.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    statusField.textColor = NSColor(srgbRed: 0.55, green: 0.56, blue: 1.0, alpha: 1.0)
    containerView.addSubview(statusField)

    openAppButton.isBordered = false
    openAppButton.wantsLayer = true
    openAppButton.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1.0).cgColor
    openAppButton.layer?.cornerRadius = 6
    openAppButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    openAppButton.contentTintColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.90, alpha: 1.0)
    openAppButton.target = self
    openAppButton.action = #selector(handleOpenAppTap)
    containerView.addSubview(openAppButton)

    closeButton.isBordered = false
    closeButton.wantsLayer = true
    closeButton.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1.0).cgColor
    closeButton.layer?.cornerRadius = 6
    closeButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    closeButton.contentTintColor = NSColor(srgbRed: 0.72, green: 0.72, blue: 0.78, alpha: 1.0)
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
    replyContainer.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
    replyContainer.layer?.cornerRadius = 18
    replyContainer.layer?.borderWidth = 1
    replyContainer.layer?.borderColor = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.24, alpha: 1.0).cgColor
    containerView.addSubview(replyContainer)

    replyField.isBordered = false
    replyField.drawsBackground = false
    replyField.focusRingType = .none
    replyField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    replyField.textColor = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
    replyField.placeholderString = "Reply in conversation…"
    replyField.delegate = self
    replyField.target = self
    replyField.action = #selector(handleSendTap)
    replyContainer.addSubview(replyField)

    sendButton.isBordered = false
    sendButton.wantsLayer = true
    sendButton.layer?.backgroundColor = NSColor(srgbRed: 0.37, green: 0.42, blue: 0.82, alpha: 1.0).cgColor
    sendButton.layer?.cornerRadius = 13
    sendButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
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
    convMessages.append((role: "user", text: text))
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
    messages: [(role: String, text: String)]
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
    let topPad = max(topSafeInset + 6, 36)
    let contentRect = NSRect(
      x: 16,
      y: 14,
      width: max(100, b.width - 32),
      height: max(80, b.height - topPad - 14)
    )
    containerView.frame = contentRect

    let headerH: CGFloat = 28
    let headerY = contentRect.height - headerH
    closeButton.frame = NSRect(x: contentRect.width - 26, y: headerY + 1, width: 26, height: 24)
    openAppButton.frame = NSRect(x: contentRect.width - 26 - 6 - 116, y: headerY + 1, width: 116, height: 24)

    let statusW: CGFloat = statusField.stringValue.isEmpty ? 0 : 64
    if statusW > 0 {
      statusField.frame = NSRect(
        x: openAppButton.frame.minX - statusW - 8,
        y: headerY + 5,
        width: statusW,
        height: 16
      )
    } else {
      statusField.frame = .zero
    }

    let titleMaxX = (statusW > 0 ? statusField.frame.minX : openAppButton.frame.minX) - 8
    titleField.frame = NSRect(x: 4, y: headerY + 4, width: max(60, titleMaxX - 4), height: 20)

    let replyH: CGFloat = 36
    replyContainer.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: replyH)
    sendButton.frame = NSRect(x: contentRect.width - 31, y: 5, width: 26, height: 26)
    replyField.frame = NSRect(x: 14, y: 7, width: max(60, contentRect.width - 52), height: 22)

    let scrollY = replyH + 10
    let scrollH = max(40, headerY - 8 - scrollY)
    scrollView.frame = NSRect(x: 0, y: scrollY, width: contentRect.width, height: scrollH)
    rebuildMessageViews(scrollToBottom: false)
  }

  private func rebuildMessageViews(scrollToBottom: Bool) {
    guard conversationExpanded else { return }
    for sub in documentView.subviews {
      sub.removeFromSuperview()
    }
    let width = max(180, scrollView.contentSize.width)
    var y: CGFloat = 6

    if convMessages.isEmpty {
      let empty = NSTextField(labelWithString: convStatus == "loading" ? "Loading conversation…" : "No messages yet.")
      empty.font = NSFont.systemFont(ofSize: 12, weight: .regular)
      empty.textColor = NSColor(srgbRed: 0.56, green: 0.56, blue: 0.62, alpha: 1.0)
      empty.frame = NSRect(x: 8, y: 16, width: width - 16, height: 20)
      documentView.addSubview(empty)
      y = 48
    } else {
      for msg in convMessages {
        let isUser = msg.role == "user"
        let maxBubbleW = width * 0.84
        let font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 2.5
        let attrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: NSColor(
            srgbRed: isUser ? 0.95 : 0.90,
            green: isUser ? 0.95 : 0.90,
            blue: isUser ? 0.97 : 0.93,
            alpha: 1.0
          ),
          .paragraphStyle: pStyle,
        ]
        let attributed = NSAttributedString(string: msg.text, attributes: attrs)
        let textBounds = attributed.boundingRect(
          with: NSSize(width: maxBubbleW - 22, height: 4000),
          options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let bubbleW = min(maxBubbleW, max(54, ceil(textBounds.width) + 22))
        let bubbleH = max(28, ceil(textBounds.height) + 14)
        let bubbleX = isUser ? (width - bubbleW - 4) : 4

        let bubble = NSView(frame: NSRect(x: bubbleX, y: y, width: bubbleW, height: bubbleH))
        bubble.wantsLayer = true
        if isUser {
          bubble.layer?.backgroundColor = NSColor(srgbRed: 0.20, green: 0.21, blue: 0.26, alpha: 1.0).cgColor
          bubble.layer?.cornerRadius = 10
        } else {
          bubble.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0).cgColor
          bubble.layer?.cornerRadius = 8
          bubble.layer?.borderWidth = 1
          bubble.layer?.borderColor = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).cgColor
        }

        let label = NSTextField(wrappingLabelWithString: msg.text)
        label.font = font
        label.textColor = NSColor(
          srgbRed: isUser ? 0.95 : 0.90,
          green: isUser ? 0.95 : 0.90,
          blue: isUser ? 0.97 : 0.93,
          alpha: 1.0
        )
        label.isSelectable = true
        label.frame = NSRect(x: 11, y: 7, width: bubbleW - 22, height: bubbleH - 14)
        bubble.addSubview(label)
        documentView.addSubview(bubble)

        y += bubbleH + 8
      }
    }

    let docH = max(scrollView.contentSize.height, y + 4)
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
    topSafeInset: CGFloat
  ) {
    self.notifTitle = notifTitle
    self.notifSubtitle = notifSubtitle
    self.notifKind = notifKind
    self.ambientActive = ambientActive
    self.userSpeaking = userSpeaking
    self.assistantSpeaking = assistantSpeaking
    self.probability = probability
    self.topSafeInset = topSafeInset
    needsLayout = true
    needsDisplay = true
  }

  func stepAnimation() {
    phase += 0.24
    if !conversationExpanded {
      needsDisplay = true
    }
  }

  override func mouseDown(with event: NSEvent) {
    if !conversationExpanded {
      onBannerTap?()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let b = bounds
    guard b.width > 10 && b.height > 10 else { return }

    let inset = b.insetBy(dx: 1.5, dy: 1.5)
    let path = Self.notchPath(in: inset, bottomRadius: conversationExpanded ? 20 : 16)

    // Deep pitch-black notch fill so it merges seamlessly with the MacBook physical notch
    NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 0.98).setFill()
    path.fill()

    // Subtle glowing rim matching the active state
    let accentColor: NSColor
    if conversationExpanded {
      accentColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 1.0, alpha: 0.85)
    } else if let kind = notifKind {
      switch kind {
      case "error", "failed":
        accentColor = NSColor(srgbRed: 0.92, green: 0.34, blue: 0.34, alpha: 1.0)
      case "waiting":
        accentColor = NSColor(srgbRed: 0.85, green: 0.62, blue: 0.27, alpha: 1.0)
      case "done", "completed":
        accentColor = NSColor(srgbRed: 0.30, green: 0.76, blue: 0.54, alpha: 1.0)
      default:
        accentColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 1.0, alpha: 1.0)
      }
    } else if assistantSpeaking {
      accentColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 1.0, alpha: 1.0)
    } else if userSpeaking {
      accentColor = NSColor(srgbRed: 0.30, green: 0.76, blue: 0.54, alpha: 1.0)
    } else {
      accentColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 1.0, alpha: 0.65)
    }

    let pulseAlpha: CGFloat = (assistantSpeaking || userSpeaking)
      ? (0.45 + 0.25 * CGFloat(sin(Double(phase))))
      : 0.34
    accentColor.withAlphaComponent(pulseAlpha).setStroke()
    path.lineWidth = (assistantSpeaking || userSpeaking) ? 1.5 : 1.0
    path.stroke()

    if conversationExpanded {
      // Separator line below the header inside the expanded notch drawer
      let headerSepY = inset.maxY - max(topSafeInset + 6, 36) - 32
      let sep = NSBezierPath()
      sep.move(to: NSPoint(x: inset.minX + 14, y: headerSepY))
      sep.line(to: NSPoint(x: inset.maxX - 14, y: headerSepY))
      NSColor(srgbRed: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).setStroke()
      sep.lineWidth = 1.0
      sep.stroke()
      return
    }

    if let title = notifTitle {
      drawNotification(in: inset, title: title, subtitle: notifSubtitle ?? "", accent: accentColor)
    } else {
      drawAmbient(in: inset, accent: accentColor)
    }
  }

  private func drawAmbient(in rect: NSRect, accent: NSColor) {
    let orbSize: CGFloat = (assistantSpeaking || userSpeaking) ? 9.0 : 7.0
    let orbX = rect.minX + 18
    let orbY = rect.midY - orbSize / 2
    let glowRect = NSRect(x: orbX - 3, y: orbY - 3, width: orbSize + 6, height: orbSize + 6)
    accent.withAlphaComponent(0.28).setFill()
    NSBezierPath(ovalIn: glowRect).fill()
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: orbX, y: orbY, width: orbSize, height: orbSize)).fill()

    let barCount = 5
    let barWidth: CGFloat = 2.6
    let barGap: CGFloat = 2.8
    let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
    let startX = rect.maxX - 16 - totalW

    for i in 0..<barCount {
      let wave = sin(Double(phase) + Double(i) * 0.85)
      let activeAmp: CGFloat = assistantSpeaking
        ? 1.0
        : (userSpeaking ? max(CGFloat(probability), 0.55) : 0.22)
      let barH = max(4.0, (4.0 + 11.0 * activeAmp * CGFloat(0.5 + 0.5 * wave)))
      let bx = startX + CGFloat(i) * (barWidth + barGap)
      let by = rect.midY - barH / 2
      let barRect = NSRect(x: bx, y: by, width: barWidth, height: barH)
      accent.withAlphaComponent(0.9).setFill()
      NSBezierPath(roundedRect: barRect, xRadius: 1.3, yRadius: 1.3).fill()
    }

    if assistantSpeaking || userSpeaking {
      let label = assistantSpeaking ? "Snippet speaking" : "Hearing you"
      let style = NSMutableParagraphStyle()
      style.alignment = .left
      style.lineBreakMode = .byTruncatingTail
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 0.92),
        .paragraphStyle: style,
      ]
      let textRect = NSRect(
        x: orbX + orbSize + 8,
        y: rect.midY - 8,
        width: max(0, startX - (orbX + orbSize + 14)),
        height: 16
      )
      (label as NSString).draw(in: textRect, withAttributes: attrs)
    }
  }

  private func drawNotification(
    in rect: NSRect,
    title: String,
    subtitle: String,
    accent: NSColor
  ) {
    let dotSize: CGFloat = 8.0
    let dotX = rect.minX + 18
    let dotY = rect.minY + 20
    accent.withAlphaComponent(0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: dotX - 3, y: dotY - 3, width: dotSize + 6, height: dotSize + 6)).fill()
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)).fill()

    let hintText = "Click to open thread"
    let hintAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
      .foregroundColor: accent.withAlphaComponent(0.9),
    ]
    let hintSize = (hintText as NSString).size(withAttributes: hintAttrs)
    let hintX = rect.maxX - hintSize.width - 16
    (hintText as NSString).draw(
      at: NSPoint(x: hintX, y: rect.minY + 26),
      withAttributes: hintAttrs
    )

    let textX = dotX + dotSize + 10
    let textW = max(10, hintX - textX - 10)

    let pStyle = NSMutableParagraphStyle()
    pStyle.lineBreakMode = .byTruncatingTail

    let titleAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
      .foregroundColor: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1.0),
      .paragraphStyle: pStyle,
    ]
    let subAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
      .foregroundColor: NSColor(srgbRed: 0.65, green: 0.65, blue: 0.70, alpha: 1.0),
      .paragraphStyle: pStyle,
    ]

    (title as NSString).draw(
      in: NSRect(x: textX, y: rect.minY + 24, width: textW, height: 17),
      withAttributes: titleAttrs
    )
    if !subtitle.isEmpty {
      (subtitle as NSString).draw(
        in: NSRect(x: textX, y: rect.minY + 7, width: textW, height: 16),
        withAttributes: subAttrs
      )
    }
  }

  /// Builds a top-anchored notch silhouette (flat along the top screen edge,
  /// rounded bottom corners).
  private static func notchPath(in rect: NSRect, bottomRadius: CGFloat) -> NSBezierPath {
    let r = min(bottomRadius, rect.height / 2, rect.width / 2)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.minX, y: rect.minY + r))
    path.appendArc(
      withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r),
      radius: r,
      startAngle: 180,
      endAngle: 270,
      clockwise: false
    )
    path.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
    path.appendArc(
      withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r),
      radius: r,
      startAngle: 270,
      endAngle: 360,
      clockwise: false
    )
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    path.close()
    return path
  }
}
