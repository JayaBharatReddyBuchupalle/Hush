import AppKit
import QuartzCore

/// Slider values (0–100) → render parameters. The blur curve keeps the low end subtle and lets the top end
/// get heavy quickly.
enum EffectMath {
    static func blurRadius(_ v: Double) -> CGFloat { CGFloat(pow(max(0, min(v, 100)) / 100, 1.4) * 60) }   // 0…60 pt
    static func saturation(monoOn: Bool, mono: Double) -> CGFloat { monoOn ? CGFloat(1 - max(0, min(mono, 100)) / 100) : 1 }
    static func tintAlpha(_ v: Double) -> Float { Float(max(0, min(v, 100)) / 100 * 0.8) }
    static func grainAlpha(_ v: Double) -> Float { Float(max(0, min(v, 100)) / 100 * 0.9) }
    /// What Hush draws instead of a blur when it has to fall back to dimming.
    static let fallbackDim: Float = 0.4
}

/// Everything an overlay needs to draw, resolved from settings plus the system state.
struct EffectConfig: Equatable {
    enum Method: Equatable {
        case backdrop                 // window-server blur via our own CABackdropLayer
        case dimmerReduceTransparency // Reduce Transparency is on and the user hasn't opted back into blur
        case dimmerUnavailable        // the private backdrop class is missing on this system
    }

    var method: Method
    var blurRadius: CGFloat
    var saturation: CGFloat
    var tint: NSColor?
    var tintAlpha: Float
    var dimAlpha: Float
    var grainAlpha: Float
    var progressive: Bool             // Ambient: use a variable blur that follows the mask
    var backdropScale: CGFloat

    var needsBackdrop: Bool { method == .backdrop && (blurRadius > 0.3 || saturation < 0.999) }

    static func make(_ s: HushSettings, reduceTransparency: Bool, lowPower: Bool) -> EffectConfig {
        let method: Method
        if !PrivateCA.isBackdropAvailable {
            method = .dimmerUnavailable
        } else if reduceTransparency && !s.blurWithReduceTransparency {
            method = .dimmerReduceTransparency
        } else {
            method = .backdrop
        }
        var radius = method == .backdrop ? EffectMath.blurRadius(s.blur) : 0
        if lowPower { radius = min(radius, 18) }                     // R23: cap the blur in Low Power Mode
        let saturation = method == .backdrop && PrivateCA.supportsSaturation
            ? EffectMath.saturation(monoOn: s.monoEnabled, mono: s.mono) : 1
        let dim: Float
        switch method {
        case .backdrop: dim = 0
        case .dimmerReduceTransparency: dim = EffectMath.fallbackDim
        case .dimmerUnavailable: dim = s.blur > 0.5 ? EffectMath.fallbackDim : 0
        }
        let tint = s.resolvedTint
        return EffectConfig(
            method: method,
            blurRadius: radius,
            saturation: saturation,
            tint: tint,
            tintAlpha: tint == nil ? 0 : EffectMath.tintAlpha(s.tintOpacity),
            dimAlpha: dim,
            grainAlpha: EffectMath.grainAlpha(s.grain),
            progressive: s.mode == .ambient,
            // A half-resolution backdrop is indistinguishable at large radii and much cheaper.
            backdropScale: (radius >= 12 || lowPower) ? 0.5 : 1
        )
    }

    var methodDescription: String {
        switch method {
        case .backdrop: return "Path B, own CABackdropLayer"
        case .dimmerReduceTransparency: return "Dimmer (Reduce Transparency)"
        case .dimmerUnavailable: return "Dimmer (backdrop unavailable)"
        }
    }
}

/// Film grain: a 256×256 tile of black and white specks with random alpha, drawn as a pattern colour so a
/// whole display costs one small image. Seeded, so the two overlays of a pair get identical grain and
/// crossfades don't shimmer.
enum GrainTexture {
    static let patternColor: CGColor = {
        guard let tile = makeTile() else { return NSColor.clear.cgColor }
        let image = NSImage(cgImage: tile, size: NSSize(width: tile.width, height: tile.height))
        return NSColor(patternImage: image).cgColor
    }()

    private static func makeTile(size: Int = 256) -> CGImage? {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {           // xorshift64*
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = next()
            let alpha = UInt8(truncatingIfNeeded: (r >> 8) % 97)        // 0…96
            let value: UInt8 = (r & 1) == 0 ? alpha : 0                  // premultiplied white, or black
            px[i] = value; px[i + 1] = value; px[i + 2] = value; px[i + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Masks

struct AmbientSpec: Equatable {
    var coverage: CGFloat          // fraction of screen height the gradient spans
}

/// One mask image per overlay carries both the Ambient gradient and any holes.
/// White means "effect visible", transparent means "keep sharp". Built at 1×: alpha masks don't need Retina.
enum MaskBuilder {
    /// `holes` are in screen-local AppKit coordinates (origin bottom-left), which match CGContext's.
    static func make(size: CGSize, ambient: AmbientSpec?, holes: [CGRect], cornerRadius: CGFloat = 10) -> CGImage? {
        let w = Int(size.width.rounded(.up)), h = Int(size.height.rounded(.up))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        if let ambient {
            // Strongest along the bottom edge, gone at `coverage` of the height. A short solid band at the
            // bottom and an eased falloff read as "rising" rather than as a flat fade.
            let top = CGFloat(h) * max(0.05, min(ambient.coverage, 1))
            let colors = [1.0, 1.0, 0.82, 0.5, 0.2, 0.0].map { CGColor(red: 1, green: 1, blue: 1, alpha: $0) }
            let locations: [CGFloat] = [0, 0.18, 0.36, 0.58, 0.8, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                         locations: locations) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: top), options: [])
            }
        } else {
            ctx.setFillColor(white)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        if !holes.isEmpty {
            ctx.setBlendMode(.clear)
            for r in holes {
                let radius = min(cornerRadius, r.width / 2, r.height / 2)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            ctx.fillPath()
        }
        return ctx.makeImage()
    }
}

enum RectMath {
    /// a − b as up to four non-overlapping rectangles.
    static func subtract(_ a: CGRect, _ b: CGRect) -> [CGRect] {
        let i = a.intersection(b)
        guard !i.isNull, !i.isEmpty else { return [a] }
        var out: [CGRect] = []
        if i.minY > a.minY { out.append(CGRect(x: a.minX, y: a.minY, width: a.width, height: i.minY - a.minY)) }
        if i.maxY < a.maxY { out.append(CGRect(x: a.minX, y: i.maxY, width: a.width, height: a.maxY - i.maxY)) }
        if i.minX > a.minX { out.append(CGRect(x: a.minX, y: i.minY, width: i.minX - a.minX, height: i.height)) }
        if i.maxX < a.maxX { out.append(CGRect(x: i.maxX, y: i.minY, width: a.maxX - i.maxX, height: i.height)) }
        return out
    }

    static func subtract(_ a: CGRect, all others: [CGRect]) -> [CGRect] {
        others.reduce([a]) { pieces, b in pieces.flatMap { subtract($0, b) } }
    }
}
