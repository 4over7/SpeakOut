import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var recordingOverlayWindow: NSPanel?
  var waveformViews: [NSView] = []
  var waveTimer: Timer?
  var statusLabel: NSTextField?
  var isShowingRecording = false

  // Mint Green accent color (#2ECC71)
  let accentColor = NSColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)

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
          if let args = call.arguments as? [String: Any], let text = args["text"] as? String {
            self?.showRecordingOverlay(initialText: text)
          } else {
            self?.showRecordingOverlay(initialText: "")
          }
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
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func showRecordingOverlay(initialText: String) {
    NSLog("[Overlay] showRecordingOverlay called with text: %@", initialText)
    // 1. Always calculate target position logic FIRST (Dynamic Multi-Monitor Support)
    let mouseLoc = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main

    guard let targetScreen = screen else { return }

    let panelWidth: CGFloat = 400
    let panelHeight: CGFloat = 50

    // Calculate position relative to the target screen
    let xPos = targetScreen.frame.origin.x + (targetScreen.frame.width - panelWidth) / 2
    let yPos = targetScreen.frame.origin.y + 60

    // 2. Reuse Existing Window if available
    if let panel = recordingOverlayWindow {
      // CRITICAL FIX: Move window to the new cursor screen
      panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
      panel.orderFront(nil)
      updateStatusLabel(initialText)  // ensure text is fresh
      startWaveAnimation()
      return
    }

    // 3. Create New Window (First Time)
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

    // Create transparent background (User request: ~30% opacity, no blur) -> Updated to 15%
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
    let waveStartX: CGFloat = 24
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

    // === STATUS LABEL ===
    let labelX = waveStartX + waveGroupWidth + 20
    let labelWidth = panelWidth - labelX - 24
    let label = NSTextField(
      frame: NSRect(x: labelX, y: (panelHeight - 20) / 2, width: labelWidth, height: 20))
    label.stringValue = initialText
    label.alignment = .left
    label.isEditable = false
    label.isBordered = false
    label.drawsBackground = false
    // User request: Text opacity 70%
    label.textColor = NSColor.white.withAlphaComponent(0.7)
    label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
    label.lineBreakMode = .byTruncatingTail
    backgroundView.addSubview(label)
    statusLabel = label

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

    guard let panel = recordingOverlayWindow else { return }
    let panelHeight = panel.frame.height

    waveTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      // Debug log every 1 second (approx 12 frames) to avoid flooding
      // if Int.random(in: 0...12) == 0 { NSLog("[Overlay] Animation Frame") }

      guard let self = self, self.isShowingRecording else { return }

      let maxHeight: CGFloat = 24
      let minHeight: CGFloat = 4
      let waveY: CGFloat = (panelHeight - 24) / 2

      // Animate each bar
      for barView in self.waveformViews {
        let randomHeight = CGFloat.random(in: minHeight...maxHeight)
        // Center the bar vertically in the wave area
        let yOffset = waveY + (24 - randomHeight) / 2

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

  private func hideRecordingOverlay() {
    NSLog("[Overlay] hideRecordingOverlay called")
    isShowingRecording = false
    waveTimer?.invalidate()
    waveTimer = nil
    recordingOverlayWindow?.orderOut(nil)
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
