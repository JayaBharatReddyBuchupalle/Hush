import AppKit
import ApplicationServices

struct WinInfo: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let layer: Int
    let cgFrame: CGRect                          // CoreGraphics global coordinates (top-left origin)
    let isOwn: Bool                              // one of Hush's windows (overlays, panel, Settings)
    var frame: CGRect { Geometry.toAppKit(cgFrame) }
}

enum Geometry {
    /// Height of the primary display, NSScreen.screens[0], whose frame origin is (0, 0).
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// CoreGraphics (top-left origin, y down) → AppKit (bottom-left origin, y up).
    static func toAppKit(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The screen showing the largest part of a rect (AppKit coordinates).
    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) }
    }

    static func area(_ r: CGRect) -> CGFloat { (r.isNull || r.isEmpty) ? 0 : r.width * r.height }

    /// 1-based display number, as people count them.
    static func displayNumber(_ id: CGDirectDisplayID) -> Int {
        (NSScreen.screens.firstIndex { displayID(of: $0) == id } ?? 0) + 1
    }
}

enum WindowList {
    /// Front-to-back list of on-screen windows. Hush's own windows are included but flagged, because the
    /// overlay pairs need to see where they sit in the stack.
    static func snapshot() -> [WinInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { d -> WinInfo? in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = d[kCGWindowLayer as String] as? Int,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }
            return WinInfo(id: id, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "",
                           layer: layer, cgFrame: rect, isOwn: pid == me)
        }
    }

    /// Normal app windows that can be a focus target.
    static func isCandidate(_ w: WinInfo) -> Bool {
        !w.isOwn && w.layer == 0 && w.cgFrame.width >= 80 && w.cgFrame.height >= 60
    }

    /// For Settings › Debug.
    static func describe(_ snap: [WinInfo], includeOwn: Bool = false) -> [String] {
        snap.filter { $0.layer == 0 && (includeOwn || !$0.isOwn) }.map { w in
            let owner = w.isOwn ? "Hush overlay" : (w.owner.isEmpty ? "pid \(w.pid)" : w.owner)
            let pos = "\(Int(w.cgFrame.minX)), \(Int(w.cgFrame.minY))"
            let size = "\(Int(w.cgFrame.width)) × \(Int(w.cgFrame.height))"
            return String(w.id).padding(toLength: 6, withPad: " ", startingAt: 0)
                + owner.prefix(16).padding(toLength: 18, withPad: " ", startingAt: 0)
                + pos.padding(toLength: 12, withPad: " ", startingAt: 0) + size
        }
    }
}

// ⚠️ Private but long-lived and widely used (AltTab, yabai): AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Adds Hush to the Accessibility list (switched off) and shows the system prompt.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let urls = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openDisplayAccessibilitySettings() {
        let urls = ["x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display",
                    "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// CGWindowID of the app's focused window, when Accessibility can tell us.
    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)          // a hung app must never stall Hush
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var id: CGWindowID = 0
        // swiftlint:disable:next force_cast
        return _AXUIElementGetWindow(value as! AXUIElement, &id) == .success && id != 0 ? id : nil
    }
}

enum StageManager {
    static var isEnabled: Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool) ?? false
    }
}
