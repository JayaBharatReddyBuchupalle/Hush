import AppKit
import SwiftUI

/// The live preview inside the Ambient/Deep tiles: wallpaper, two background windows, the effect, and the
/// sharp front window. The effect follows the current settings, so the tiles double as a preview.
struct ModeScene: View {
    let ambient: Bool
    var cornerRadius: CGFloat = 10
    var windowRadius: CGFloat = 4
    var blur: CGFloat = 3
    var saturation: Double = 1
    var tint: Color? = nil
    var dim: Double = 0
    var detail: Detail = .small

    enum Detail { case small, large }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                background(w: w, h: h)
                ZStack(alignment: .topLeading) {
                    background(w: w, h: h, bleed: blur * 3)
                        .blur(radius: blur)
                        .saturation(saturation)
                    if dim > 0 { Rectangle().fill(Color.black.opacity(dim)) }
                    if let tint { Rectangle().fill(tint) }
                }
                .mask {
                    if ambient {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.08),
                                               .init(color: .clear, location: 0.66)],
                                       startPoint: .bottom, endPoint: .top)
                    } else {
                        Rectangle()
                    }
                }
                frontWindow(w: w, h: h)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func background(w: CGFloat, h: CGFloat, bleed: CGFloat = 0) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.sceneGradient)
                .frame(width: w + bleed * 2, height: h + bleed * 2)
                .offset(x: -bleed, y: -bleed)
            RoundedRectangle(cornerRadius: windowRadius, style: .continuous)
                .fill(Color(hex: 0x46557C))
                .frame(width: w * 0.38, height: h * 0.42)
                .offset(x: w * 0.09, y: h * 0.14)
            RoundedRectangle(cornerRadius: windowRadius, style: .continuous)
                .fill(Color(hex: 0x7A5A78))
                .frame(width: w * 0.33, height: h * 0.52)
                .offset(x: w * (1 - 0.07 - 0.33), y: h * 0.36)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func frontWindow(w: CGFloat, h: CGFloat) -> some View {
        let fw = w * 0.46, fh = h * 0.52
        let dot: CGFloat = detail == .small ? 3 : 5
        let line: CGFloat = detail == .small ? 2 : 3
        let gap: CGFloat = detail == .small ? 6 : 9
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: windowRadius, style: .continuous)
                .fill(Color(hex: 0x2A2A30))
                .overlay(RoundedRectangle(cornerRadius: windowRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: detail == .small ? 4 : 6, y: detail == .small ? 3 : 4)
            HStack(spacing: dot * (detail == .small ? 0.33 : 0.4)) {
                Circle().fill(Color(hex: 0xFF5F57))
                Circle().fill(Color(hex: 0xFEBC2E))
                Circle().fill(Color(hex: 0x28C840))
            }
            .frame(height: dot)
            .fixedSize()
            .offset(x: fw * (detail == .small ? 0.07 : 0.06), y: fh * (detail == .small ? 0.11 : 0.1))
            VStack(alignment: .leading, spacing: gap - line) {
                Capsule().fill(Color.white.opacity(0.5)).frame(height: line)
                Capsule().fill(Color.white.opacity(0.3)).frame(height: line)
                Capsule().fill(Color.white.opacity(0.3)).frame(height: line)
            }
            .padding(.horizontal, fw * (detail == .small ? 0.09 : 0.08))
            .frame(width: fw)
            .offset(y: fh * (detail == .small ? 0.36 : 0.34))
        }
        .frame(width: fw, height: fh)
        .offset(x: w * 0.27, y: h * 0.24)
    }
}

/// Hero image for the first onboarding step.
struct HeroScene: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Theme.sceneGradient)
                        .frame(width: w + 42, height: h + 42)
                        .offset(x: -21, y: -21)
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x46557C))
                        .frame(width: w * 0.3, height: h * 0.46).offset(x: w * 0.05, y: h * 0.12)
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x33416A))
                        .frame(width: w * 0.26, height: h * 0.4).offset(x: w * 0.08, y: h * 0.64)
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x7A5A78))
                        .frame(width: w * 0.28, height: h * 0.6).offset(x: w * (1 - 0.04 - 0.28), y: h * 0.22)
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .blur(radius: 7)

                let fw = w * 0.4, fh = h * 0.66
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: 0x2A2A30))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: 0xFF5F57))
                        Circle().fill(Color(hex: 0xFEBC2E))
                        Circle().fill(Color(hex: 0x28C840))
                    }
                    .frame(height: 7).fixedSize().offset(x: 12, y: 11)
                    VStack(alignment: .leading, spacing: 9) {
                        Capsule().fill(Color.white.opacity(0.55)).frame(height: 5)
                        Capsule().fill(Color.white.opacity(0.3)).frame(height: 5)
                        Capsule().fill(Color.white.opacity(0.3)).frame(height: 5)
                        Capsule().fill(Color.white.opacity(0.3)).frame(height: 5)
                    }
                    .padding(.leading, 12).padding(.trailing, 30)
                    .frame(width: fw)
                    .offset(y: 40)
                }
                .frame(width: fw, height: fh)
                .offset(x: w * 0.3, y: h * 0.16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// The Hush app icon, drawn live (header of the panel, onboarding, mock rows).
struct HushIconView: View {
    var size: CGFloat = 32

    var body: some View {
        let u = size / 72
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: Color(hex: 0x31426E), location: 0),
                                   .init(color: Color(hex: 0x1A2242), location: 0.58),
                                   .init(color: Color(hex: 0x3D2C48), location: 1)],
                           startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97))
            RoundedRectangle(cornerRadius: 5 * u).fill(Color(hex: 0x6A7AA6))
                .frame(width: 27 * u, height: 20 * u).blur(radius: 3 * u * 0.9)
                .offset(x: 7 * u, y: 14 * u)
            RoundedRectangle(cornerRadius: 5 * u).fill(Color(hex: 0x9B7088))
                .frame(width: 27 * u, height: 25 * u).blur(radius: 3 * u * 0.9)
                .offset(x: (72 - 5 - 27) * u, y: (72 - 9 - 25) * u)
            RoundedRectangle(cornerRadius: 6 * u, style: .continuous).fill(Color(hex: 0xF3F5FA))
                .frame(width: 34 * u, height: 27 * u)
                .shadow(color: .black.opacity(0.5), radius: 3 * u, y: 2 * u)
                .offset(x: 20 * u, y: 22 * u)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.24), lineWidth: max(0.5, size / 72)))
    }
}

