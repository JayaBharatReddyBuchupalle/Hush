import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no extra permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    var onAction: ((ShortcutAction) -> Void)?

    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var combos: [ShortcutAction: KeyCombo] = [:]
    private var suspended = false
    private static let signature: OSType = 0x4855_5348   // 'HUSH'

    func update(_ newCombos: [ShortcutAction: KeyCombo]) {
        guard newCombos != combos || refs.isEmpty else { return }
        combos = newCombos
        if !suspended { registerAll() }
    }

    /// While a shortcut is being recorded, existing ones must not fire.
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        registerAll()
    }

    fileprivate func fire(_ index: UInt32) {
        guard Int(index) < ShortcutAction.allCases.count else { return }
        onAction?(ShortcutAction.allCases[Int(index)])
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let index = hotKeyID.id
            MainActor.assumeIsolated { HotKeys.shared.fire(index) }   // delivered on the main thread
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func registerAll() {
        unregisterAll()
        installHandler()
        for (i, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = combos[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i))
            let status = RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(combo.modifierFlags), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[action] = ref
            } else {
                DebugLog.shared.log("shortcut \(combo.displayString) for “\(action.title)” is taken (\(status))")
            }
        }
    }

    private func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
}

extension KeyCombo {
    /// "⌃⌥⌘F"
    var displayString: String {
        var s = ""
        let f = modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// "Control-Option-Command-F", for sentences.
    var spokenString: String {
        var parts: [String] = []
        let f = modifierFlags
        if f.contains(.control) { parts.append("Control") }
        if f.contains(.option) { parts.append("Option") }
        if f.contains(.shift) { parts.append("Shift") }
        if f.contains(.command) { parts.append("Command") }
        parts.append(Self.keyName(keyCode))
        return parts.joined(separator: "-")
    }

    static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
            kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
            kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
            kVK_F20: "F20", kVK_ANSI_KeypadEnter: "⌤",
        ]
        if let name = special[Int(code)] { return name }
        return character(for: code) ?? "Key \(code)"
    }

    static func isFunctionKey(_ code: UInt16) -> Bool {
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
         kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].contains(Int(code))
    }

    /// The character a key produces on the current keyboard layout, uppercased.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s.uppercased()
    }
}
