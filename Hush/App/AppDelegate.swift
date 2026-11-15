import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let panel = PanelController()
    private let shake = ShakeDetector()
    private let peek = PeekMonitor()
    private var lastShakeConfig = ""
    private var lastPeekConfig = ""

    private var overlay: OverlayController { .shared }
    private var store: SettingsStore { .shared }

    var debugPanel: PanelController { panel }
    var debugStatusButton: NSStatusBarButton? { statusItem?.button }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemChrome.restoreIfNeeded()                     // crash recovery for Dock / menu bar
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        SystemState.shared.start()

        let overlay = self.overlay
        let store = self.store
        let status = StatusItemController(overlay: overlay, store: store)
        status.onTogglePanel = { [weak self] in self?.togglePanel() }
        status.onOpenSettings = { [weak self] in self?.openSettings(nil) }
        statusItem = status

        panel.makeContent = { [weak self] in
            AnyView(QuickPanel(store: store, overlay: overlay, system: SystemState.shared,
                               openSettings: { page in self?.openSettings(page) },
                               quit: { NSApp.terminate(nil) }))
        }
        panel.onVisibilityChange = { [weak self] shown in self?.statusItem?.setHighlighted(shown) }

        overlay.onNeedsAccess = { [weak self] in self?.showAccessHelp() }
        overlay.onPowerChange = { [weak self] _ in self?.applyTriggers() }
        URLRouter.showPanel = { [weak self] in self?.showPanel() }
        URLRouter.showSettings = { [weak self] page in self?.openSettings(page) }
        OnboardingWindowController.shared.onTurnOn = { overlay.turnOn() }
        OnboardingWindowController.shared.onOpenSettings = { [weak self] in self?.openSettings(nil) }

        HotKeys.shared.onAction = { [weak self] action in self?.handle(action) }
        shake.onShake = { [weak self] _, flags in self?.handleShake(flags) }
        peek.onPeek = { reason, active in overlay.setPeek(reason, active) }
        applyTriggers()
        store.observe { [weak self] _, _ in self?.applyTriggers() }

        if !OnboardingWindowController.isComplete || !overlay.canTurnOn {
            OnboardingWindowController.shared.show()
        }
        #if DEBUG
        DebugAutomation.runIfRequested()
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { URLRouter.handle($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.turnOff(animated: false)
        SystemChrome.restoreIfNeeded(sync: true)
        store.saveNow()
    }

    // MARK: Triggers

    /// Only restarts monitors when their settings change, not on every blur-slider tick.
    private func applyTriggers() {
        let s = store.value
        let shakeConfig = "\(s.shakeEnabled)|\(s.shakeSensitivity)|\(s.shakeModifiers)|\(s.logShakeReversals)"
        if shakeConfig != lastShakeConfig {
            lastShakeConfig = shakeConfig
            shake.tuning = .from(sensitivity: s.shakeSensitivity)
            shake.requiredModifiers = NSEvent.ModifierFlags(rawValue: s.shakeModifiers)
            shake.logReversals = s.logShakeReversals
            if s.shakeEnabled { if !shake.isRunning { shake.start() } } else { shake.stop() }
        }
        // Peeks only matter while Hush is on.
        let peekConfig = "\(overlay.isOn)|\(s.cornerPeek)|\(s.holdToPeekModifiers)|\(s.dragPeek)"
        if peekConfig != lastPeekConfig {
            lastPeekConfig = peekConfig
            peek.cornerEnabled = s.cornerPeek
            peek.holdModifiers = NSEvent.ModifierFlags(rawValue: s.holdToPeekModifiers)
            peek.dragEnabled = s.dragPeek
            if overlay.isOn { peek.start() } else { peek.stop() }
        }
        var combos: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases { combos[action] = s.shortcut(action) }
        HotKeys.shared.update(combos)
    }

    #if DEBUG
    private var debugShakeClock: TimeInterval = 0

    /// Debug builds: feeds synthetic side-to-side shakes through the real detector and handler.
    /// `gestures` shakes of `reversals` direction changes each (80 pt per stroke), `gap` seconds apart.
    func debugSimulateShake(reversals: Int, shift: Bool, gestures: Int, gap: TimeInterval) {
        let source = CGEventSource(stateID: .hidSystemState)
        let p = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: p.x, y: Geometry.primaryHeight - p.y)
        func event(dx: Int64, at seconds: TimeInterval, unit: Double) -> NSEvent? {
            guard let cg = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                   mouseCursorPosition: cgPoint, mouseButton: .left) else { return nil }
            cg.setIntegerValueField(.mouseEventDeltaX, value: dx)
            cg.flags = shift ? .maskShift : []
            cg.timestamp = CGEventTimestamp(seconds / unit)
            return NSEvent(cgEvent: cg)
        }
        // CGEvent timestamps aren't seconds; measure the unit with a probe so synthetic timing is exact.
        let unit = (event(dx: 0, at: 1, unit: 1e-9)?.timestamp ?? 1) / 1e9     // seconds per timestamp unit
        let step = 0.02, perStroke = 4
        let duration = Double(gestures) * Double((reversals + 1) * perStroke) * step + Double(max(0, gestures - 1)) * gap
        // In the past (so real pointer events that follow aren't "earlier"), but after any previous simulation.
        var t = max(ProcessInfo.processInfo.systemUptime - duration - 1, debugShakeClock + 1)
        DebugLog.shared.log("debug: simulating \(gestures) shake(s) of \(reversals) reversals, shift \(shift)")
        for g in 0..<gestures {
            if g > 0 { t += gap }
            var direction: Int64 = 1
            for _ in 0...reversals {
                for _ in 0..<perStroke {
                    t += step
                    if let e = event(dx: 20 * direction, at: t, unit: unit) { shake.debugFeed(e) }
                }
                direction = -direction
            }
        }
        debugShakeClock = t
        DebugLog.shared.log("debug: simulation done; Hush is \(overlay.isOn ? "on" : "off")"
            + (overlay.isPeeking ? ", peeking" : ""))
    }
    #endif

    private func handleShake(_ flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift) && store.value.shakePeekEnabled {
            if overlay.isOn { peek.beginShiftPeek() }
            return
        }
        overlay.toggle()
    }

    private func handle(_ action: ShortcutAction) {
        switch action {
        case .toggleOverlay: overlay.toggle()
        case .toggleMode: store.update { $0.mode.toggle() }
        case .toggleExclude: overlay.setFrontAppExcluded(nil)
        case .showPanel: togglePanel()
        }
    }

    // MARK: Windows

    private func togglePanel() {
        panel.toggle(from: statusItem?.button)
    }

    private func showPanel() {
        if !panel.isShown { panel.show(from: statusItem?.button) }
    }

    private func openSettings(_ page: SettingsPage?) {
        panel.close()
        SettingsWindowController.shared.show(page: page)
    }

    private func showAccessHelp() {
        if OnboardingWindowController.isComplete {
            showPanel()
        } else {
            OnboardingWindowController.shared.show()
        }
    }

    // MARK: Menu

    @objc private func openSettingsFromMenu(_ sender: Any?) { openSettings(nil) }

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Hush")
        appMenu.addItem(withTitle: "About Hush", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hush", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}