/// The menu bar glyph as a SwiftUI view (18×14 design units).
struct HushGlyph: View {
    enum Kind { case on, paused, alert }
    var kind: Kind = .on
    var width: CGFloat = 18

    var body: some View {
        let s = width / 18
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3.25 * s, style: .continuous)
                .stroke(lineWidth: 1.5 * s)
                .opacity(kind == .alert ? 0.6 : 0.5)
                .frame(width: 16.5 * s, height: 12.5 * s)
                .offset(x: 0.75 * s, y: 0.75 * s)
            switch kind {
            case .on:
                RoundedRectangle(cornerRadius: 1.5 * s).frame(width: 8 * s, height: 6 * s).offset(x: 5 * s, y: 4 * s)
            case .paused:
                RoundedRectangle(cornerRadius: 1 * s).frame(width: 2 * s, height: 6.5 * s).offset(x: 6.25 * s, y: 3.75 * s)
                RoundedRectangle(cornerRadius: 1 * s).frame(width: 2 * s, height: 6.5 * s).offset(x: 9.75 * s, y: 3.75 * s)
            case .alert:
                RoundedRectangle(cornerRadius: 0.9 * s).frame(width: 1.8 * s, height: 4.8 * s).offset(x: 8.1 * s, y: 3.2 * s)
                Circle().frame(width: 2 * s, height: 2 * s).offset(x: 8 * s, y: 9.1 * s)
            }
        }
        .frame(width: 18 * s, height: 14 * s, alignment: .topLeading)
    }
}

/// Two monitors for Settings › Displays. In "global" mode the second display's window is quieted too.
struct MonitorPair: View {
    let quietSecondWindow: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            monitor(windowSharp: true)
            monitor(windowSharp: !quietSecondWindow)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.2)))
    }

    private func monitor(windowSharp: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Theme.sceneGradient)
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x46557C))
                        .frame(width: 92 * 0.4, height: 58 * 0.42).offset(x: 92 * 0.08, y: 58 * 0.14)
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x7A5A78))
                        .frame(width: 92 * 0.34, height: 58 * 0.5).offset(x: 92 * 0.6, y: 58 * 0.38)
                    if !windowSharp { miniWindow }
                }
                .frame(width: 92, height: 58, alignment: .topLeading)
                .compositingGroup()
                .scaleEffect(1.08)              // pushes the blur's soft edge outside the clip
                .blur(radius: 2.5)
                if windowSharp { miniWindow }
            }
            .frame(width: 92, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(hex: 0x3A3A42), lineWidth: 2))
            Rectangle().fill(Color(hex: 0x3A3A42)).frame(width: 12, height: 8)
            Capsule().fill(Color(hex: 0x3A3A42)).frame(width: 34, height: 3)
        }
    }

    private var miniWindow: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x2A2A30))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            HStack(spacing: 1) {
                Circle().fill(Color(hex: 0xFF5F57))
                Circle().fill(Color(hex: 0xFEBC2E))
                Circle().fill(Color(hex: 0x28C840))
            }
            .frame(height: 3).fixedSize().offset(x: 3, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Color.white.opacity(0.5)).frame(height: 2)
                Capsule().fill(Color.white.opacity(0.3)).frame(height: 2)
                Capsule().fill(Color.white.opacity(0.3)).frame(height: 2)
            }
            .padding(.horizontal, 4)
            .frame(width: 92 * 0.48)
            .offset(y: 58 * 0.52 * 0.38)
        }
        .frame(width: 92 * 0.48, height: 58 * 0.52)
        .offset(x: 92 * 0.26, y: 58 * 0.26)
    }
}

/// App icon for a bundle ID, if it's installed.
enum AppIcons {
    static func icon(for bundleID: String) -> NSImage? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func name(for bundleID: String) -> String {
        let known = ["com.raycast.macos": "Raycast", "com.runningwithcrayons.Alfred": "Alfred",
                     "com.apple.Spotlight": "Spotlight"]
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return known[bundleID] ?? bundleID
    }
}

/// An installed app's icon, or a lettered tile like the design's placeholders.
struct AppIconTile: View {
    let bundleID: String
    var size: CGFloat = 24

    var body: some View {
        if let icon = AppIcons.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.18, height: size * 1.18)
                .frame(width: size, height: size)
        } else {
            let name = AppIcons.name(for: bundleID)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color(hex: 0x4B4F5C))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                if bundleID == "com.apple.Spotlight" {
                    Image(systemName: "magnifyingglass").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
    }
}
