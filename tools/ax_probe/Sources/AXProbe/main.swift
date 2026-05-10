import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var lastDumpURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ensureDumpsDirectory()
        setupStatusItem()
        ensureAXPermission()
        registerHotkey()

        NSLog("[AXProbe] ready — 按 F19 dump 当前焦点")
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "👁️"
            button.toolTip = "AX Probe — 按 F19 dump 当前焦点"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dump now (3s 倒计时)", action: #selector(dumpWithCountdown), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Reveal last dump", action: #selector(revealLastDump), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open dumps folder", action: #selector(openDumpsFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Hotkey: F19", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Re-check AX permission", action: #selector(ensureAXPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        for mi in menu.items {
            mi.target = self
        }
        item.menu = menu
        self.statusItem = item
    }

    // MARK: - 热键

    private func registerHotkey() {
        HotkeyManager.shared.onPressed = { [weak self] in
            self?.dumpNow()
        }
        let ok = HotkeyManager.shared.register()
        if !ok {
            NSLog("[AXProbe] hotkey 注册失败")
            updateStatusTitle("⚠️")
        }
    }

    // MARK: - Dump

    @objc private func dumpWithCountdown() {
        let countdown = 3
        for i in (1...countdown).reversed() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(countdown - i)) { [weak self] in
                self?.updateStatusTitle("\(i)…")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(countdown)) { [weak self] in
            self?.dumpNow()
        }
    }

    @objc private func dumpNow() {
        updateStatusTitle("📸")

        let info = AXDumper.dumpFocusedContext()
        let json: Data
        do {
            json = try JSONSerialization.data(
                withJSONObject: info,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            NSLog("[AXProbe] JSON 序列化失败: \(error)")
            updateStatusTitle("❌")
            return
        }

        let url = nextDumpURL(for: info)
        do {
            try json.write(to: url, options: .atomic)
            lastDumpURL = url
            NSLog("[AXProbe] dumped → \(url.path)")
            flashStatusTitle("✅", duration: 1.0, restore: "👁️")
        } catch {
            NSLog("[AXProbe] 写入失败: \(error)")
            updateStatusTitle("❌")
        }
    }

    @objc private func revealLastDump() {
        guard let url = lastDumpURL else {
            openDumpsFolder()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openDumpsFolder() {
        NSWorkspace.shared.open(dumpsDirectory())
    }

    @objc private func ensureAXPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        NSLog("[AXProbe] AX trusted = \(trusted)")
        if !trusted {
            updateStatusTitle("🔒")
        }
    }

    // MARK: - 文件系统

    private func dumpsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AXProbe/dumps", isDirectory: true)
    }

    private func ensureDumpsDirectory() {
        let dir = dumpsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func nextDumpURL(for info: [String: Any]) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let ts = formatter.string(from: Date())

        let bundleID: String = {
            if let app = info["app"] as? [String: Any], let id = app["bundleID"] as? String, !id.isEmpty {
                return id.replacingOccurrences(of: ".", with: "_")
            }
            return "unknown"
        }()

        return dumpsDirectory().appendingPathComponent("\(ts)_\(bundleID).json")
    }

    // MARK: - 状态栏标题动效

    private func updateStatusTitle(_ s: String) {
        statusItem?.button?.title = s
    }

    private func flashStatusTitle(_ s: String, duration: TimeInterval, restore: String) {
        updateStatusTitle(s)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateStatusTitle(restore)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
