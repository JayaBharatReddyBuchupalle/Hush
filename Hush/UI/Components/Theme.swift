import AppKit
import SwiftUI

/// Values taken from the design files (Hush — macOS Focus Overlay).
enum Theme {
    static let blue = Color(hex: 0x0A84FF)            // switches, sliders, selection rings
    static let buttonBlue = Color(hex: 0x0B5FD3)      // primary buttons, selected sidebar row
    static let link = Color(hex: 0x4AA3FF)
    static let orange = Color(hex: 0xFF9F0A)
    static let green = Color(hex: 0x32D74B)
    static let windowBackground = Color(hex: 0x1E1E21)
    static let nsWindowBackground = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x21 / 255, alpha: 1)

    static let text = Color.white.opacity(0.88)
    static let strongText = Color.white.opacity(0.92)
    static let panelSecondary = Color.white.opacity(0.66)
    static let sub = Color.white.opacity(0.6)
    static let groupFill = Color.white.opacity(0.045)
    static let groupStroke = Color.white.opacity(0.06)
    static let rowDivider = Color.white.opacity(0.07)
    static let segmentTrack = Color.white.opacity(0.08)
    static let segmentSelected = Color.white.opacity(0.22)
    static let buttonFill = Color.white.opacity(0.12)
    static let switchOff = Color.white.opacity(0.22)
    static let sliderTrack = Color.white.opacity(0.16)

    static let mono = Font.system(size: 12, design: .monospaced)

    /// The wallpaper gradient used by every illustration.
    static let sceneGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x13203A), location: 0),
            .init(color: Color(hex: 0x25335A), location: 0.48),
            .init(color: Color(hex: 0x6A5268), location: 0.66),
            .init(color: Color(hex: 0x3A3756), location: 0.78),
            .init(color: Color(hex: 0x171D31), location: 1),
        ],
        startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension TintPreset {
    /// Swatch fill as drawn in the design.
    @ViewBuilder
    func swatchFill(size: CGFloat) -> some View {
        switch self {
        case .off:
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: size * 0.2, height: size * 1.6)
                    .rotationEffect(.degrees(45))
            }
            .clipShape(Circle())
        case .accent:
            ZStack {
                Circle().fill(Color(nsColor: .controlAccentColor))
                Circle().fill(.white).frame(width: size * 0.28, height: size * 0.28)
            }
        case .custom:
            Circle().fill(AngularGradient(
                colors: [0xFF453A, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x0A84FF, 0xBF5AF2, 0xFF375F, 0xFF453A].map { Color(hex: $0) },
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
        default:
            Circle().fill(Color(nsColor: NSColor(hex: fixedHex ?? "000000") ?? .black))
        }
    }
}
