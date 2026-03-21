import Cocoa
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

  override func applicationDidFinishLaunching(_ notification: Notification) {
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
    currentOverlayMode = mode

    // 1. Always calculate target position logic FIRST (Dynamic Multi-Monitor Support)
    let mouseLoc = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main

    guard let targetScreen = screen else { return }

    let isDiary = (mode == "diary")
    let isOffline = (mode == "offline") || isDiary  // diary also uses compact mode
    let barColor = isDiary ? diaryColor : accentColor
    // Offline/Diary: compact (waveform only), Streaming: full width (waveform + subtitle)
    let panelWidth: CGFloat = isOffline ? 120 : 400
    let panelHeight: CGFloat = 50

    // Calculate position relative to the target screen
    let xPos = targetScreen.frame.origin.x + (targetScreen.frame.width - panelWidth) / 2
    let yPos = targetScreen.frame.origin.y + 60

    // 2. If mode changed or window doesn't exist, recreate
    if let panel = recordingOverlayWindow, panel.frame.width == panelWidth {
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

    panel.begin { response in
      if response == .OK, let url = panel.url {
        result(url.path)
      } else {
        result(nil)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // Hide to tray instead of quitting
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
