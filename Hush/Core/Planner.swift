import AppKit

struct ScreenPlan: Equatable {
    var visible = true
    var targetID: CGWindowID?       // overlay goes directly below this window; nil = cover every window
    var holes: [CGRect] = []        // screen-local AppKit rects kept sharp
    var ambient: AmbientSpec?
}

enum Planner {
    /// The window Hush keeps sharp: Accessibility's focused window when it belongs to the front app,
    /// otherwise the front app's top window. Sheets resolve to their parent.
    static func focusWindow(snapshot snap: [WinInfo], frontPID: pid_t, focusedID: CGWindowID?) -> WinInfo? {
        let candidates = snap.filter(WindowList.isCandidate)
        guard let f = candidates.first(where: { $0.id == focusedID && $0.pid == frontPID })
                ?? candidates.first(where: { $0.pid == frontPID }) else { return nil }
        return parentIfSheet(f, in: candidates)
    }

    /// Windows that stay sharp besides the target: the front app's other windows (app-wide scope),
    /// grouped apps' windows, and the Stage Manager strip.
    static func clearIDs(snapshot: [WinInfo], frontPID: pid_t, groupPIDs: Set<pid_t>,
                         scope: FocusScope, stageManager: Bool) -> Set<CGWindowID> {
        let candidates = snapshot.filter(WindowList.isCandidate)
        var ids = Set<CGWindowID>()
        for pid in groupPIDs.union([frontPID]) {
            let mine = candidates.filter { $0.pid == pid }
            if scope == .app {
                ids.formUnion(mine.map(\.id))                 // every visible window of the app
            } else if pid != frontPID, let top = mine.first {
                ids.insert(top.id)                            // a grouped app's top window
            }
            // In window scope the front app contributes only the target, which already sits above the overlay.
        }
        if stageManager {
            ids.formUnion(snapshot.filter { $0.owner == "WindowManager" && !$0.isOwn }.map(\.id))
        }
        return ids
    }

    static func plan(snapshot snap: [WinInfo], focus: WinInfo?, clear: Set<CGWindowID>,
                     settings s: HushSettings) -> [CGDirectDisplayID: ScreenPlan] {
        let candidates = snap.filter(WindowList.isCandidate)
        let ambient = s.mode == .ambient ? AmbientSpec(coverage: CGFloat(s.ambientCoverage)) : nil

        var plans: [CGDirectDisplayID: ScreenPlan] = [:]
        for screen in NSScreen.screens {
            let displayID = Geometry.displayID(of: screen)
            if focus == nil && s.hideWhenNoWindow {                 // desktop reveal
                plans[displayID] = ScreenPlan(visible: false)
                continue
            }
            let focusIsHere = focus.map { Geometry.screen(for: $0.frame) == screen } ?? false
            let target: WinInfo?
            switch s.displayMode {
            case .global:
                target = focus                                      // every overlay sits under the one focused window
            case .perScreen:
                target = focusIsHere ? focus                        // other screens keep their own top window
                       : candidates.first { Geometry.screen(for: $0.frame) == screen }
            }
            plans[displayID] = ScreenPlan(visible: true, targetID: target?.id,
                                          holes: holes(behind: target, in: snap, clear: clear, on: screen),
                                          ambient: ambient)
        }
        return plans
    }

    /// Visible parts of "clear" windows that sit behind the overlay on this screen.
    private static func holes(behind target: WinInfo?, in snap: [WinInfo],
                              clear: Set<CGWindowID>, on screen: NSScreen) -> [CGRect] {
        guard !clear.isEmpty else { return [] }
        let start = target.flatMap { t in snap.firstIndex { $0.id == t.id }.map { $0 + 1 } } ?? 0
        let behind = snap[start...].filter { $0.layer == 0 && !$0.isOwn }
        var rects: [CGRect] = []
        for (k, w) in behind.enumerated() where clear.contains(w.id) {
            let occluders = behind.prefix(k).filter { !clear.contains($0.id) }.map(\.frame)
            rects += RectMath.subtract(w.frame, all: occluders)
        }
        return rects.compactMap { r in
            let c = r.intersection(screen.frame)
            guard !c.isNull, c.width >= 2, c.height >= 2 else { return nil }
            return c.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        }
    }

    /// Sheets are separate windows stacked just above their parent. Targeting the sheet would blur the
    /// parent, so target the parent instead (heuristic: same app, next window down, contains it).
    private static func parentIfSheet(_ t: WinInfo, in candidates: [WinInfo]) -> WinInfo {
        guard let i = candidates.firstIndex(of: t),
              let parent = candidates[(i + 1)...].first(where: { $0.pid == t.pid }),
              parent.cgFrame.insetBy(dx: -2, dy: -2).contains(t.cgFrame),
              parent.cgFrame.width > t.cgFrame.width + 1 || parent.cgFrame.height > t.cgFrame.height + 1
        else { return t }
        return parent
    }
}
