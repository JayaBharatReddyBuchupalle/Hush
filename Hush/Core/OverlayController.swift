import AppKit
import Observation

/// Owns the on/off/peek state, the per-display overlay pairs, focus tracking and retargeting.
///
/// State machine: Off or On. While On, two sub-states suppress drawing without switching Hush off:
/// Suspended (the front app is ignored, or has no windows and desktop reveal is on) and Peeking.
/// Turning off orders the overlays out entirely, stops observers and polling, and restores Dock/menu bar.
@MainActor @Observable
final class OverlayController {
    static let shared = OverlayController()

    enum PeekReason: Hashable { case corner, hold, drag, shiftShake }
    enum IconState { case on, off, paused, needsAccess }

    struct FrontApp: Equatable {
        let pid: pid_t
        let bundleID: String
        let name: String
    }

    private(set) var isOn = false
    private(set) var peekReasons: Set<PeekReason> = []
    private(set) var isSuspended = false
    private(set) var isDesktopRevealed = false
    private(set) var frontApp: FrontApp?
    private(set) var pendingTurnOn = false
    private(set) var effect: EffectConfig

    var isPeeking: Bool { !peekReasons.isEmpty }

    var isFrontAppIgnored: Bool {
        guard let id = frontApp?.bundleID, !id.isEmpty else { return false }
        return store.value.ignoredBundleIDs.contains(id)
    }

    var canTurnOn: Bool {
        !DevFlags.forceNeedsAccess && (system.accessibilityTrusted || DevFlags.skipAccessibilityCheck)
    }

    var iconState: IconState {
        if !canTurnOn { return .needsAccess }
        if !isOn { return .off }
        return isFrontAppIgnored ? .paused : .on
    }

    /// Called when something asks Hush to turn on before Accessibility is allowed.
    @ObservationIgnored var onNeedsAccess: (() -> Void)?
    /// Called after Hush turns on (true) or off (false).
    @ObservationIgnored var onPowerChange: ((Bool) -> Void)?

    @ObservationIgnored private let store = SettingsStore.shared
    @ObservationIgnored private let system = SystemState.shared
    @ObservationIgnored private var pairs: [CGDirectDisplayID: OverlayPair] = [:]
    @ObservationIgnored private let tracker = FocusTracker()
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var lastExternalPID: pid_t?
    @ObservationIgnored private var lastSignature = ""
    @ObservationIgnored private var retargetQueued = false
    @ObservationIgnored private var lastTargets: [CGDirectDisplayID: CGWindowID] = [:]
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var stageManagerCache: (value: Bool, at: Date) = (false, .distantPast)
    @ObservationIgnored private var lastDriftLog = Date.distantPast
    @ObservationIgnored private let myPID = ProcessInfo.processInfo.processIdentifier

    private var s: HushSettings { store.value }

