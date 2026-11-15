import AppIntents
import AppKit
import ServiceManagement

/// hush:// links cover Shell, AppleScript, Shortcuts ("Open URLs") and Raycast in one go.
///
///   hush://overlay/on|off|toggle      hush://mode/ambient|deep|toggle     hush://app/exclude|include|toggle
///   hush://mono/on|off|toggle         hush://appwide/on|off|toggle        hush://display/per-screen|global
///   hush://set?blur=70&grain=20&mono=50&tintOpacity=30                  hush://set?tint=4A90E2
///   hush://set?tintPreset=accent      hush://panel    hush://settings    hush://quit
@MainActor
enum URLRouter {
    static var showPanel: (() -> Void)?
    static var showSettings: ((SettingsPage?) -> Void)?

    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "hush" else { return }
        let overlay = OverlayController.shared
        let store = SettingsStore.shared
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        let noun = parts.first ?? ""
        let verb = parts.count > 1 ? parts[1] : "toggle"
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                                   .map { ($0.name.lowercased(), $0.value ?? "") },
                               uniquingKeysWith: { _, last in last })
        func percent(_ key: String) -> Double? { query[key].flatMap { Double($0) }.map { min(max($0, 0), 100) } }
        func onOff(_ current: Bool) -> Bool { verb == "on" ? true : verb == "off" ? false : !current }

        DebugLog.shared.log("url: \(url.absoluteString)")
        switch noun {
        case "overlay":
            if onOff(overlay.isOn) { overlay.turnOn() } else { overlay.turnOff() }
        case "mode":
            store.update { s in
                switch verb {
                case "ambient": s.mode = .ambient
                case "deep": s.mode = .deep
                default: s.mode.toggle()
                }
            }
        case "app":
            overlay.setFrontAppExcluded(verb == "exclude" ? true : verb == "include" ? false : nil)
        case "mono":
            store.update { $0.monoEnabled = onOff($0.monoEnabled) }
        case "appwide":
            store.update { $0.scope = onOff($0.scope == .app) ? .app : .window }
        case "display":
            store.update { $0.displayMode = (verb == "global") ? .global : .perScreen }
        case "set":
            store.update { s in
                if let v = percent("blur") { s.blur = v }
                if let v = percent("grain") { s.grain = v }
                if let v = percent("mono") { s.mono = v; s.monoEnabled = v > 0 }
                if let v = percent("tintopacity") { s.tintOpacity = v }
                if let v = query["crossfade"].flatMap(Double.init) { s.crossfade = min(max(v, 0), 1) }
                if let v = percent("ambientheight") { s.ambientCoverage = max(0.2, v / 100) }
                if let raw = query["tint"] {
                    if let preset = TintPreset(rawValue: raw.lowercased()) {
                        s.tintPreset = preset
                    } else if NSColor(hex: raw) != nil {
                        s.tintHex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
                        s.tintPreset = .custom
                    }
                }
                if let preset = query["tintpreset"].flatMap({ TintPreset(rawValue: $0.lowercased()) }) {
                    s.tintPreset = preset
                }
            }
        case "panel":
            showPanel?()
        case "settings":
            showSettings?(SettingsPage(rawValue: verb))
        case "quit":
            NSApp.terminate(nil)
        #if DEBUG
        case "debug":
            if verb == "layers" { DebugLog.shared.log("layer tree\n" + overlay.layerTreeDump()) }
            if verb == "reapply" { overlay.debugReapplyEffect() }
            if verb == "shake" {
                AppMain.delegate.debugSimulateShake(reversals: Int(query["reversals"] ?? "") ?? 6,
                                                    shift: query["shift"] == "1",
                                                    gestures: Int(query["gestures"] ?? "") ?? 1,
                                                    gap: Double(query["gap"] ?? "") ?? 0.6)
            }
            if verb == "windows" {
                DebugLog.shared.log((["stack, level 0, front to back"]
                    + WindowList.describe(WindowList.snapshot(), includeOwn: true)).joined(separator: "\n"))
            }
        #endif
        default:
            NSSound.beep()
        }
    }
}

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DebugLog.shared.log("login item update failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcuts actions

struct ToggleHushIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Hush"
    static let description = IntentDescription("Turns Hush on or off.")

    @MainActor
    func perform() async throws -> some IntentResult {
        OverlayController.shared.toggle()
        return .result()
    }
}

struct SetHushBlurIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Hush Blur"
    static let description = IntentDescription("Sets how strongly Hush blurs the background, from 0 to 100.")

    @Parameter(title: "Blur", inclusiveRange: (0, 100))
    var amount: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        SettingsStore.shared.update { $0.blur = Double(max(0, min(amount, 100))) }
        return .result()
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleHushIntent(), phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle Hush", systemImageName: "rectangle.inset.filled")
    }
}
