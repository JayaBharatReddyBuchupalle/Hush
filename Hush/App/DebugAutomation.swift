#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only. With HUSH_SNAPSHOT_DIR set, Hush opens its panel, each Settings page and both onboarding
/// steps, saves a PNG of each window into that folder, restores the settings it touched, and quits.
/// Used to compare the UI with the design files.
@MainActor
enum DebugAutomation {
    static func runIfRequested() {
        applySettingsOverride()
        guard let dir = ProcessInfo.processInfo.environment["HUSH_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            await run(dir: dir)
            NSApp.terminate(nil)
        }
    }

    /// HUSH_DEBUG_SETTINGS='{"mode":"ambient","blurWithReduceTransparency":true}' merges keys into the settings.
    private static func applySettingsOverride() {
        guard let json = ProcessInfo.processInfo.environment["HUSH_DEBUG_SETTINGS"],
              let patch = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let current = try? JSONEncoder().encode(SettingsStore.shared.value),
              var dict = try? JSONSerialization.jsonObject(with: current) as? [String: Any] else { return }
        dict.merge(patch) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: dict),
              let settings = try? JSONDecoder().decode(HushSettings.self, from: merged) else { return }
        SettingsStore.shared.update { $0 = settings }
        DebugLog.shared.log("debug settings override: \(json)")
    }

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        return dlsym(handle, "CGWindowListCreateImage").map { unsafeBitCast($0, to: CreateImage.self) }
    }()

    private static func run(dir: String) async {
        let store = SettingsStore.shared
        let original = store.value
        let delegate = AppMain.delegate
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["HUSH_SNAPSHOT_ONLY"]
        func wanted(_ name: String) -> Bool {
            only.map { $0.split(separator: ",").contains { name.hasPrefix(String($0)) } } ?? true
        }

        OnboardingWindowController.shared.close()
        await pause(0.3)

        // Panel states
        if wanted("panel") {
            delegate.debugShowPanel()
            await pause(0.9)
            capture(delegate.debugPanelWindow, name: "panel", dir: dir, withBackground: true)
            store.update { $0.monoEnabled = true; $0.tintPreset = .blue }
            await pause(0.5)
            capture(delegate.debugPanelWindow, name: "panel-mono-tint", dir: dir, withBackground: true)
            store.update { $0 = original }
            if OverlayController.shared.canTurnOn {
                OverlayController.shared.turnOn()
                await pause(0.6)
                capture(delegate.debugPanelWindow, name: "panel-on", dir: dir, withBackground: true)
                OverlayController.shared.setFrontAppExcluded(true)
                await pause(0.6)
                capture(delegate.debugPanelWindow, name: "panel-paused", dir: dir, withBackground: true)
                store.update { $0 = original }
                OverlayController.shared.turnOff(animated: false)
            }
            delegate.debugClosePanel()
            await pause(0.3)
        }

        // Settings pages
        for page in SettingsPage.allCases where wanted("settings-\(page.rawValue)") || wanted("settings") {
            SettingsWindowController.shared.show(page: page)
            if page == .debug {
                DebugLog.shared.log("snapshot run")
                DebugLog.shared.log(OverlayController.shared.windowListDump())
            }
            await pause(0.9)
            capture(NSApp.windows.first { $0.title == "Hush Settings" }, name: "settings-\(page.rawValue)", dir: dir,
                    withBackground: false)
        }
        SettingsWindowController.shared.close()

        // Onboarding
        if wanted("onboarding") {
            OnboardingWindowController.shared.show()
            await pause(0.9)
            capture(NSApp.windows.first { $0.title == "Welcome to Hush" }, name: "onboarding", dir: dir, withBackground: false)
            OnboardingWindowController.shared.close()
        }
        store.update { $0 = original }
        store.saveNow()
        await pause(0.2)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func capture(_ window: NSWindow?, name: String, dir: String, withBackground: Bool) {
        guard let window, let createImage, let screen = window.screen ?? NSScreen.main else {
            print("snapshot \(name): no window")
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = window.frame.insetBy(dx: -24, dy: -24)
        let rect = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        // 1<<2 | 1<<3: on-screen windows below this one, plus this one; 1<<3: this window only. 1<<3 image option: best resolution.
        let options: UInt32 = withBackground ? (1 << 2) | (1 << 3) : (1 << 3)
        guard let image = createImage(rect, options, UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue() else {
            print("snapshot \(name): capture failed")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot \(name): \(url.path)")
    }
}

extension AppDelegate {
    func debugShowPanel() { debugPanel.show(from: debugStatusButton) }
    func debugClosePanel() { debugPanel.close() }
    var debugPanelWindow: NSWindow? { debugPanel.window }
}
#endif
