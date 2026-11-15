import AppKit
import SwiftUI

// MARK: - Switch (38×22, knob 18)

struct HushSwitch: View {
    @Binding var isOn: Bool
    var offFill: Color = Theme.switchOff
    var label: String = ""
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.blue : offFill)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

// MARK: - Slider (track 4, knob 16, height 22)

struct HushSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var label: String = ""
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let f = CGFloat(span > 0 ? (value - range.lowerBound) / span : 0).clamped(to: 0...1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sliderTrack).frame(height: 4)
                Capsule().fill(Theme.blue).frame(width: max(0, (w - 16) * f + 8), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1)
                    .offset(x: (w - 16) * f)
            }
            .frame(width: w, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard isEnabled else { return }
                        if !dragging { dragging = true; onEditingChanged(true) }
                        set(fraction: (g.location.x - 8) / max(1, w - 16))
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 22)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(label) }
        }
    }

    private func set(fraction: CGFloat) {
        let f = Double(fraction.clamped(to: 0...1))
        var v = range.lowerBound + f * (range.upperBound - range.lowerBound)
        if step > 0 { v = (v / step).rounded() * step }
        v = min(max(v, range.lowerBound), range.upperBound)
        if abs(v - value) > 1e-9 { value = v }
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

// MARK: - Pill segmented control

struct PillSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]
    var fontSize: CGFloat = 12
    var equalWidths = false
    /// Settings style: selected segment gets a soft shadow, unselected text is slightly dimmer.
    var settingsStyle = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: fontSize))
                        .foregroundStyle(selected || !settingsStyle ? Color.white : Color.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, equalWidths ? 4 : 12)
                        .frame(maxWidth: equalWidths ? .infinity : nil)
                        .frame(height: 24)
                        .background(
                            Capsule()
                                .fill(selected ? Theme.segmentSelected : .clear)
                                .shadow(color: .black.opacity(selected && settingsStyle ? 0.25 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.segmentTrack))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// MARK: - Tint swatch

struct TintSwatch: View {
    let preset: TintPreset
    let selected: Bool
    var size: CGFloat = 18
    /// The colour of the 2 pt gap between the swatch and its white selection ring.
    var ringBackground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    Circle().fill(.white).frame(width: size + 7, height: size + 7)
                    Circle().fill(ringBackground).frame(width: size + 4, height: size + 4)
                }
                preset.swatchFill(size: size)
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0 : 0.4), lineWidth: 0.5))
            }
            .frame(width: size + 7, height: size + 7)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(preset.title)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case settings, onboarding, primary, small, panel, panelChip }
    var kind: Kind = .settings
    var fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: kind == .primary ? .medium : .regular))
            .foregroundStyle(kind == .primary || kind == .panel || kind == .panelChip ? Color.white : Theme.strongText)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(Capsule().fill(fill ?? defaultFill))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var fontSize: CGFloat {
        switch kind {
        case .small, .panelChip: return 12
        case .panel: return 12.5
        default: return 13
        }
    }
    private var height: CGFloat {
        switch kind {
        case .onboarding, .primary: return 30
        case .small: return 24
        case .panelChip: return 26
        default: return 28
        }
    }
    private var horizontalPadding: CGFloat {
        switch kind {
        case .onboarding, .primary: return 16
        case .small: return 10
        case .panelChip: return 11
        case .panel: return 12
        case .settings: return 14
        }
    }
    private var defaultFill: Color {
        switch kind {
        case .primary: return Theme.buttonBlue
        case .panel: return Color.white.opacity(0.1)
        default: return Theme.buttonFill
        }
    }
}

/// Round icon button (power, copy, trash…).
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 24
    var iconSize: CGFloat = 13
    var fill: Color = .clear
    var hoverFill: Color = Color.white.opacity(0.08)
    var color: Color = Color.white.opacity(0.75)
    var circle = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: circle ? size / 2 : 6, style: .continuous)
                        .fill(hovering && fill == .clear ? hoverFill : fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Pop-up pill (opens a native menu)

struct PopupPill<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]
    var label: String = ""
    @State private var anchor = MenuAnchor()

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Button {
            showMenu()
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle).font(.system(size: 13)).foregroundStyle(Theme.text)
                UpDownChevrons().stroke(Theme.text, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 9, height: 12)
            }
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(
                Capsule().fill(Color.white.opacity(0.1))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .accessibilityLabel("\(label): \(currentTitle)")
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        let handler = MenuHandler { index in selection = options[index].value }
        var selectedItem: NSMenuItem?
        for (i, option) in options.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.tag = i
            item.state = option.value == selection ? .on : .off
            if option.value == selection { selectedItem = item }
            menu.addItem(item)
        }
        menu.appearance = NSAppearance(named: .darkAqua)
        withExtendedLifetime(handler) {
            _ = menu.popUp(positioning: selectedItem, at: NSPoint(x: 4, y: view.bounds.height - 3), in: view)
        }
    }
}

struct UpDownChevrons: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 9, sy = r.height / 12
        var p = Path()
        p.move(to: CGPoint(x: 1.5 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 4.5 * sx, y: 1.5 * sy))
        p.addLine(to: CGPoint(x: 7.5 * sx, y: 4.5 * sy))
        p.move(to: CGPoint(x: 1.5 * sx, y: 7.5 * sy))
        p.addLine(to: CGPoint(x: 4.5 * sx, y: 10.5 * sy))
        p.addLine(to: CGPoint(x: 7.5 * sx, y: 7.5 * sy))
        return p
    }
}

/// Gives SwiftUI buttons an NSView to anchor native menus to.
final class MenuAnchor {
    weak var view: NSView?
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        anchor.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

final class MenuHandler: NSObject {
    private let action: (Int) -> Void
    init(_ action: @escaping (Int) -> Void) { self.action = action }
    @objc func pick(_ item: NSMenuItem) { action(item.tag) }
}

// MARK: - Settings layout pieces

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.groupFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupStroke, lineWidth: 1))
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.rowDivider).frame(height: 1) }
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    var minHeight: CGFloat = 44
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: minHeight)
    }
}

struct RowLabel: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.strongText)
            .padding(.horizontal, 2)
    }
}

struct NoteText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.sub)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionHeader(title: title) }
            content
        }
    }
}

/// Slider + value label at the fixed width used in Settings rows.
struct SliderControl: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var width: CGFloat = 250
    var label: String
    var format: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        HStack(spacing: 10) {
            HushSlider(value: $value, range: range, step: step, label: label)
            Text(format(value))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(width: width)
    }
}
