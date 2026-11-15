import AppKit
import SwiftUI

// MARK: - General

struct GeneralPage: View {
    @Bindable private var store = SettingsStore.shared
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var updateNote: String?

    private var s: HushSettings { store.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow {
                    RowLabel(title: "Open Hush at login")
                } trailing: {
                    HushSwitch(isOn: Binding(get: { openAtLogin }, set: { value in
                        LoginItem.set(value)
                        openAtLogin = LoginItem.isEnabled
                    }), offFill: Color.white.opacity(0.2), label: "Open Hush at login")
                }
            }

            SettingsSection(title: "Menu bar icon") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Clicking the icon")
                    } trailing: {
                        PopupPill(selection: store.binding(\.menuBarClick),
                                  options: MenuBarClick.allCases.map { ($0, $0.title) }, label: "Clicking the icon")
                    }
                }
                NoteText(text: "A click can also open the panel or open Settings. Shift-click switches between Ambient and Deep, and right-click or Control-click opens the panel.")
            }

            SettingsSection(title: "While Hush is on") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Fade out when the front app has no windows",
                                 subtitle: "Clicking the desktop then shows it clearly.")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.hideWhenNoWindow), offFill: Color.white.opacity(0.2),
                                   label: "Fade out when the front app has no windows")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Hide")
                    } trailing: {
                        PillSegmented(selection: store.binding(\.chromeHiding),
                                      options: ChromeHiding.allCases.map { ($0, $0.title) },
                                      fontSize: 12.5, settingsStyle: true)
                    }
                }
                NoteText(text: "Hiding the Dock or menu bar uses Automation access to System Events. Hush puts them back when it turns off or quits, and after a crash the next time it opens.")
            }

            SettingsSection(title: "Updates") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Check for updates automatically")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.checkForUpdates), offFill: Color.white.opacity(0.2),
                                   label: "Check for updates automatically")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Hush \(Self.version)", subtitle: updateNote ?? "Personal build")
                    } trailing: {
                        Button("Check Now") {
                            updateNote = "No update feed is set up for personal builds."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { updateNote = nil }
                        }
                        .buttonStyle(PillButtonStyle(kind: .settings))
                    }
                }
            }
        }
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @Bindable private var store = SettingsStore.shared
    private var system = SystemState.shared
    private var overlay = OverlayController.shared
    @State private var hexDraft = ""
    @FocusState private var hexFocused: Bool

    private var s: HushSettings { store.value }
    private var dimming: Bool { overlay.effect.method == .dimmerReduceTransparency }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            modeTiles

            SettingsSection(title: "Effect") {
                SettingsGroup {
                    if system.reduceTransparency {
                        SettingsRow {
                            RowLabel(title: "Blur with Reduce Transparency on",
                                     subtitle: "Reduce Transparency is on in Accessibility settings, so Hush dims instead of blurring unless you turn this on.")
                        } trailing: {
                            HushSwitch(isOn: store.binding(\.blurWithReduceTransparency), offFill: Color.white.opacity(0.2),
                                       label: "Blur with Reduce Transparency on")
                        }
                        RowDivider()
                    }
                    SettingsRow {
                        RowLabel(title: "Blur")
                    } trailing: {
                        SliderControl(value: store.binding(\.blur), label: "Blur",
                                      format: { dimming ? "Off" : String(Int($0.rounded())) })
                    }
                    .disabled(dimming)
                    .opacity(dimming ? 0.45 : 1)
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Ambient height", subtitle: "How far up the screen the blur reaches in Ambient")
                    } trailing: {
                        SliderControl(value: Binding(get: { s.ambientCoverage * 100 },
                                                     set: { v in store.update { $0.ambientCoverage = v / 100 } }),
                                      range: 20...100, label: "Ambient height",
                                      format: { "\(Int($0.rounded()))%" })
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Grain")
                    } trailing: {
                        SliderControl(value: store.binding(\.grain), label: "Grain")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Black and white",
                                 subtitle: "Everything behind your window turns gray. Your window doesn’t.")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.monoEnabled), offFill: Color.white.opacity(0.2),
                                   label: "Black and white")
                    }
                    .disabled(dimming)
                    .opacity(dimming ? 0.45 : 1)
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Strength")
                    } trailing: {
                        SliderControl(value: store.binding(\.mono), label: "Black and white strength")
                    }
                    .disabled(!s.monoEnabled || dimming)
                    .opacity(!s.monoEnabled || dimming ? 0.45 : 1)
                }
                NoteText(text: "Set Blur to 0 for a blur-free look. Tint, grain and black and white still apply.")
            }

            SettingsSection(title: "Tint") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Tint")
                    } trailing: {
                        HStack(spacing: 10) {
                            ForEach(TintPreset.allCases) { preset in
                                TintSwatch(preset: preset, selected: s.tintPreset == preset, size: 20,
                                           ringBackground: Theme.windowBackground) {
                                    store.update { $0.tintPreset = preset }
                                }
                                .padding(-3.5)
                            }
                        }
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Custom tint")
                    } trailing: {
                        HStack(spacing: 8) {
                            TextField("", text: $hexDraft)
                                .textFieldStyle(.plain)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.text)
                                .focused($hexFocused)
                                .padding(.horizontal, 8)
                                .frame(width: 96, height: 26)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                .onSubmit(commitHex)
                                .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
                                .accessibilityLabel("Custom tint hex value")
                            ColorWell(hex: s.tintHex) { hex in
                                store.update { $0.tintHex = hex; $0.tintPreset = .custom }
                            }
                        }
                    }
                    .opacity(s.tintPreset == .custom ? 1 : 0.45)
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Strength")
                    } trailing: {
                        SliderControl(value: store.binding(\.tintOpacity), label: "Tint strength")
                    }
                    .disabled(s.tintPreset == .off)
                    .opacity(s.tintPreset == .off ? 0.45 : 1)
                }
            }

            SettingsSection(title: "Motion") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Crossfade")
                    } trailing: {
                        SliderControl(value: store.binding(\.crossfade), range: 0...1, step: 0.05, label: "Crossfade in seconds",
                                      format: { String(format: "%.1f s", $0) })
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Reveal")
                    } trailing: {
                        PillSegmented(selection: store.binding(\.revealStyle),
                                      options: [(RevealStyle.fade, "Fade"), (RevealStyle.cursor, "From the pointer")],
                                      fontSize: 12.5, settingsStyle: true)
                    }
                }
                NoteText(text: "Changes apply right away, so you can tune them with your work on screen.")
            }
        }
        .onAppear { hexDraft = "#" + s.tintHex }
        .onChange(of: s.tintHex) { _, new in if !hexFocused { hexDraft = "#" + new } }
    }

    private func commitHex() {
        let cleaned = hexDraft.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        if NSColor(hex: cleaned) != nil {
            store.update { $0.tintHex = cleaned; $0.tintPreset = .custom }
            hexDraft = "#" + cleaned
        } else {
            hexDraft = "#" + s.tintHex
            NSSound.beep()
        }
    }

    private var modeTiles: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(FocusMode.allCases) { mode in
                let selected = s.mode == mode
                Button {
                    store.update { $0.mode = mode }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ModeScene(ambient: mode == .ambient, cornerRadius: 12, windowRadius: 6,
                                  blur: dimming ? 0 : max(1.5, CGFloat(s.blur) * 0.085),
                                  saturation: !dimming && s.monoEnabled ? 1 - s.mono / 100 : 1,
                                  tint: previewTint, dim: dimming ? 0.4 : 0, detail: .large)
                            .frame(height: 138)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Theme.blue : Color.white.opacity(0.16), lineWidth: selected ? 2.5 : 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text(mode == .ambient ? "Blur rises from the bottom edge" : "Everything but your window is blurred")
                                .font(.system(size: 12)).foregroundStyle(Theme.sub)
                        }
                        .padding(.horizontal, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var previewTint: Color? {
        guard let color = s.resolvedTint, s.tintPreset != .off else { return nil }
        return Color(nsColor: color).opacity(s.tintOpacity / 100)
    }
}

/// A colour well in the design's style that opens the system colour panel.
struct ColorWell: View {
    let hex: String
    let onChange: (String) -> Void

    var body: some View {
        Button {
            ColorPanelBridge.shared.open(hex: hex, onChange: onChange)
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: NSColor(hex: hex) ?? .black))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Choose a colour")
        .accessibilityLabel("Choose a custom tint colour")
    }
}

