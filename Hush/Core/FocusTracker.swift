import AppKit
import ApplicationServices

/// Events give low latency; OverlayController's 3 Hz poll catches whatever they miss.
/// The Accessibility observer is re-attached each time a different app becomes frontmost.
@MainActor
final class FocusTracker {
    private var onChange: (() -> Void)?
    private var onScreens: (() -> Void)?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var screenToken: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0

    func start(onChange: @escaping () -> Void, onScreensChanged: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        self.onScreens = onScreensChanged
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
        ]
        workspaceTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontmostChanged() }
            }
        }
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScreens?() }
        }
        frontmostChanged()
    }

    func stop() {
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        detachAX()
        onChange = nil
        onScreens = nil
    }

    private func frontmostChanged() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           app.processIdentifier != observedPID {
            attachAX(to: app.processIdentifier)
        }
        onChange?()
    }

    private func attachAX(to pid: pid_t) {
        detachAX()
        guard AX.isTrusted else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.onChange?() }
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
            kAXWindowMovedNotification, kAXWindowResizedNotification,
        ]
        for name in notifications { AXObserverAddNotification(observer, app, name as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        observedPID = pid
    }

    private func detachAX() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
        observedPID = 0
    }
}
