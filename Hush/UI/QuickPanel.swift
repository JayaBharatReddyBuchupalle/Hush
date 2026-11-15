import AppKit
import SwiftUI

/// The menu bar panel. Layout, sizes and copy follow the design: 320 wide, 14/14/12 padding, 12 pt gaps.
struct QuickPanel: View {
    @Bindable var store: SettingsStore
    var overlay: OverlayController
    var system: SystemState
    var openSettings: (SettingsPage?) -> Void
    var quit: () -> Void

    private var s: HushSettings { store.value }
    private var dimming: Bool { overlay.effect.method == .dimmerReduceTransparency }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if overlay.canTurnOn {
                controls
            } else {
                accessCard
            }
            footer
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            HushIconView(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hush").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            HushSwitch(isOn: Binding(get: { overlay.isOn },
                                     set: { $0 ? overlay.turnOn() : overlay.turnOff() }),
                       label: "Hush")
                .disabled(!overlay.canTurnOn)
                .opacity(overlay.canTurnOn ? 1 : 0.4)
        }
    }

    private var statusText: String {
        if !overlay.canTurnOn { return "Needs Accessibility access" }
        if !overlay.isOn { return offHint }
        if overlay.isFrontAppIgnored { return "Paused for \(overlay.frontApp?.name ?? "this app")" }
        if overlay.peekReasons.contains(.shiftShake) { return "Peeking while Shift is held" }
        if overlay.isPeeking { return "Peeking under the overlay" }
        if dimming { return "On, dimming instead of blurring" }
        if overlay.isDesktopRevealed { return "On, showing the desktop" }
        return "On in \(s.mode.title) mode"
    }

    private var offHint: String {
        let shortcut = s.shortcut(.toggleOverlay)?.displayString
        switch (s.shakeEnabled, shortcut) {
        case (true, let key?): return "Shake or press \(key) to turn on"
        case (true, nil): return "Shake the pointer to turn on"
        case (false, let key?): return "Press \(key) to turn on"
        case (false, nil): return "Off"
        }
    }

    // MARK: Needs access

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.orange.opacity(0.18))
                        HushGlyph(kind: .alert, width: 18).foregroundStyle(Theme.orange)
                    }
                    .frame(width: 34, height: 34)
                    Text("Allow Accessibility access").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
                Text("Hush uses it to see which window is in front, so it knows what to keep sharp. It never records your screen.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AX.requestTrust()
                    AX.openAccessibilitySettings()
                } label: {
                    Text("Open Accessibility Settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.buttonBlue))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
            Text("Hush turns on by itself as soon as access is allowed.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.panelSecondary)
                .padding(.horizontal, 2)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dimming { reduceTransparencyNote }
            if overlay.frontApp != nil { frontAppCard }
            divider
            modeTiles
            VStack(alignment: .leading, spacing: 10) {
                labeledSlider("Blur", value: store.binding(\.blur), display: dimming ? "Unavailable" : "\(Int(s.blur.rounded()))")
                    .disabled(dimming)
                    .opacity(dimming ? 0.4 : 1)
                labeledSlider("Grain", value: store.binding(\.grain), display: "\(Int(s.grain.rounded()))")
            }
            monochrome
            tint
            divider
            HStack(spacing: 10) {
                Text("Keep sharp")
                Spacer(minLength: 0)
                PillSegmented(selection: store.binding(\.scope),
                              options: [(FocusScope.window, "Window"), (FocusScope.app, "Whole app")])
            }
            shakeRow
            VStack(alignment: .leading, spacing: 6) {
                Text("Hide while Hush is on")
                PillSegmented(selection: store.binding(\.chromeHiding),
                              options: ChromeHiding.allCases.map { ($0, $0.title) }, equalWidths: true)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private var reduceTransparencyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(rtMessage)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Theme.link)
                .environment(\.openURL, OpenURLAction { url in
                    if url.host == "display" {
                        AX.openDisplayAccessibilitySettings()
                    } else if url.host == "blur" {
                        store.update { $0.blurWithReduceTransparency = true }
                    }
                    return .handled
                })
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private var rtMessage: AttributedString {
        var text = AttributedString("Reduce Transparency is on, so Hush dims the background instead of blurring it. ")
        var display = AttributedString("Display Settings…")
        display.link = URL(string: "hush-panel://display")
        display.foregroundColor = Theme.link
        var blur = AttributedString("Blur anyway")
        blur.link = URL(string: "hush-panel://blur")
        blur.foregroundColor = Theme.link
        text.append(display)
        text.append(AttributedString("  ·  "))
        text.append(blur)
        return text
    }

    private var frontAppCard: some View {
        let paused = overlay.isFrontAppIgnored
        let app = overlay.frontApp
        return HStack(spacing: 10) {
            if let app {
                AppIconTile(bundleID: app.bundleID, size: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.name ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(frontAppCaption(paused: paused))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(paused ? "Stop Ignoring" : "Ignore") { overlay.setFrontAppExcluded(nil) }
                .buttonStyle(PillButtonStyle(kind: .panelChip,
                                             fill: paused ? Color.white.opacity(0.2) : Color.white.opacity(0.12)))
                .disabled(app?.bundleID.isEmpty ?? true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(paused ? Theme.blue.opacity(0.26) : Color.white.opacity(0.07)))
        .animation(.easeOut(duration: 0.2), value: paused)
    }

    private func frontAppCaption(paused: Bool) -> String {
        if paused { return "Ignored while it’s in front" }
        if !overlay.isOn { return "In front" }
        return s.scope == .app ? "All its windows kept sharp" : "Kept sharp"
    }

    private var modeTiles: some View {
        HStack(spacing: 10) {
            ForEach(FocusMode.allCases) { mode in
                let selected = s.mode == mode
                Button {
                    store.update { $0.mode = mode }
                } label: {
                    VStack(spacing: 6) {
                        ModeScene(ambient: mode == .ambient, cornerRadius: 10, windowRadius: 4,
                                  blur: dimming ? 0 : CGFloat(s.blur * 0.05),
                                  saturation: !dimming && s.monoEnabled ? 1 - s.mono / 100 : 1,
                                  tint: previewTint, dim: dimming ? 0.4 : 0)
                            .frame(height: 86)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? Theme.blue : Color.white.opacity(0.16),
                                              lineWidth: selected ? 2 : 1))
                        Text(mode.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(.white)
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

    private var monochrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Black and white")
                Spacer(minLength: 0)
                HushSwitch(isOn: store.binding(\.monoEnabled), label: "Black and white")
            }
            if s.monoEnabled && !dimming {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text("\(Int(s.mono.rounded()))").monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.72))
                    HushSlider(value: store.binding(\.mono), label: "Black and white strength")
                }
            }
        }
        .disabled(dimming)
        .opacity(dimming ? 0.4 : 1)
    }

    private var tint: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Tint")
                Spacer()
                Text(s.tintPreset.title).foregroundStyle(Theme.panelSecondary)
            }
            HStack(spacing: 0) {
                ForEach(Array(TintPreset.allCases.enumerated()), id: \.element) { index, preset in
                    if index > 0 { Spacer(minLength: 0) }
                    TintSwatch(preset: preset, selected: s.tintPreset == preset, size: 18,
                               ringBackground: Color(.sRGB, red: 30 / 255, green: 30 / 255, blue: 36 / 255, opacity: 0.95)) {
                        store.update { $0.tintPreset = preset }
                    }
                }
            }
            .padding(.horizontal, -1.5)
            labeledSlider("Tint strength", value: store.binding(\.tintOpacity), display: "\(Int(s.tintOpacity.rounded()))")
                .disabled(s.tintPreset == .off)
                .opacity(s.tintPreset == .off ? 0.4 : 1)
        }
    }

    private var shakeRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Shake to turn on or off")
                Text(s.shakePeekEnabled ? "Hold Shift while shaking to peek" : "A few quick side-to-side moves")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.panelSecondary)
            }
            Spacer(minLength: 0)
            IconButton(systemName: "slider.horizontal.3", size: 26, iconSize: 13, circle: true,
                       help: "Shake settings") { openSettings(.triggers) }
            HushSwitch(isOn: store.binding(\.shakeEnabled), label: "Shake to turn on or off")
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(Theme.panelSecondary)
            }
            HushSlider(value: value, label: title)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Settings…") { openSettings(nil) }
                .buttonStyle(PillButtonStyle(kind: .panel))
            IconButton(systemName: "power", size: 28, iconSize: 13, fill: Color.white.opacity(0.1),
                       color: .white, circle: true, help: "Quit Hush", action: quit)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
    }
}
