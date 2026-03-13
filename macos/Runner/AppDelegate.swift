import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var recordingOverlayWindow: NSPanel?
  var waveformViews: [NSView] = []
  var waveTimer: Timer?
  var statusLabel: NSTextField?
  var isShowingRecording = false
  var currentOverlayMode: String = "streaming" // "streaming" or "offline"

  // Mint Green accent color (#2ECC71)
  let accentColor = NSColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)

  // FFT spectrum function pointer from native dylib
  typealias GetAudioSpectrumFunc = @convention(c) (UnsafeMutablePointer<Float>, Int32) -> Void
  var getAudioSpectrum: GetAudioSpectrumFunc?
  var spectrumBuffer = [Float](repeating: 0, count: 7)

  private func loadSpectrumFunction() {
    if getAudioSpectrum != nil { return }
    let bundle = Bundle.main
    let dylibPath = bundle.bundlePath + "/Contents/MacOS/native_lib/libnative_input.dylib"
    guard let handle = dlopen(dylibPath, RTLD_NOW) else {
      NSLog("[Overlay] Failed to load dylib: %@", String(cString: dlerror()))
      return
    }
    guard let sym = dlsym(handle, "get_audio_spectrum") else {
      NSLog("[Overlay] get_audio_spectrum symbol not found")
      return
    }
    getAudioSpectrum = unsafeBitCast(sym, to: GetAudioSpectrumFunc.self)
    NSLog("[Overlay] FFT spectrum function loaded")
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

    let isOffline = (mode == "offline")
    // Offline: compact (waveform only), Streaming: full width (waveform + subtitle)
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
      barView.layer?.backgroundColor = accentColor.cgColor
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
    loadSpectrumFunction()

    guard let panel = recordingOverlayWindow else { return }
    let panelHeight = panel.frame.height

    waveTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      guard let self = self, self.isShowingRecording else { return }

      let maxHeight: CGFloat = 24
      let minHeight: CGFloat = 4
      let waveY: CGFloat = (panelHeight - 24) / 2

      // Get FFT spectrum data from native lib
      if let spectrumFunc = self.getAudioSpectrum {
        self.spectrumBuffer.withUnsafeMutableBufferPointer { ptr in
          spectrumFunc(ptr.baseAddress!, 7)
        }
      }

      // Animate each bar based on spectrum
      for (i, barView) in self.waveformViews.enumerated() {
        let spectrum = i < self.spectrumBuffer.count ? CGFloat(self.spectrumBuffer[i]) : 0
        let clampedSpectrum = min(max(spectrum, 0), 1)
        let barHeight = minHeight + (maxHeight - minHeight) * clampedSpectrum
        let yOffset = waveY + (maxHeight - barHeight) / 2

        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.08
          barView.animator().frame = NSRect(
            x: barView.frame.origin.x,
            y: yOffset,
            width: barView.frame.width,
            height: barHeight
          )
        }
      }
    }
  }

  private func hideRecordingOverlay() {
    NSLog("[Overlay] hideRecordingOverlay called")
    isShowingRecording = false
    waveTimer?.invalidate()
    waveTimer = nil
    recordingOverlayWindow?.orderOut(nil)
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
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
