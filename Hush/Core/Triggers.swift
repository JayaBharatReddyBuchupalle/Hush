import AppKit

/// Counts horizontal direction reversals within a short window, ignoring wiggles shorter than a minimum
/// travel distance. Uses raw deltaX, which keeps reporting motion even when the cursor is pinned against a
/// screen edge. Only mouseMoved is monitored, so drags never trigger it (and scrolling isn't motion).
@MainActor
final class ShakeDetector {
    struct Tuning {
        var window: TimeInterval        // reversals must happen within this span
        var minReversals: Int
        var minSegment: CGFloat         // points of travel before a direction change counts

        /// 0 = firm (hard to trigger), 100 = light (very easy).
        static func from(sensitivity v: Double) -> Tuning {
            let t = max(0, min(1, v / 100))
            return Tuning(window: 0.45 + 0.35 * t, minReversals: t > 0.66 ? 3 : 4, minSegment: CGFloat(70 - 45 * t))
        }
    }

    var tuning = Tuning.from(sensitivity: 50)
    var requiredModifiers: NSEvent.ModifierFlags = []
    var cooldown: TimeInterval = 0.8
    /// After a shake fires, the pointer has to settle for this long before another shake can count, so one
    /// long, vigorous shake turns Hush off once instead of off and straight back on.
    var settle: TimeInterval = 0.35
    var logReversals = false
    /// Location of the pointer and the modifier keys held during the shake.
    var onShake: ((NSPoint, NSEvent.ModifierFlags) -> Void)?

    private var monitors: [Any] = []
    private var lastSign: CGFloat = 0
    private var segment: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude
    private var lastReversal: TimeInterval = -.greatestFiniteMagnitude
    private var lastEvent: TimeInterval = -.greatestFiniteMagnitude
    private var armed = true

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        stop()
        let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            MainActor.assumeIsolated { self?.feed(e) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            MainActor.assumeIsolated { self?.feed(e) }
            return e
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func reset() {
        lastSign = 0
        segment = 0
        reversals.removeAll()
    }

    private func feed(_ e: NSEvent) {
        // Shift never blocks a shake (it only matters when "Hold Shift and shake to peek" is on).
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .function]
        if !requiredModifiers.isEmpty, e.modifierFlags.intersection(relevant) != requiredModifiers {
            reset()
            return
        }
        let dx = e.deltaX
        guard abs(dx) >= 1 else { return }
        let t = e.timestamp
        if t - lastEvent > tuning.window { reset() }          // a pause starts a fresh gesture
        lastEvent = t
        if !armed, t - lastReversal > settle {                // the previous shake has ended
            armed = true
            reversals.removeAll()
        }
        let sign: CGFloat = dx > 0 ? 1 : -1
        if sign == lastSign || lastSign == 0 {
            segment += abs(dx)
        } else {
            if segment >= tuning.minSegment {
                reversals.append(t)
                lastReversal = t
                if logReversals {
                    DebugLog.shared.log(String(format: "shake: reversal %d after %.0f pt%@", reversals.count, segment,
                                               armed ? "" : " (same shake, ignored)"))
                }
            }
            segment = abs(dx)
        }
        lastSign = sign
        reversals.removeAll { t - $0 > tuning.window }
        guard armed, reversals.count >= tuning.minReversals, t - lastFire > cooldown else { return }
        lastFire = t
        armed = false                                         // one shake, one toggle
        reversals.removeAll()
        if logReversals { DebugLog.shared.log("shake: fired") }
        onShake?(NSEvent.mouseLocation, e.modifierFlags)
    }

    #if DEBUG
    /// Lets the Debug shake simulator drive the real detector.
    func debugFeed(_ e: NSEvent) { feed(e) }
    #endif
}

/// Screen corners with an action assigned in System Settings › Desktop & Dock › Hot Corners.
enum HotCorners {
    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight
        var key: String {
            switch self {
            case .topLeft: return "wvous-tl-corner"
            case .topRight: return "wvous-tr-corner"
            case .bottomLeft: return "wvous-bl-corner"
            case .bottomRight: return "wvous-br-corner"
            }
        }
    }

    static func active() -> Set<Corner> {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        return Set(Corner.allCases.filter { corner in
            let value = (CFPreferencesCopyAppValue(corner.key as CFString, domain) as? NSNumber)?.intValue ?? 0
            return value >= 2          // 0 and 1 mean "no action"
        })
    }
}

/// Peeks temporarily hide the overlay without turning Hush off: screen corners, holding a key,
/// dragging a file, and Shift-shake (which lasts until Shift is released).
@MainActor
final class PeekMonitor {
    var onPeek: ((OverlayController.PeekReason, Bool) -> Void)?
    var cornerEnabled = true
    var holdModifiers: NSEvent.ModifierFlags = []
    var dragEnabled = true

