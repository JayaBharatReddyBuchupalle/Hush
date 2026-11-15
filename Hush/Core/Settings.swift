import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// MARK: - Enums

enum FocusMode: String, Codable, CaseIterable, Identifiable {
    case ambient, deep
    var id: String { rawValue }
    var title: String { self == .ambient ? "Ambient" : "Deep" }
    mutating func toggle() { self = (self == .ambient) ? .deep : .ambient }
}

enum FocusScope: String, Codable, CaseIterable { case window, app }

enum DisplayMode: String, Codable, CaseIterable { case perScreen, global }

enum TintPreset: String, Codable, CaseIterable, Identifiable {
    case off, accent, graphite, blue, purple, pink, red, orange, yellow, green, black, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .accent: return "Accent"
        case .graphite: return "Graphite"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .black: return "Black"
        case .custom: return "Custom"
        }
    }

    /// Fixed colours from the design (the dark-mode system palette). Accent and custom resolve at runtime.
    var fixedHex: String? {
        switch self {
        case .graphite: return "8E8E93"
        case .blue: return "0A84FF"
        case .purple: return "BF5AF2"
        case .pink: return "FF375F"
        case .red: return "FF453A"
        case .orange: return "FF9F0A"
        case .yellow: return "FFD60A"
        case .green: return "30D158"
        case .black: return "000000"
        case .off, .accent, .custom: return nil
        }
    }
}

enum RevealStyle: String, Codable, CaseIterable { case fade, cursor }

enum MenuBarClick: String, Codable, CaseIterable {
    case toggle, panel, settings
    var title: String {
        switch self {
        case .toggle: return "Turns Hush on or off"
        case .panel: return "Opens the panel"
        case .settings: return "Opens Settings"
        }
    }
}

/// The "Hide while Hush is on" control is a single choice over two stored booleans.
enum ChromeHiding: String, CaseIterable, Identifiable {
    case off, dock, menuBar, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .dock: return "Dock"
        case .menuBar: return "Menu bar"
        case .both: return "Both"
        }
    }
    var hidesDock: Bool { self == .dock || self == .both }
    var hidesMenuBar: Bool { self == .menuBar || self == .both }
    init(dock: Bool, menuBar: Bool) {
        switch (dock, menuBar) {
        case (true, true): self = .both
        case (true, false): self = .dock
        case (false, true): self = .menuBar
        case (false, false): self = .off
        }
    }
}

/// Modifier choices offered by the "Only while holding" and "Hold a key to peek" pop-ups.
enum ModifierChoice: UInt, CaseIterable, Identifiable {
    case none = 0
    case control = 262_144      // NSEvent.ModifierFlags.control
    case option = 524_288       // .option
    case command = 1_048_576    // .command
    case function = 8_388_608   // .function
    var id: UInt { rawValue }
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: rawValue) }
    func title(noneTitle: String) -> String {
        switch self {
        case .none: return noneTitle
        case .control: return "Control ⌃"
        case .option: return "Option ⌥"
        case .command: return "Command ⌘"
        case .function: return "Function fn"
        }
    }
    func shortTitle(noneTitle: String) -> String {
        switch self {
        case .none: return noneTitle
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        case .function: return "fn"
        }
    }
}

struct AppGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var bundleIDs: [String]
}

// MARK: - Keyboard shortcuts

struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// Device-independent NSEvent.ModifierFlags (command, option, control, shift only).
    var modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case toggleOverlay, toggleMode, toggleExclude, showPanel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleOverlay: return "Turn Hush on or off"
        case .toggleMode: return "Switch between Ambient and Deep"
        case .toggleExclude: return "Ignore the front app"
        case .showPanel: return "Show the panel"
        }
    }

    var defaultCombo: KeyCombo {
        let mods: NSEvent.ModifierFlags = [.control, .option, .command]
        switch self {
        case .toggleOverlay: return KeyCombo(keyCode: UInt16(kVK_ANSI_F), modifiers: mods)
        case .toggleMode: return KeyCombo(keyCode: UInt16(kVK_ANSI_M), modifiers: mods)
        case .toggleExclude: return KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: mods)
        case .showPanel: return KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: mods)
        }
    }

    static var defaults: [String: KeyCombo] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.defaultCombo) })
    }
}

// MARK: - Settings model

struct HushSettings: Codable, Equatable {
    static let defaultIgnored = ["com.raycast.macos", "com.runningwithcrayons.Alfred", "com.apple.Spotlight"]

    var mode: FocusMode = .deep
    var blur: Double = 60
    var monoEnabled = false
    var mono: Double = 100
    var grain: Double = 15
    var tintPreset: TintPreset = .off
    var tintHex = "1E1E1E"
    var tintOpacity: Double = 20
    var scope: FocusScope = .window
    var appGroups: [AppGroup] = []
    var ignoredBundleIDs: [String] = HushSettings.defaultIgnored
    var displayMode: DisplayMode = .perScreen
    var crossfade: Double = 0.3
    var revealStyle: RevealStyle = .fade
    var ambientCoverage: Double = 0.6
    var hideWhenNoWindow = true
    var autoHideDock = false
    var autoHideMenuBar = false
    var shakeEnabled = true
    /// Opt-in: Shift-shake peeks (until Shift is released) instead of turning Hush on or off.
    var shakePeekEnabled = false
    var shakeSensitivity: Double = 50
    var shakeModifiers: UInt = 0
    var cornerPeek = true
    var holdToPeekModifiers: UInt = 0
    var dragPeek = true
    var menuBarClick: MenuBarClick = .toggle
    var checkForUpdates = true
    /// Reduce Transparency normally switches Hush to a plain dimmer (as macOS does for its own materials).
    /// Hush's own backdrop layer can still blur, so this lets the user opt back in.
    var blurWithReduceTransparency = false
    var logShakeReversals = false
    /// Keyed by ShortcutAction.rawValue. A missing entry means the user cleared that shortcut.
    var shortcuts: [String: KeyCombo] = ShortcutAction.defaults
    /// Saved-settings format; SettingsStore.migrate upgrades older saves. Missing in saves before version 2.
    var schemaVersion = 0
    static let currentSchema = 2

