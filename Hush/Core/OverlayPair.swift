import AppKit

/// Where a Cursor Reveal starts, in global AppKit coordinates.
struct RevealSpec {
    let center: CGPoint
    let radius: CGFloat
    let duration: TimeInterval
}

/// The two overlay windows for one display. When focus moves, the spare overlay is ordered under the new
/// target and faded in while the current one fades out. A generation counter stops a late completion
/// handler from ordering out a window that a newer transition is fading back in.
@MainActor
final class OverlayPair {
    let displayID: CGDirectDisplayID
    private(set) var screen: NSScreen
    private let windows: [OverlayWindow]
    private var active = 0
    private(set) var plan: ScreenPlan?
    private(set) var isShowing = false
    private(set) var generation = 0
    private var maskSource: ScreenPlan?
    private var maskImage: CGImage?

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.screen = screen
        self.displayID = displayID
        windows = (0..<2).map { _ in
            let window = OverlayWindow(screen: screen)
            window.contentView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
            return window
        }
    }

    private var current: OverlayWindow { windows[active] }
    private var spare: OverlayWindow { windows[1 - active] }
    private func content(_ w: OverlayWindow) -> OverlayContentView {
        // swiftlint:disable:next force_cast
        w.contentView as! OverlayContentView
    }

    var windowNumbers: Set<Int> { Set(windows.map(\.windowNumber)) }
    var layerTree: String {
        windows.enumerated().map { i, w in
            let view = content(w)
            return "window \(w.windowNumber)\(i == active ? " (current)" : "") visible \(w.isVisible) alpha \(w.alphaValue) "
                + "onActiveSpace \(w.isOnActiveSpace) effectVisible \(view.isEffectVisible) presentation \(view.presentationOpacity)\n"
                + view.layerTree
        }.joined(separator: "\n")
    }

    func configure(_ effect: EffectConfig) {
        windows.forEach { content($0).apply(effect) }
    }

    /// Returns true when the overlay moved to a new target (a crossfade started).
    @discardableResult
    func apply(_ new: ScreenPlan, duration: TimeInterval, reveal: RevealSpec?, snapshot: [WinInfo]) -> Bool {
        guard new.visible else {
            hide(duration: duration, reveal: nil)
            return false
        }
        let old = plan
        plan = new
        let mask = mask(for: new)

        // Same target and already showing: at most the mask changed (moves, resizes, holes), and the window
        // might have drifted in the stack (another app ordered a window in between).
        if let old, isShowing, old.targetID == new.targetID {
            content(current).setPlanMask(mask)
            if !isPlaced(current, below: new.targetID, in: snapshot) {
                #if DEBUG
                DebugLog.shared.log("z-order repair: window \(current.windowNumber) below \(new.targetID.map(String.init) ?? "front")")
                #endif
                order(current, below: new.targetID)
            }
            return false
        }

        let incoming = spare, outgoing = current
        let inView = content(incoming), outView = content(outgoing)
        let wasShowing = isShowing
        isShowing = true
        active = 1 - active
        generation += 1
        let gen = generation
        inView.setPlanMask(mask)

        if let reveal, !wasShowing {
            // Cursor Reveal: the effect grows as a circle from the pointer.
            if outgoing.isVisible {
                outView.setVisible(false, duration: 0)
                outView.endReveal()
                outgoing.orderOut(nil)
            }
            order(incoming, below: new.targetID)
            let local = CGPoint(x: reveal.center.x - screen.frame.minX, y: reveal.center.y - screen.frame.minY)
            inView.animateReveal(center: local, from: 0.5, to: reveal.radius, duration: reveal.duration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    inView.endReveal()
                }
            }
            return true
        }

        inView.endReveal()                 // an interrupted reveal must not leave its circular mask behind
        if !incoming.isVisible { inView.setVisible(false, duration: 0) }   // start transparent
        order(incoming, below: new.targetID)
        inView.setVisible(true, duration: duration)
        if outgoing.isVisible {
            outView.setVisible(false, duration: duration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    outgoing.orderOut(nil)      // stop compositing its backdrop
                }
            }
        }
        return true
    }

    func hide(duration: TimeInterval, reveal: RevealSpec?) {
        plan = nil
        guard isShowing || windows.contains(where: \.isVisible) else { return }
        isShowing = false
        generation += 1
        let gen = generation
        let all = windows

        if let reveal, current.isVisible, content(current).isEffectVisible {
            let view = content(current)
            let local = CGPoint(x: reveal.center.x - screen.frame.minX, y: reveal.center.y - screen.frame.minY)
            if spare.isVisible { content(spare).setVisible(false, duration: min(duration, 0.2)) }
            view.animateReveal(center: local, from: reveal.radius, to: 0.5, duration: reveal.duration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    view.setVisible(false, duration: 0)
                    view.endReveal()
                    all.forEach { $0.orderOut(nil) }
                }
            }
            return
        }

        for w in all where w.isVisible {
            let view = content(w)
            view.setVisible(false, duration: duration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    view.endReveal()
                    w.orderOut(nil)
                }
            }
        }
    }

    func tearDown() {
        generation += 1
        windows.forEach {
            content($0).endReveal()
            content($0).setVisible(false, duration: 0)
            $0.orderOut(nil)
            $0.close()
        }
        isShowing = false
        plan = nil
    }

    // MARK: Ordering

    private func order(_ w: OverlayWindow, below target: CGWindowID?) {
        if let target {
            w.order(.below, relativeTo: Int(target))
        } else {
            w.orderFrontRegardless()            // nothing to keep sharp on this display
        }
    }

    /// True when no other app's normal window on this display sits between the target and the overlay.
    private func isPlaced(_ w: OverlayWindow, below target: CGWindowID?, in snap: [WinInfo]) -> Bool {
        guard let mine = snap.firstIndex(where: { $0.id == CGWindowID(w.windowNumber) }) else { return false }
        let start: Int
        if let target {
            guard let t = snap.firstIndex(where: { $0.id == target }) else { return true }   // can't tell; leave it
            guard t < mine else { return false }
            start = t + 1
        } else {
            start = 0
        }
        let frame = screen.frame
        return !snap[start..<mine].contains { other in
            !other.isOwn && other.layer == 0 && Geometry.area(other.frame.intersection(frame)) > 0
        }
    }

    // MARK: Masks

    private func mask(for p: ScreenPlan) -> CGImage? {
        guard !p.holes.isEmpty || p.ambient != nil else {
            maskSource = nil
            maskImage = nil
            return nil
        }
        if let src = maskSource, src.holes == p.holes, src.ambient == p.ambient, let maskImage { return maskImage }
        maskSource = p
        maskImage = MaskBuilder.make(size: screen.frame.size, ambient: p.ambient, holes: p.holes)
        return maskImage
    }
}