@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((String) -> Void)?

    func open(hex: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(hex: hex) ?? .black
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color.hexString)
    }
}

// MARK: - Triggers

struct TriggersPage: View {
    @Bindable private var store = SettingsStore.shared
    private var s: HushSettings { store.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: "Shake") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Shake the pointer to turn Hush on or off")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.shakeEnabled), offFill: Color.white.opacity(0.2),
                                   label: "Shake the pointer to turn Hush on or off")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Hold Shift and shake to peek", subtitle: "Hush steps aside until you let go of Shift.")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.shakePeekEnabled), offFill: Color.white.opacity(0.2),
                                   label: "Hold Shift and shake to peek")
                    }
                    .disabled(!s.shakeEnabled)
                    .opacity(s.shakeEnabled ? 1 : 0.45)
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Sensitivity")
                    } trailing: {
                        HStack(spacing: 10) {
                            Text("Firm").font(.system(size: 11.5)).foregroundStyle(Theme.sub)
                            HushSlider(value: store.binding(\.shakeSensitivity), label: "Shake sensitivity")
                            Text("Light").font(.system(size: 11.5)).foregroundStyle(Theme.sub)
                        }
                        .frame(width: 260)
                    }
                    .disabled(!s.shakeEnabled)
                    .opacity(s.shakeEnabled ? 1 : 0.45)
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Only while holding")
                    } trailing: {
                        PopupPill(selection: store.binding(\.shakeModifiers),
                                  options: ModifierChoice.allCases.map { ($0.rawValue, $0.title(noneTitle: "No key")) },
                                  label: "Only while holding")
                    }
                    .disabled(!s.shakeEnabled)
                    .opacity(s.shakeEnabled ? 1 : 0.45)
                }
                NoteText(text: "Moving, scrolling and dragging never count as a shake.")
            }

            SettingsSection(title: "Peek") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Peek from screen corners", subtitle: "Push the pointer into a corner to see under the overlay.")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.cornerPeek), offFill: Color.white.opacity(0.2),
                                   label: "Peek from screen corners")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Hold a key to peek", subtitle: "Hold it for a moment; let go to bring Hush back.")
                    } trailing: {
                        PopupPill(selection: store.binding(\.holdToPeekModifiers),
                                  options: ModifierChoice.allCases.map { ($0.rawValue, $0.title(noneTitle: "Off")) },
                                  label: "Hold a key to peek")
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Peek while dragging files", subtitle: "Hush steps aside so you can see where to drop.")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.dragPeek), offFill: Color.white.opacity(0.2),
                                   label: "Peek while dragging files")
                    }
                }
                NoteText(text: "Corners you’ve set up as Hot Corners are skipped.")
            }

            SettingsSection(title: "Keyboard shortcuts") {
                SettingsGroup {
                    ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 { RowDivider() }
                        SettingsRow {
                            RowLabel(title: action.title)
                        } trailing: {
                            ShortcutRecorder(action: action)
                        }
                    }
                }
            }
        }
    }
}
