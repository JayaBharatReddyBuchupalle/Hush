import AppKit
import Observation

/// System conditions Hush reacts to: Reduce Transparency, Low Power Mode and Accessibility trust.
@MainActor @Observable
final class SystemState {
    static let shared = SystemState()

    private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var accessibilityTrusted = AX.isTrusted

    @ObservationIgnored private var listeners: [() -> Void] = []
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var trustTimer: Timer?

    /// Called after any of the observed values change.
    func observe(_ listener: @escaping () -> Void) { listeners.append(listener) }

    func start() {
        guard tokens.isEmpty else { return }
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        tokens.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        // Posted whenever any app's Accessibility permission changes; the new value lands a moment later.
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                for delay in [0.3, 1.0, 2.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.refresh() }
                }
            }
        })
        scheduleTrustPoll()
    }

    private func scheduleTrustPoll() {
        trustTimer?.invalidate()
        // Poll quickly while waiting for the user to allow access, lazily afterwards (it can be revoked).
        let interval: TimeInterval = accessibilityTrusted ? 10 : 1
        trustTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        trustTimer?.tolerance = interval * 0.2
    }

    func refresh() {
        let rt = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let lp = ProcessInfo.processInfo.isLowPowerModeEnabled
        let trusted = AX.isTrusted
        let trustChanged = trusted != accessibilityTrusted
        guard rt != reduceTransparency || lp != lowPowerMode || trustChanged else { return }
        reduceTransparency = rt
        lowPowerMode = lp
        accessibilityTrusted = trusted
        if trustChanged { scheduleTrustPoll() }
        listeners.forEach { $0() }
    }
}

enum DevFlags {
    /// Debug builds only: shows the "needs Accessibility" states even when access is allowed (for screenshots).
    static var forceNeedsAccess: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "HushDevForceNeedsAccess")
        #else
        return false
        #endif
    }

    /// Debug builds only: lets Hush turn on without Accessibility (focus then comes from the window list alone).
    static var skipAccessibilityCheck: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "HushDevSkipAXCheck")
        #else
        return false
        #endif
    }
}

/// The Output console in Settings › Debug.
@MainActor @Observable
final class DebugLog {
    static let shared = DebugLog()

    struct Line: Identifiable, Equatable {
        let id: Int
        let time: String
        let text: String
    }

    private(set) var lines: [Line] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func log(_ text: String) {
        let time = formatter.string(from: Date())
        var new: [Line] = []
        for (i, part) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            new.append(Line(id: nextID, time: i == 0 ? time : "", text: String(part)))
            nextID += 1
        }
        lines.append(contentsOf: new)
        if lines.count > 600 { lines.removeFirst(lines.count - 500) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["HUSH_LOG_STDOUT"] != nil {
            print("[\(time)] \(text)")
            fflush(stdout)
        }
        #endif
    }

    func clear() { lines.removeAll() }

    var plainText: String {
        lines.map { ($0.time.isEmpty ? String(repeating: " ", count: 8) : $0.time) + "  " + $0.text }
            .joined(separator: "\n")
    }
}
