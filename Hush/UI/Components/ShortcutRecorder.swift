import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to record, type a combination with at least one of ⌘ ⌥ ⌃ (or a function key), Esc to cancel.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    @Bindable private var store = SettingsStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    private var combo: KeyCombo? { store.value.shortcut(action) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .font(.system(size: 13))
                    .tracking(recording || combo == nil ? 0 : 1.04)
                    .foregroundStyle(recording ? Theme.link : (combo == nil ? Theme.sub : .white))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 96)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recording ? Theme.blue : Color.white.opacity(0.12), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(combo.map { "Shortcut \($0.spokenString). Click to record a new one." } ?? "Record a shortcut")

            Button {
                stopRecording()
                store.update { $0.shortcuts[action.rawValue] = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .accessibilityLabel("Clear shortcut")
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if recording { return "Type shortcut" }
        return combo?.displayString ?? "Record"
    }

    private func startRecording() {
        stopRecording()
        recording = true
        HotKeys.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeys.shared.resume()
        }
    }

    /// Returns true when the key event was used for recording (and must not reach the window).
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if event.keyCode == UInt16(kVK_Escape) && mods.isEmpty {
            stopRecording()
            return true
        }
        if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) && mods.isEmpty {
            stopRecording()
            store.update { $0.shortcuts[action.rawValue] = nil }
            return true
        }
        let hasCommandLike = !mods.intersection([.command, .option, .control]).isEmpty
        guard hasCommandLike || KeyCombo.isFunctionKey(event.keyCode) else {
            NSSound.beep()
            return true
        }
        let newCombo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
        store.update { s in
            for (key, value) in s.shortcuts where value == newCombo && key != action.rawValue {
                s.shortcuts[key] = nil          // one combination, one action
            }
            s.shortcuts[action.rawValue] = newCombo
        }
        stopRecording()
        return true
    }
}
