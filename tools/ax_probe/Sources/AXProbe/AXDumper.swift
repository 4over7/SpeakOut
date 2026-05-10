import Cocoa
import ApplicationServices

enum AXDumper {

    static func dumpFocusedContext() -> [String: Any] {
        var result: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        let trusted = AXIsProcessTrusted()
        result["axTrusted"] = trusted
        if !trusted {
            result["error"] = "AX 权限未授予 — 系统设置 → 隐私与安全性 → 辅助功能"
            return result
        }

        if let appInfo = frontmostApp() {
            result["app"] = appInfo
        }

        let systemWide = AXUIElementCreateSystemWide()

        if let focusedApp: AXUIElement = copy(systemWide, kAXFocusedApplicationAttribute) {
            result["focusedAppFromAX"] = describeElement(focusedApp, depth: 0, includeChildren: false)

            if let focusedWindow: AXUIElement = copy(focusedApp, kAXFocusedWindowAttribute) {
                result["focusedWindow"] = describeElement(focusedWindow, depth: 0, includeChildren: false)
                result["browserHints"] = browserHints(window: focusedWindow)
            }
        }

        if let focusedElement: AXUIElement = copy(systemWide, kAXFocusedUIElementAttribute) {
            result["focusedElement"] = describeElement(focusedElement, depth: 0, includeChildren: true)
            result["selection"] = readSelection(focusedElement)
            result["surrounding"] = readSurrounding(focusedElement)
            result["parentChain"] = parentChain(focusedElement, maxDepth: 6)
        } else {
            result["focusedElement"] = NSNull()
        }

        return result
    }

    private static func frontmostApp() -> [String: Any]? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return [
            "bundleID": app.bundleIdentifier ?? "",
            "name": app.localizedName ?? "",
            "pid": app.processIdentifier,
            "executablePath": app.executableURL?.path ?? "",
        ]
    }

    private static func describeElement(_ element: AXUIElement, depth: Int, includeChildren: Bool) -> [String: Any] {
        var info: [String: Any] = [:]

        let attrs: [(String, String)] = [
            ("role", kAXRoleAttribute as String),
            ("subrole", kAXSubroleAttribute as String),
            ("roleDescription", kAXRoleDescriptionAttribute as String),
            ("identifier", kAXIdentifierAttribute as String),
            ("title", kAXTitleAttribute as String),
            ("description", kAXDescriptionAttribute as String),
            ("help", kAXHelpAttribute as String),
            ("placeholder", kAXPlaceholderValueAttribute as String),
            ("value", kAXValueAttribute as String),
            ("valueDescription", kAXValueDescriptionAttribute as String),
        ]

        for (key, attr) in attrs {
            if let v = readString(element, attr) {
                info[key] = truncate(v, max: 500)
            }
        }

        if let nChars = readNumber(element, kAXNumberOfCharactersAttribute as String) {
            info["numberOfCharacters"] = nChars
        }

        if let names = copyAttrNames(element) {
            info["allAttrs"] = names
        }
        if let actions = copyActionNames(element) {
            info["actions"] = actions
        }

        if includeChildren {
            if let kids: [AXUIElement] = copyArray(element, kAXChildrenAttribute) {
                info["childCount"] = kids.count
                info["childRoles"] = kids.prefix(10).map { readString($0, kAXRoleAttribute as String) ?? "?" }
            }
        }

        return info
    }

    private static func readSelection(_ element: AXUIElement) -> [String: Any] {
        var sel: [String: Any] = [:]
        if let text = readString(element, kAXSelectedTextAttribute as String) {
            sel["selectedText"] = truncate(text, max: 1000)
            sel["selectedLength"] = text.count
        }
        if let range = readRange(element, kAXSelectedTextRangeAttribute as String) {
            sel["selectedRange"] = ["location": range.location, "length": range.length]
        }
        if let visible = readRange(element, kAXVisibleCharacterRangeAttribute as String) {
            sel["visibleRange"] = ["location": visible.location, "length": visible.length]
        }
        return sel
    }

    private static func readSurrounding(_ element: AXUIElement) -> [String: Any] {
        var info: [String: Any] = [:]

        guard let fullValue = readString(element, kAXValueAttribute as String) else {
            info["available"] = false
            return info
        }

        info["available"] = true
        info["fullLength"] = fullValue.count

        let cursorLoc: Int
        if let r = readRange(element, kAXSelectedTextRangeAttribute as String) {
            cursorLoc = r.location
        } else {
            cursorLoc = fullValue.count
        }

        let context = 200
        let startIdx = max(0, cursorLoc - context)
        let endIdx = min(fullValue.count, cursorLoc + context)

        let chars = Array(fullValue)
        if startIdx < endIdx && endIdx <= chars.count {
            let before = String(chars[startIdx..<min(cursorLoc, chars.count)])
            let after = String(chars[max(cursorLoc, 0)..<endIdx])
            info["before"] = before
            info["after"] = after
            info["beforeLen"] = before.count
            info["afterLen"] = after.count
        }
        return info
    }

    private static func parentChain(_ element: AXUIElement, maxDepth: Int) -> [[String: Any]] {
        var chain: [[String: Any]] = []
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < maxDepth {
            let info: [String: Any] = [
                "depth": depth,
                "role": readString(el, kAXRoleAttribute as String) ?? "?",
                "subrole": readString(el, kAXSubroleAttribute as String) ?? "",
                "identifier": readString(el, kAXIdentifierAttribute as String) ?? "",
                "title": truncate(readString(el, kAXTitleAttribute as String) ?? "", max: 80),
            ]
            chain.append(info)
            if let parent: AXUIElement = copy(el, kAXParentAttribute) {
                current = parent
            } else {
                break
            }
            depth += 1
        }
        return chain
    }

    private static func browserHints(window: AXUIElement) -> [String: Any] {
        var hints: [String: Any] = [:]
        if let url = readString(window, "AXURL") {
            hints["windowAXURL"] = url
        }
        if let doc = readString(window, "AXDocument") {
            hints["windowAXDocument"] = doc
        }
        if let title = readString(window, kAXTitleAttribute as String) {
            hints["windowTitle"] = title
        }
        return hints
    }

    // MARK: - 低层封装

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        if T.self == AXUIElement.self {
            if CFGetTypeID(v) == AXUIElementGetTypeID() {
                return (v as! AXUIElement) as? T
            }
            return nil
        }
        return v as? T
    }

    private static func readString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if let url = v as? URL { return url.absoluteString }
        return nil
    }

    private static func readNumber(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let n = value as? NSNumber else { return nil }
        return n.intValue
    }

    private static func readRange(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        let axVal = v as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axVal, .cfRange, &range) else { return nil }
        return range
    }

    private static func copyArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return nil }
        return arr
    }

    private static func copyAttrNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success, let arr = names as? [String] else {
            return nil
        }
        return arr
    }

    private static func copyActionNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let arr = names as? [String] else {
            return nil
        }
        return arr
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "…[+\(s.count - max)]"
    }
}