    private var monitors: [Any] = []
    private var inCorner = false
    private var holding = false
    private var dragging = false
    private var shiftPeeking = false
    private var cornerTimer: Timer?
    private var holdTimer: Timer?
    private var dragWatch: Timer?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var hotCorners: Set<HotCorners.Corner> = []
    private var hotCornersReadAt = Date.distantPast

    func start() {
        stop()
        let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCorner() }
        }
        let localMoved = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            MainActor.assumeIsolated { self?.checkCorner() }
            return e
        }
        let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            MainActor.assumeIsolated { self?.checkFlags(e.modifierFlags) }
        }
        let localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            MainActor.assumeIsolated { self?.checkFlags(e.modifierFlags) }
            return e
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
            MainActor.assumeIsolated { self?.checkDrag(e) }
        }
        monitors = [moved, localMoved, flags, localFlags, drag].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        cornerTimer?.invalidate(); cornerTimer = nil
        holdTimer?.invalidate(); holdTimer = nil
        dragWatch?.invalidate(); dragWatch = nil
        for (reason, active) in [(OverlayController.PeekReason.corner, inCorner), (.hold, holding),
                                 (.drag, dragging), (.shiftShake, shiftPeeking)] where active {
            onPeek?(reason, false)
        }
        inCorner = false; holding = false; dragging = false; shiftPeeking = false
    }

    /// Shift-shake: peek until Shift is released.
    func beginShiftPeek() {
        guard !shiftPeeking else { return }
        shiftPeeking = true
        onPeek?(.shiftShake, true)
    }

    // MARK: Corners

    private func checkCorner() {
        guard cornerEnabled else { return }
        let hit = cornerHit(NSEvent.mouseLocation)
        if hit {
            guard !inCorner, cornerTimer == nil else { return }
            // A short dwell keeps a quick swipe past a corner (towards the clock, say) from flashing the overlay.
            cornerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.cornerTimer = nil
                    if self.cornerHit(NSEvent.mouseLocation), !self.inCorner {
                        self.inCorner = true
                        self.onPeek?(.corner, true)
                    }
                }
            }
        } else {
            cornerTimer?.invalidate()
            cornerTimer = nil
            if inCorner {
                inCorner = false
                onPeek?(.corner, false)
            }
        }
    }

    private func cornerHit(_ p: NSPoint) -> Bool {
        if Date().timeIntervalSince(hotCornersReadAt) > 10 {
            hotCorners = HotCorners.active()
            hotCornersReadAt = Date()
        }
        let zone: CGFloat = 3
        let screens = NSScreen.screens
        for screen in screens {
            let f = screen.frame
            guard f.insetBy(dx: -1, dy: -1).contains(p) else { continue }
            let left = p.x <= f.minX + zone, right = p.x >= f.maxX - zone
            let bottom = p.y <= f.minY + zone, top = p.y >= f.maxY - zone
            guard (left || right) && (top || bottom) else { continue }
            let corner: HotCorners.Corner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
            if hotCorners.contains(corner) { continue }
            // Skip corners where another display continues, since the pointer can't be "pushed" there.
            let cx = left ? f.minX : f.maxX, cy = bottom ? f.minY : f.maxY
            let outward = [CGPoint(x: cx + (left ? -2 : 2), y: cy + (bottom ? 2 : -2)),
                           CGPoint(x: cx + (left ? 2 : -2), y: cy + (bottom ? -2 : 2))]
            if outward.contains(where: { pt in screens.contains { $0 !== screen && $0.frame.contains(pt) } }) {
                continue
            }
            return true
        }
        return false
    }

    // MARK: Modifier keys

    private func checkFlags(_ flags: NSEvent.ModifierFlags) {
        if shiftPeeking, !flags.contains(.shift) {
            shiftPeeking = false
            onPeek?(.shiftShake, false)
        }
        guard !holdModifiers.isEmpty else { return }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        holdTimer?.invalidate()
        holdTimer = nil
        if flags.intersection(relevant) == holdModifiers {
            // Wait 250 ms so ordinary shortcuts that use the same modifiers don't flash the overlay.
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.holding else { return }
                    self.holding = true
                    self.onPeek?(.hold, true)
                }
            }
        } else if holding {
            holding = false
            onPeek?(.hold, false)
        }
    }

    // MARK: Drags

    private func checkDrag(_ e: NSEvent) {
        guard dragEnabled else { return }
        switch e.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            let count = NSPasteboard(name: .drag).changeCount
            if count != dragChangeCount, !dragging {      // a new drag session wrote to the drag pasteboard
                dragChangeCount = count
                dragging = true
                onPeek?(.drag, true)
                // Mouse-up isn't always delivered once a drag session takes over; watch the button instead.
                dragWatch?.invalidate()
                dragWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if NSEvent.pressedMouseButtons & 1 == 0 { self?.endDrag() }
                    }
                }
            }
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    private func endDrag() {
        dragWatch?.invalidate()
        dragWatch = nil
        guard dragging else { return }
        dragging = false
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        onPeek?(.drag, false)
    }
}
