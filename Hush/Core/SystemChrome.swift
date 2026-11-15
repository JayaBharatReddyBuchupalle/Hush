import AppKit
import Foundation

/// Dock and menu bar auto-hide through System Events (the same switches as System Settings, no `killall Dock`).
/// The user's original state is saved before anything changes and restored on turn-off, on quit and at the
/// next launch, so a crash can never leave the Dock hidden.
enum SystemChrome {
    private static let queue = DispatchQueue(label: "hush.system-chrome")
    private static let savedKey = "savedChromeState"      // persisted, so it survives crashes

    /// Applies the "Hide while Hush is on" choice. Hiding nothing restores the originals.
    static func apply(hideDock: Bool, hideMenuBar: Bool) {
        guard hideDock || hideMenuBar else {
            restoreIfNeeded()
            return
        }
        queue.async {
            let defaults = UserDefaults.standard
            var saved = defaults.dictionary(forKey: savedKey) as? [String: Bool]
            if saved == nil {                                       // remember the ORIGINAL state only once
                let original = ["dock": run("get autohide of dock preferences") == "true",
                                "menuBar": run("get autohide menu bar of dock preferences") == "true"]
                defaults.set(original, forKey: savedKey)
                saved = original
            }
            let originalDock = saved?["dock"] ?? false
            let originalMenuBar = saved?["menuBar"] ?? false
            run("set autohide of dock preferences to \(hideDock ? true : originalDock)")
            run("set autohide menu bar of dock preferences to \(hideMenuBar ? true : originalMenuBar)")
        }
    }

    /// On turn-off, on quit (sync: true) and at launch (crash recovery).
    static func restoreIfNeeded(sync: Bool = false) {
        let work = {
            let defaults = UserDefaults.standard
            guard let saved = defaults.dictionary(forKey: savedKey) as? [String: Bool] else { return }
            run("set autohide of dock preferences to \(saved["dock"] ?? false)")
            run("set autohide menu bar of dock preferences to \(saved["menuBar"] ?? false)")
            defaults.removeObject(forKey: savedKey)
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// osascript off the main thread: System Events can take 100+ ms to answer.
    @discardableResult
    private static func run(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to \(command)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum AutomationStatus { case allowed, denied, notRequested, unknown }

    /// Whether Hush may send Apple Events to System Events, without prompting.
    static func automationStatus() -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let desc = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch Int(status) {
        case Int(noErr): return .allowed
        case Int(errAEEventNotPermitted): return .denied
        case Int(errAEEventWouldRequireUserConsent), Int(procNotFound): return .notRequested
        default: return .unknown
        }
    }
}