    init() {}

    var chromeHiding: ChromeHiding {
        get { ChromeHiding(dock: autoHideDock, menuBar: autoHideMenuBar) }
        set {
            autoHideDock = newValue.hidesDock
            autoHideMenuBar = newValue.hidesMenuBar
        }
    }

    func shortcut(_ action: ShortcutAction) -> KeyCombo? { shortcuts[action.rawValue] }
}

extension HushSettings {
    /// Synthesized Decodable throws on missing keys, which would reset everything whenever a field is added.
    /// Decode each key on its own and keep the default for anything missing or malformed.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ field: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { field = v }
        }
        read(.mode, &mode)
        read(.blur, &blur)
        read(.monoEnabled, &monoEnabled)
        read(.mono, &mono)
        read(.grain, &grain)
        read(.tintPreset, &tintPreset)
        read(.tintHex, &tintHex)
        read(.tintOpacity, &tintOpacity)
        read(.scope, &scope)
        read(.appGroups, &appGroups)
        read(.ignoredBundleIDs, &ignoredBundleIDs)
        read(.displayMode, &displayMode)
        read(.crossfade, &crossfade)
        read(.revealStyle, &revealStyle)
        read(.ambientCoverage, &ambientCoverage)
        read(.hideWhenNoWindow, &hideWhenNoWindow)
        read(.autoHideDock, &autoHideDock)
        read(.autoHideMenuBar, &autoHideMenuBar)
        read(.shakeEnabled, &shakeEnabled)
        read(.shakePeekEnabled, &shakePeekEnabled)
        read(.shakeSensitivity, &shakeSensitivity)
        read(.shakeModifiers, &shakeModifiers)
        read(.cornerPeek, &cornerPeek)
        read(.holdToPeekModifiers, &holdToPeekModifiers)
        read(.dragPeek, &dragPeek)
        read(.menuBarClick, &menuBarClick)
        read(.checkForUpdates, &checkForUpdates)
        read(.blurWithReduceTransparency, &blurWithReduceTransparency)
        read(.logShakeReversals, &logShakeReversals)
        read(.shortcuts, &shortcuts)
        read(.schemaVersion, &schemaVersion)
    }

    /// PIDs of running apps that share an App Group with `bundleID` (empty if it isn't grouped).
    func groupPIDs(for bundleID: String) -> Set<pid_t> {
        let ids = Set(appGroups.filter { $0.bundleIDs.contains(bundleID) }.flatMap(\.bundleIDs))
        guard !ids.isEmpty else { return [] }
        return Set(NSWorkspace.shared.runningApplications
            .filter { ids.contains($0.bundleIdentifier ?? "") }
            .map(\.processIdentifier))
    }

    /// The overlay tint colour, or nil when tint is off.
    var resolvedTint: NSColor? {
        switch tintPreset {
        case .off: return nil
        case .accent: return NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor(hex: "0A84FF")
        case .custom: return NSColor(hex: tintHex) ?? .black
        default: return tintPreset.fixedHex.flatMap { NSColor(hex: $0) }
        }
    }
}

// MARK: - Store

@MainActor @Observable
final class SettingsStore {
    static let shared = SettingsStore()
    nonisolated private static let key = "settings"

    private(set) var value: HushSettings

    @ObservationIgnored private var listeners: [(HushSettings, HushSettings) -> Void] = []
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        var loaded = data.flatMap { try? JSONDecoder().decode(HushSettings.self, from: $0) } ?? HushSettings()
        if loaded.schemaVersion < HushSettings.currentSchema {
            Self.migrate(&loaded)
            if data != nil { Self.write(loaded) }
        }
        value = loaded
    }

    /// One-time upgrades of saved settings.
    private static func migrate(_ s: inout HushSettings) {
        if s.schemaVersion < 2 {
            // Shift-shake used to peek by default, so a shake with Shift held only hid Hush until Shift was
            // released. A shake now always turns Hush on or off; peeking is opt-in in Settings › Triggers.
            s.shakePeekEnabled = false
        }
        s.schemaVersion = HushSettings.currentSchema
    }

    /// Listeners receive (old, new) after every effective change.
    func observe(_ listener: @escaping (HushSettings, HushSettings) -> Void) {
        listeners.append(listener)
    }

    func update(_ change: (inout HushSettings) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        let old = value
        value = next
        listeners.forEach { $0(old, next) }
        scheduleSave()
    }

    func binding<T>(_ keyPath: WritableKeyPath<HushSettings, T>) -> Binding<T> {
        Binding(
            get: { MainActor.assumeIsolated { self.value[keyPath: keyPath] } },
            set: { newValue in MainActor.assumeIsolated { self.update { $0[keyPath: keyPath] = newValue } } }
        )
    }

    /// Slider drags fire dozens of changes per second; write to disk once they settle.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = value
        let work = DispatchWorkItem { Self.write(snapshot) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        Self.write(value)
    }

    nonisolated private static func write(_ settings: HushSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Colour helpers

extension NSColor {
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "000000" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()),
            b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", max(0, min(r, 255)), max(0, min(g, 255)), max(0, min(b, 255)))
    }
}