    private init() {
        effect = EffectConfig.make(SettingsStore.shared.value,
                                   reduceTransparency: SystemState.shared.reduceTransparency,
                                   lowPower: SystemState.shared.lowPowerMode)
        store.observe { [weak self] old, new in self?.settingsChanged(old: old, new: new) }
        system.observe { [weak self] in self?.systemChanged() }

        let ws = NSWorkspace.shared.notificationCenter
        tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFrontApp() }
        })
        tokens.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFrontApp() }
        })
        // The window server can rebuild a backdrop's filters around wake and display changes: re-apply.
        let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.reapplyEffect() }
            }
        }
        tokens.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reapply))
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main, using: reapply))
        refreshFrontApp()
    }

    // MARK: On / off

    func toggle() { isOn ? turnOff() : turnOn() }

    func turnOn() {
        guard !isOn else { return }
        guard canTurnOn else {
            pendingTurnOn = true
            onNeedsAccess?()
            return
        }
        pendingTurnOn = false
        isOn = true
        peekReasons = []
        rebuildScreens()
        tracker.start(onChange: { [weak self] in self?.scheduleRetarget() },
                      onScreensChanged: { [weak self] in
                          self?.rebuildScreens()
                          self?.scheduleRetarget()
                      })
        startPoll()
        SystemChrome.apply(hideDock: s.autoHideDock, hideMenuBar: s.autoHideMenuBar)
        DebugLog.shared.log("overlay on, \(s.mode.title) mode, \(effect.methodDescription)")
        onPowerChange?(true)
        retarget(reveal: s.revealStyle == .cursor ? makeReveal() : nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.reapplyEffect() }
        }
    }

    func turnOff(animated: Bool = true) {
        pendingTurnOn = false
        guard isOn else { return }
        isOn = false
        peekReasons = []
        isSuspended = false
        isDesktopRevealed = false
        tracker.stop()
        poll?.invalidate()
        poll = nil
        let reveal = animated && s.revealStyle == .cursor ? makeReveal() : nil
        pairs.values.forEach { $0.hide(duration: animated ? crossfadeDuration : 0, reveal: reveal) }
        lastTargets = [:]
        SystemChrome.restoreIfNeeded()
        DebugLog.shared.log("overlay off")
        onPowerChange?(false)
    }

    /// Cancels a turn-on that was waiting for Accessibility.
    func cancelPendingTurnOn() { pendingTurnOn = false }

    // MARK: Peeking

    func setPeek(_ reason: PeekReason, _ active: Bool) {
        let was = isPeeking
        if active && isOn { peekReasons.insert(reason) } else { peekReasons.remove(reason) }
        guard isOn, was != isPeeking else { return }
        if isPeeking {
            pairs.values.forEach { $0.hide(duration: 0.15, reveal: nil) }
            lastTargets = [:]
            DebugLog.shared.log("peek: \(reason)")
        } else {
            DebugLog.shared.log("peek ended")
            retarget()
        }
    }

    // MARK: Ignore list

    /// nil toggles. Used by the hotkey, the panel button and hush://app/…
    func setFrontAppExcluded(_ excluded: Bool?) {
        refreshFrontApp()
        guard let app = frontApp, !app.bundleID.isEmpty else { NSSound.beep(); return }
        let isExcluded = s.ignoredBundleIDs.contains(app.bundleID)
        let want = excluded ?? !isExcluded
        store.update { st in
            if want && !isExcluded { st.ignoredBundleIDs.append(app.bundleID) }
            if !want { st.ignoredBundleIDs.removeAll { $0 == app.bundleID } }
        }
    }

    // MARK: Changes

    private func settingsChanged(old: HushSettings, new: HushSettings) {
        updateEffect()
        let planChanged = old.mode != new.mode || old.ambientCoverage != new.ambientCoverage
            || old.scope != new.scope || old.displayMode != new.displayMode
            || old.ignoredBundleIDs != new.ignoredBundleIDs || old.appGroups != new.appGroups
            || old.hideWhenNoWindow != new.hideWhenNoWindow
        if isOn && planChanged { scheduleRetarget() }
        if isOn && (old.autoHideDock != new.autoHideDock || old.autoHideMenuBar != new.autoHideMenuBar) {
            SystemChrome.apply(hideDock: new.autoHideDock, hideMenuBar: new.autoHideMenuBar)
        }
    }

    private func systemChanged() {
        updateEffect()
        if pendingTurnOn && canTurnOn {
            DebugLog.shared.log("Accessibility allowed; turning on")
            turnOn()
        }
    }

    private func updateEffect() {
        let e = EffectConfig.make(s, reduceTransparency: system.reduceTransparency, lowPower: system.lowPowerMode)
        guard e != effect else { return }
        let methodChanged = e.method != effect.method
        effect = e
        pairs.values.forEach { $0.configure(e) }
        if methodChanged { DebugLog.shared.log("blur method: \(e.methodDescription)") }
    }

    private func reapplyEffect() {
        pairs.values.forEach { $0.configure(effect) }
    }

    #if DEBUG
    func debugReapplyEffect() {
        DebugLog.shared.log("debug: re-applying effect")
        reapplyEffect()
    }
    #endif

    private var crossfadeDuration: TimeInterval {
        let base = max(0, min(s.crossfade, 1))
        return system.lowPowerMode ? base * 0.5 : base
    }

    // MARK: Targeting

    func scheduleRetarget() {
        guard !retargetQueued else { return }
        retargetQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retargetQueued = false
                self.retarget()
            }
        }
    }

    private func retarget(reveal: RevealSpec? = nil) {
        guard isOn, !isPeeking, let pid = externalFrontPID() else { return }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let snap = WindowList.snapshot()
        lastSignature = signature(snap, pid)

        if s.ignoredBundleIDs.contains(bundleID) {                     // Suspended
            if !isSuspended { DebugLog.shared.log("suspended: \(frontApp?.name ?? bundleID) is ignored") }
            isSuspended = true
            pairs.values.forEach { $0.hide(duration: crossfadeDuration, reveal: nil) }
            lastTargets = [:]
            return
        }
        isSuspended = false

        let focus = Planner.focusWindow(snapshot: snap, frontPID: pid, focusedID: AX.focusedWindowID(pid: pid))
        let clear = Planner.clearIDs(snapshot: snap, frontPID: pid, groupPIDs: s.groupPIDs(for: bundleID),
                                     scope: s.scope, stageManager: stageManagerEnabled)
        let plans = Planner.plan(snapshot: snap, focus: focus, clear: clear, settings: s)

        let revealed = !plans.isEmpty && plans.values.allSatisfy { !$0.visible }
        if revealed != isDesktopRevealed {
            isDesktopRevealed = revealed
            if revealed { DebugLog.shared.log("desktop reveal: \(frontApp?.name ?? "front app") has no windows") }
        }

        for (displayID, plan) in plans {
            guard let pair = pairs[displayID] else { continue }
            let moved = pair.apply(plan, duration: crossfadeDuration, reveal: reveal, snapshot: snap)
            if plan.visible, moved || lastTargets[displayID] != plan.targetID {
                let display = Geometry.displayNumber(displayID)
                let target = plan.targetID.map { "window \($0)" } ?? "every window"
                DebugLog.shared.log("retarget → \(frontApp?.name ?? "?") (pid \(pid)), \(target), display \(display)\n"
                    + "plan: \(plan.targetID.map { "below \($0)" } ?? "front"), holes \(plan.holes.count), "
                    + "ambient \(plan.ambient == nil ? "off" : "on")"
                    + (moved ? String(format: "\ncrossfade %.2f s, generation %d", crossfadeDuration, pair.generation) : ""))
            }
            if plan.visible, let id = plan.targetID { lastTargets[displayID] = id } else { lastTargets[displayID] = nil }
        }
    }

    private var stageManagerEnabled: Bool {
        if Date().timeIntervalSince(stageManagerCache.at) > 3 {
            stageManagerCache = (StageManager.isEnabled, Date())
        }
        return stageManagerCache.value
    }

    private func startPoll() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retargetIfDrifted() }
        }
        poll?.tolerance = 0.1
    }

    /// Cheap drift check: catches new windows, reorders and moves the event stream missed.
    private func retargetIfDrifted() {
        guard isOn, !isPeeking, let pid = externalFrontPID() else { return }
        if signature(WindowList.snapshot(), pid) != lastSignature {
            // Window drags change the signature on every tick; note drift at most every few seconds.
            if Date().timeIntervalSince(lastDriftLog) > 3 {
                lastDriftLog = Date()
                DebugLog.shared.log("drift poll: window list changed")
            }
            retarget()
        }
    }

    private func signature(_ snap: [WinInfo], _ pid: pid_t) -> String {
        "\(pid)|" + snap.lazy.filter { $0.layer == 0 && !$0.isOwn }.prefix(24).map {
            "\($0.id):\(Int($0.cgFrame.minX)),\(Int($0.cgFrame.minY)),\(Int($0.cgFrame.width)),\(Int($0.cgFrame.height))"
        }.joined(separator: ";")
    }

    /// Hush's own panel, Settings and URL handling must never become the focus target.
    func externalFrontPID() -> pid_t? {
        refreshFrontApp()
        return lastExternalPID
    }

    private func refreshFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != myPID else {
            if let pid = lastExternalPID, NSRunningApplication(processIdentifier: pid) == nil {
                lastExternalPID = nil
                frontApp = nil
            }
            return
        }
        lastExternalPID = app.processIdentifier
        let info = FrontApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "",
                            name: app.localizedName ?? app.bundleIdentifier ?? "App")
        if frontApp != info { frontApp = info }
    }

    // MARK: Displays

    func rebuildScreens() {
        let screens = Dictionary(NSScreen.screens.map { (Geometry.displayID(of: $0), $0) },
                                 uniquingKeysWith: { first, _ in first })
        for (id, pair) in pairs where screens[id]?.frame != pair.screen.frame {
            pair.tearDown()
            pairs[id] = nil
            lastTargets[id] = nil
        }
        for (id, screen) in screens where pairs[id] == nil {
            let pair = OverlayPair(screen: screen, displayID: id)
            pair.configure(effect)
            pairs[id] = pair
        }
    }

    // MARK: Cursor Reveal

    private func makeReveal() -> RevealSpec {
        let p = NSEvent.mouseLocation
        var radius: CGFloat = 0
        for screen in NSScreen.screens {
            let f = screen.frame
            for corner in [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                           CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.maxX, y: f.maxY)] {
                radius = max(radius, hypot(corner.x - p.x, corner.y - p.y))
            }
        }
        let duration = system.lowPowerMode ? 0.3 : 0.45
        return RevealSpec(center: p, radius: radius + 24, duration: duration)
    }

    // MARK: Debug

    func layerTreeDump() -> String {
        if let pair = pairs.values.first { return pair.layerTree }
        let view = OverlayContentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.apply(effect)
        return view.layerTree + "\n(Hush hasn't been turned on yet; this is a fresh overlay)"
    }

    func windowListDump() -> String {
        (["window list, level 0, front to back"] + WindowList.describe(WindowList.snapshot())).joined(separator: "\n")
    }
}
