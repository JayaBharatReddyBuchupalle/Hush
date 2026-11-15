import AppKit
import QuartzCore

/// Full-display, click-through, borderless window at the normal level.
/// It is re-ordered directly beneath the focused window; it never takes focus.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true            // clicks fall through to the window underneath
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .normal                      // same level as app windows, so z-ordering works
        // .transient hides it in Mission Control; .fullScreenAuxiliary lets it quiet the other half of Split View.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        isExcludedFromWindowsMenu = true
        setFrame(screen.frame, display: false)
        // sharingType stays at its default, so the overlay shows up in screen shares and recordings.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content of one overlay window: backdrop (blur + saturation) → dimmer → tint → grain.
///
/// Masks go on each effect layer individually. A partial-alpha mask on a container that holds the backdrop
/// plus siblings makes the window server render the group offscreen, and the backdrop then captures nothing.
/// Masks are always image masks: on a normal-level window ordered below another app's window, changing a
/// CAShapeLayer mask (animated or not) on a backdrop stops the whole window from drawing, while swapping a
/// mask image works (both verified on macOS 27). The Cursor Reveal therefore steps small mask images.
final class OverlayContentView: NSView {
    private let container = CALayer()
    private let backdrop: CALayer? = PrivateCA.makeBackdropLayer()
    private let dim = CALayer()
    private let tint = CALayer()
    private let grain = CALayer()

    private(set) var effect: EffectConfig?
    private var planMask: CGImage?
    private var isRevealing = false
    private var revealTimer: Timer?
    private var revealCenter: CGPoint = .zero
    private var revealRadius: CGFloat = 0

    private var effectLayers: [CALayer] { [backdrop, dim, tint, grain].compactMap { $0 } }

    private static let noActions: [String: CAAction] = [
        "opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contents": NSNull(),
        "backgroundColor": NSNull(), "hidden": NSNull(), "mask": NSNull(), "filters": NSNull(), "path": NSNull(),
        "sublayers": NSNull(),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = [.width, .height]
        guard let root = layer else { return }
        container.actions = Self.noActions
        container.allowsGroupOpacity = false   // fade each layer, never render the group offscreen
        container.opacity = 0
        container.name = "hush.container"
        root.addSublayer(container)
        dim.backgroundColor = NSColor.black.cgColor
        dim.name = "hush.dim"
        tint.name = "hush.tint"
        grain.name = "hush.grain"
        grain.backgroundColor = GrainTexture.patternColor
        for l in effectLayers {
            l.actions = Self.noActions
            l.isHidden = true
            container.addSublayer(l)
        }
        layoutLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var allowsVibrancy: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        for l in effectLayers {
            l.frame = container.bounds
            l.mask?.frame = l.bounds
            l.mask?.mask?.frame = l.bounds
        }
        CATransaction.commit()
    }

    // MARK: Effect

    func apply(_ e: EffectConfig) {
        effect = e
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureBackdrop()
        dim.opacity = e.dimAlpha
        dim.isHidden = e.dimAlpha <= 0.001
        if let color = e.tint, e.tintAlpha > 0.001 {
            tint.backgroundColor = color.cgColor
            tint.opacity = e.tintAlpha
            tint.isHidden = false
        } else {
            tint.isHidden = true
        }
        grain.opacity = e.grainAlpha
        grain.isHidden = e.grainAlpha <= 0.001
        CATransaction.commit()
    }

    private func configureBackdrop() {
        guard let backdrop, let e = effect else { return }
        backdrop.isHidden = !e.needsBackdrop        // blur-free without mono: no backdrop cost at all
        guard e.needsBackdrop else { backdrop.filters = []; return }
        PrivateCA.configureBackdrop(backdrop, radius: e.blurRadius, saturation: e.saturation,
                                    variableMask: e.progressive ? planMask : nil, scale: e.backdropScale)
    }

    // MARK: Masks

    func setPlanMask(_ image: CGImage?) {
        guard image !== planMask else { return }
        planMask = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectLayers.forEach(updateMask)
        if effect?.progressive == true { configureBackdrop() }
        CATransaction.commit()
    }

    private func updateMask(for l: CALayer) {
        if isRevealing {
            setMaskImage(revealImage(), on: l)
        } else if let planMask {
            setMaskImage(planMask, on: l)
        } else {
            l.mask = nil
        }
    }

    private func setMaskImage(_ image: CGImage?, on l: CALayer) {
        let m = l.mask ?? {
            let m = CALayer()
            m.actions = Self.noActions
            m.contentsGravity = .resize
            return m
        }()
        m.frame = l.bounds
        m.contents = image
        l.mask = m
    }

    // MARK: Visibility

    /// Fades the whole effect with a render-server animation (smooth even if the main thread is busy).
    func setVisible(_ visible: Bool, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let target: Float = visible ? 1 : 0
        let current = container.presentation()?.opacity ?? container.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAnimation(forKey: "fade")
        container.opacity = target
        let animate = duration > 0.001 && abs(current - target) > 0.001
        if animate {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = current
            anim.toValue = target
            anim.duration = duration * Double(abs(target - current))
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            CATransaction.setCompletionBlock(completion)
            container.add(anim, forKey: "fade")
        }
        CATransaction.commit()
        if !animate { completion?() }
    }

    var isEffectVisible: Bool { container.opacity > 0.001 }
    var presentationOpacity: Float { container.presentation()?.opacity ?? -1 }

    /// Grows (show) or shrinks (hide) the effect as a circle centred on `center` (view coordinates).
    /// Each frame swaps in a quarter-resolution mask image; the upscaling softens the circle's edge.
    func animateReveal(center: CGPoint, from r0: CGFloat, to r1: CGFloat, duration: TimeInterval,
                       completion: @escaping () -> Void) {
        revealTimer?.invalidate()
        isRevealing = true
        revealCenter = center
        revealRadius = r0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAnimation(forKey: "fade")
        container.opacity = 1
        effectLayers.forEach(updateMask)
        CATransaction.commit()

        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.isRevealing else { timer.invalidate(); return }
                let p = min(1, (CACurrentMediaTime() - start) / max(duration, 0.01))
                let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2      // ease in-out
                self.revealRadius = r0 + (r1 - r0) * CGFloat(eased)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.effectLayers.forEach(self.updateMask)
                CATransaction.commit()
                if p >= 1 {
                    timer.invalidate()
                    self.revealTimer = nil
                    completion()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    /// Drops the reveal masks (back to the plan mask, or none).
    func endReveal() {
        revealTimer?.invalidate()
        revealTimer = nil
        guard isRevealing else { return }
        isRevealing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectLayers.forEach(updateMask)
        CATransaction.commit()
    }

    /// The plan mask (or full coverage) cut down to the current reveal circle, at quarter resolution.
    private func revealImage() -> CGImage? {
        let scale: CGFloat = 0.25
        let w = max(1, Int((bounds.width * scale).rounded(.up))), h = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        if let planMask {
            ctx.interpolationQuality = .low
            ctx.draw(planMask, in: full)
        } else {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(full)
        }
        let r = max(0, revealRadius) * scale
        let c = CGPoint(x: revealCenter.x * scale, y: revealCenter.y * scale)
        ctx.addRect(full)
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setBlendMode(.clear)
        ctx.fillPath(using: .evenOdd)                 // clear everything outside the circle
        return ctx.makeImage()
    }

    var layerTree: String { layer.map { layerTreeDescription($0) } ?? "(no layer)" }
}
