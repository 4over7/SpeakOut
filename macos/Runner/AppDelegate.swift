import Cocoa
import Security
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var recordingOverlayWindow: NSPanel?
  var waveformViews: [NSView] = []
  var waveTimer: Timer?
  var statusLabel: NSTextField?
  var silenceHintWindow: NSPanel?
  var isShowingRecording = false
  var currentOverlayMode: String = "streaming" // "streaming" or "offline"

  // Mint Green accent color (#2ECC71) for normal recording
  let accentColor = NSColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
  // Purple accent color (#9B59B6) for diary/flash note mode
  let diaryColor = NSColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1.0)
  // Teal accent color (#1ABC9C) for AI organize mode
  let organizeColor = NSColor(red: 0.10, green: 0.74, blue: 0.61, alpha: 1.0)

  // Native audio level function pointer from dylib
  typealias GetAudioLevelFunc = @convention(c) () -> Float
  var getAudioLevelFunc: GetAudioLevelFunc?

  private func loadAudioLevelFunction() {
    if getAudioLevelFunc != nil { return }
    let dylibPath = Bundle.main.bundlePath + "/Contents/MacOS/native_lib/libnative_input.dylib"
    guard let handle = dlopen(dylibPath, RTLD_NOW) else {
      NSLog("[Overlay] Failed to load dylib: %@", String(cString: dlerror()))
      return
    }
    guard let sym = dlsym(handle, "get_audio_level") else {
      NSLog("[Overlay] get_audio_level symbol not found")
      return
    }
    getAudioLevelFunc = unsafeBitCast(sym, to: GetAudioLevelFunc.self)
    NSLog("[Overlay] Audio level function loaded")
  }

  // MARK: - Security-scoped bookmark（沙盒版的闪念目录权限）
  //
  // App Store 版开了 app-sandbox，而 NSOpenPanel（Powerbox）给的授权**不跨进程**。
  // 原来只把 url.path 交回 Dart 存进配置，重启后 Dart 照着这个路径写文件，
  // 沙盒直接拒绝 —— 闪念笔记从此静默写不进去，用户看不到任何原因。
  // 要跨启动保住权限，必须存 security-scoped bookmark，启动时解析并
  // startAccessingSecurityScopedResource()。
  //
  // 非沙盒的 Release 版不需要这套，但这段代码在那里也无害。
  // pickFile（导入模型 .tar.bz2）不需要：它在同一次会话里读完就结束，
  // Powerbox 的临时授权覆盖得到。
  private static let diaryBookmarkKey = "SpeakOutDiaryDirBookmark"
  private var scopedDiaryURL: URL?

  /// 是否运行在 App Sandbox 里。沙盒下 bookmark 失败 = 目录不可用，必须报错；
  /// 非沙盒下 bookmark 只是锦上添花，失败了普通文件权限照样能写，不该打扰用户。
  ///
  /// **不能用 `APP_SANDBOX_CONTAINER_ID` 这个环境变量判断** —— 那是运行环境的
  /// 实现细节而非公开契约，已知有沙盒进程读不到它。误判的代价是实打实的：
  /// 漏判成非沙盒时，拿不到持久授权也照样把路径返回给 Dart，重启后闪念静默失效。
  /// 这里读自己的 entitlement，是 Apple 给的标准做法。
  private lazy var isSandboxed: Bool = {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let value = SecTaskCopyValueForEntitlement(
      task, "com.apple.security.app-sandbox" as CFString, nil)
    return (value as? Bool) ?? false
  }()

  private func makeBookmark(for url: URL) -> Data? {
    do {
      return try url.bookmarkData(options: [.withSecurityScope],
                                  includingResourceValuesForKeys: nil,
                                  relativeTo: nil)
    } catch {
      NSLog("[Sandbox] 创建 bookmark 失败: %@", String(describing: error))
      return nil
    }
  }

  /// 解析 bookmark 并真正取得访问权。成功才返回 URL —— 调用方据此决定
  /// 要不要提交这次目录切换。
  private func acquireScope(from data: Data) -> URL? {
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else {
        NSLog("[Sandbox] startAccessingSecurityScopedResource 失败: %@", url.path)
        return nil
      }
      // stale 说明目录被移动/改名过，此刻立刻重建，否则下次启动就解析不出来了
      if stale, let fresh = makeBookmark(for: url) {
        UserDefaults.standard.set(fresh, forKey: Self.diaryBookmarkKey)
      }
      return url
    } catch {
      NSLog("[Sandbox] 解析 bookmark 失败: %@", String(describing: error))
      return nil
    }
  }

  @discardableResult
  private func restoreScopedDiaryAccess() -> Bool {
    guard let data = UserDefaults.standard.data(forKey: Self.diaryBookmarkKey) else {
      return false
    }
    guard let url = acquireScope(from: data) else { return false }
    scopedDiaryURL = url
    NSLog("[Sandbox] 已恢复闪念目录访问权限: %@", url.path)
    return true
  }

  /// 切换闪念目录。**整件事要么全成、要么什么都不动。**
  /// 上一版是「建 bookmark → 放掉旧 scope → 试着恢复 → 不管成没成都返回路径」：
  /// 新目录能生成 bookmark 但解析/取权失败时，旧授权已经放掉、旧 bookmark 已被
  /// 覆盖，用户配置却指向一个写不进去的目录 —— 本次会话靠 Powerbox 临时授权
  /// 还能写，重启后就静默失效。所以先拿到新权限，再提交。
  private func switchDiaryDirectory(to url: URL) -> Bool {
    guard let data = makeBookmark(for: url) else { return false }
    let previous = scopedDiaryURL
    scopedDiaryURL = nil
    guard let acquired = acquireScope(from: data) else {
      scopedDiaryURL = previous // 新的没拿到，旧 scope 原样留着
      return false
    }
    previous?.stopAccessingSecurityScopedResource()
    scopedDiaryURL = acquired
    UserDefaults.standard.set(data, forKey: Self.diaryBookmarkKey)
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    restoreScopedDiaryAccess()

    // Setup MethodChannel for recording overlay control
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.SpeakOut/overlay",
        binaryMessenger: controller.engine.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] (call, result) in
        // Debug Log: Trace Incoming Calls
        NSLog("[Overlay] MethodChannel received: %@", call.method)

        switch call.method {
        case "showRecording":
          let args = call.arguments as? [String: Any]
          let text = args?["text"] as? String ?? ""
          let mode = args?["mode"] as? String ?? "streaming"
          self?.showRecordingOverlay(initialText: text, mode: mode)
          result(nil)
        case "updateStatus":
          if let args = call.arguments as? [String: Any], let text = args["text"] as? String {
            self?.updateStatusLabel(text)
          }
          result(nil)
        case "hideRecording":
          self?.hideRecordingOverlay()
          result(nil)
        case "showSilenceHint":
          self?.showSilenceHint()
          result(nil)
        case "hideSilenceHint":
          self?.hideSilenceHint()
          result(nil)
        case "pickDirectory":
          self?.pickDirectory(result: result)
        case "pickFile":
          self?.pickFile(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func showRecordingOverlay(initialText: String, mode: String = "streaming") {
    NSLog("[Overlay] showRecordingOverlay called with text: %@, mode: %@", initialText, mode)
    let previousMode = currentOverlayMode
    currentOverlayMode = mode

    // 1. Always calculate target position logic FIRST (Dynamic Multi-Monitor Support)
    let mouseLoc = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main

    guard let targetScreen = screen else { return }

    let isDiary = (mode == "diary")
    let isOrganize = (mode == "organize")
    let isOffline = (mode == "offline") || isDiary || isOrganize  // compact mode for diary/organize
    let barColor = isDiary ? diaryColor : (isOrganize ? organizeColor : accentColor)
    // Offline/Diary: compact (waveform only), Streaming: full width (waveform + subtitle)
    let panelWidth: CGFloat = isOffline ? 120 : 400
    let panelHeight: CGFloat = 50

    // Calculate position relative to the target screen
    let xPos = targetScreen.frame.origin.x + (targetScreen.frame.width - panelWidth) / 2
    let yPos = targetScreen.frame.origin.y + 60

    // 2. If same mode and window exists, reuse; otherwise recreate
    if let panel = recordingOverlayWindow, panel.frame.width == panelWidth && previousMode == mode {
      // Same mode, reuse existing window
      panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
      panel.orderFront(nil)
      if !isOffline { updateStatusLabel(initialText) }
      startWaveAnimation()
      return
    }

    // Tear down old window if mode changed
    if recordingOverlayWindow != nil {
      hideRecordingOverlay()
      recordingOverlayWindow = nil
    }

    // 3. Create New Window
    let panel = NSPanel(
      contentRect: NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let backgroundView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    backgroundView.wantsLayer = true
    backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
    backgroundView.layer?.cornerRadius = panelHeight / 2
    backgroundView.layer?.masksToBounds = true

    // === WAVEFORM BARS ===
    let barCount = 7
    let barWidth: CGFloat = 5
    let barSpacing: CGFloat = 6
    let waveGroupWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    // Offline: center waveform in compact panel; Streaming: left-aligned
    let waveStartX: CGFloat = isOffline
      ? (panelWidth - waveGroupWidth) / 2
      : 24
    let waveY: CGFloat = (panelHeight - 24) / 2

    waveformViews.removeAll()
    for i in 0..<barCount {
      let barX = waveStartX + CGFloat(i) * (barWidth + barSpacing)
      let barView = NSView(
        frame: NSRect(x: barX, y: waveY, width: barWidth, height: 8))
      barView.wantsLayer = true
      barView.layer?.backgroundColor = barColor.cgColor
      barView.layer?.cornerRadius = barWidth / 2
      backgroundView.addSubview(barView)
      waveformViews.append(barView)
    }

    // === STATUS LABEL (streaming mode only) ===
    if !isOffline {
      let labelX = waveStartX + waveGroupWidth + 20
      let labelWidth = panelWidth - labelX - 24
      let label = NSTextField(
        frame: NSRect(x: labelX, y: (panelHeight - 20) / 2, width: labelWidth, height: 20))
      label.stringValue = initialText
      label.alignment = .left
      label.isEditable = false
      label.isBordered = false
      label.drawsBackground = false
      label.textColor = NSColor.white.withAlphaComponent(0.7)
      label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
      label.lineBreakMode = .byTruncatingTail
      backgroundView.addSubview(label)
      statusLabel = label
    } else {
      statusLabel = nil
    }

    panel.contentView = backgroundView
    recordingOverlayWindow = panel

    panel.orderFront(nil)
    startWaveAnimation()
  }

  private func updateStatusLabel(_ text: String) {
    statusLabel?.stringValue = text
  }

  private func startWaveAnimation() {
    isShowingRecording = true
    loadAudioLevelFunction()

    guard let panel = recordingOverlayWindow else { return }
    let panelHeight = panel.frame.height

    waveTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      guard let self = self, self.isShowingRecording else { return }

      let maxHeight: CGFloat = 36
      let minHeight: CGFloat = 4
      let waveY: CGFloat = (panelHeight - maxHeight) / 2

      // Get real-time audio level (0.0 ~ 1.0)
      let level = CGFloat(self.getAudioLevelFunc?() ?? 0)
      let minScale: CGFloat = 0.08
      let scale = minScale + (1.0 - minScale) * min(max(level, 0), 1)

      // Random animation scaled by audio level
      for barView in self.waveformViews {
        let randomHeight = minHeight + (maxHeight - minHeight) * CGFloat.random(in: 0...1) * scale
        let yOffset = waveY + (maxHeight - randomHeight) / 2

        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.08
          barView.animator().frame = NSRect(
            x: barView.frame.origin.x,
            y: yOffset,
            width: barView.frame.width,
            height: randomHeight
          )
        }
      }
    }
  }

  private func showSilenceHint() {
    guard let overlay = recordingOverlayWindow else { return }
    if silenceHintWindow != nil { return } // already showing

    let hintText = "🎤 未检测到声音"
    let hintWidth: CGFloat = 140
    let hintHeight: CGFloat = 22
    let overlayFrame = overlay.frame
    let hintX = overlayFrame.origin.x + (overlayFrame.width - hintWidth) / 2
    let hintY = overlayFrame.origin.y - hintHeight - 4

    let panel = NSPanel(
      contentRect: NSRect(x: hintX, y: hintY, width: hintWidth, height: hintHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false
    )
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let bg = NSView(frame: NSRect(x: 0, y: 0, width: hintWidth, height: hintHeight))
    bg.wantsLayer = true
    bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    bg.layer?.cornerRadius = hintHeight / 2

    let label = NSTextField(frame: NSRect(x: 8, y: 1, width: hintWidth - 16, height: hintHeight - 2))
    label.stringValue = hintText
    label.alignment = .center
    label.isEditable = false
    label.isBordered = false
    label.drawsBackground = false
    label.textColor = NSColor.white.withAlphaComponent(0.7)
    label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
    bg.addSubview(label)

    panel.contentView = bg
    panel.orderFront(nil)
    silenceHintWindow = panel
  }

  private func hideSilenceHint() {
    silenceHintWindow?.orderOut(nil)
    silenceHintWindow = nil
  }

  private func hideRecordingOverlay() {
    NSLog("[Overlay] hideRecordingOverlay called")
    isShowingRecording = false
    waveTimer?.invalidate()
    waveTimer = nil
    recordingOverlayWindow?.orderOut(nil)
    hideSilenceHint()
  }

  private func pickFile(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.init(filenameExtension: "bz2")!]
    panel.prompt = "Import"
    panel.message = "Select a .tar.bz2 model file"

    panel.begin { response in
      if response == .OK, let url = panel.url {
        result(url.path)
      } else {
        result(nil)
      }
    }
  }

  private func pickDirectory(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true  // Critical: Allow creating new folders
    panel.prompt = "Select"

    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      guard let self = self else {
        result(url.path)
        return
      }
      let ok = self.switchDiaryDirectory(to: url)
      if !ok && self.isSandboxed {
        // 沙盒下拿不到跨启动授权 = 这个目录用不了。不能静默返回路径，
        // 否则用户这次能写、重启后闪念就静默丢失，而且看不到任何原因。
        // message 只进日志：给用户看的文案由 Dart 侧走 i18n
        result(FlutterError(code: "bookmark_failed",
                            message: "security-scoped bookmark unavailable",
                            details: url.path))
        return
      }
      result(url.path)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // Hide to tray instead of quitting
  }

  /// Dock 图标 / Spotlight 重新打开应用时，如果主窗口被关闭了就重新打开
  /// 没有这个方法 macOS 默认行为是"啥也不做"，导致点 Dock 图标无反应
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      if let window = mainFlutterWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
