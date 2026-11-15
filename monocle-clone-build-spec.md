# Hush — Build Spec for a Monocle-Style Focus Overlay on macOS

*A personal-use clone of Monocle ("noise-cancelling for your screen"). Codename **Hush**; rename it freely. Research is current to Monocle v3.5.1, checked 15 November 2026.*

---

## 0. How to use this document

The file has two halves. Sections 1–2 are research and product definition: what Monocle actually does (each feature marked as confirmed, seen in the video, unverified or contradicted) and what your clone should do, in priority order. Sections 3–8 are the engineering plan: the core rendering trick, the module layout, Swift code for every hard part, pitfalls, a test matrix, milestones with exit criteria, and prompts you can hand to an AI coding assistant. If you build with Claude Code or Cursor, put this file at the repo root as `SPEC.md` and work one milestone at a time (Section 7).

Two caveats. The Swift snippets are starting points written for macOS 14+ in Swift 5 language mode; they have not been compiled, so expect small fixes. Everything marked ⚠️ relies on private Apple APIs that can change between macOS releases, which is why Milestone 0 proves those pieces on your own machine before anything is built on top of them.

A word on the original: Monocle is a paid indie app by Dominik Kandravý. Building your own version to learn from and use yourself is fine; give it its own name, icon and wording, and don't distribute a look-alike.

---

## 1. Research findings

### 1.1 What Monocle is

Monocle is a native, menu-bar-only macOS utility that blurs, tints, grains and/or desaturates everything except the window you're working in. You toggle it with a cursor shake, a global shortcut or a menu bar click. Nothing is closed, hidden or rearranged; it's purely a visual layer over the desktop. Its developer is a product designer who built it with AI tools and no prior coding background, restarting three times before 1.0. That's a useful signal for you: the difficulty is in knowing which macOS mechanisms to use, not in the amount of code.

### 1.2 Release timeline

| Version | Released | What changed (paraphrased from release notes) |
|---|---|---|
| 1.0 | 23 Feb 2025 | Initial release: menu bar toggle with Ambient (gradient) and Deep (full) modes |
| 1.1–1.1.2 | Mar–May 2025 | Store page by now lists Shift-click mode switching, a global shortcut, multi-display support and app-specific rules; changelog adds an excluded-app indicator on the menu bar icon, simplified Settings, experimental overlay-opacity and fade-timing sliders, fix for blur failing when desktop icons are hidden |
| 2.0 | 8 Oct 2025 | Smooth window-to-window transitions, Settings redesigned for macOS 26 Tahoe, license reset |
| 3.0 | 8 Dec 2025 | Rebuilt from scratch; custom blur intensity obtained by hacking `NSVisualEffectView`; shake to toggle; grayscale and tints (presets or system accent); URL-scheme automation; Homebrew cask |
| 3.0.1–3.0.3 | Dec 2025–Jan 2026 | Developer named a shake-sensitivity fix as the first 3.0.1 item; 3.0.3 removed the experimental before/after GIF feature |
| 3.5 | 18 May 2026 | App Groups, automatic Stage Manager support, multi-monitor blur fix (including with "Displays have separate Spaces" off), Corner Peek, Cursor Reveal effect, Blur-Free mode, smoother Dock/menu bar auto-hide, new scripting commands |
| 3.5.1 | 19 May 2026 | Current version; the expanded Raycast extension (June 2026) requires it |

The store listing gives macOS 14.6 as the minimum. At 3.0 the price was a 7-day trial, then a one-time $9 for one Mac or $20 for three.

### 1.3 Feature inventory and verification status

Legend: ✅ confirmed by a first-party or official source · 🎥 shown in the Snazzy Labs demo (from your notes) · ❓ not found in any source · ⚠️ contradicted or outdated

| Feature | Status | Evidence and notes |
|---|---|---|
| Shake the cursor to toggle on/off | ✅ | 3.0 launch notes |
| Menu bar click toggles; Shift-click switches Ambient/Deep | ✅ | 1.x store page |
| Global keyboard shortcuts | ✅ / ❓ | Shortcuts exist and are configurable; the defaults in your notes (⌃⌥⌘F/M/E/C) could not be confirmed |
| Ambient (gradient) vs Deep (full-screen) modes | ✅ 🎥 | Raycast command descriptions; demo shows a bottom-to-top fade |
| Blur intensity 0–100 | ✅ | Raycast "Set Blur" |
| Blur-Free mode (tint, grain and mono only) | ✅ | 3.5 notes |
| Tint presets, match system accent, custom hex, opacity 0–100 | ✅ | 3.0 notes and Raycast |
| Film grain 0–100 | ✅ | Raycast |
| Monochrome on/off plus intensity 0–100 | ✅ | Raycast |
| Single-window vs app-wide focus | ✅ 🎥 | Raycast "Toggle App-Wide Focus" |
| App Groups (apps that share focus) | ✅ | 3.5 notes |
| Ignore list ("exclude current app"); overlay fades out while an ignored app is frontmost | ✅ 🎥 | Raycast and demo |
| Crossfade and transition timing | ✅ 🎥 | 1.x slider, 2.0 transitions, demo |
| Auto-hide Dock and menu bar while active | ✅ 🎥 | Demo, plus the 3.5 polish note |
| Stage Manager handling | ✅ / ⚠️ | 3.5 keeps the Stage Manager strip **visible** beside the focused app. Your notes say Monocle blurs the thumbnails, which contradicts the release notes |
| Per-screen vs global display mode | ✅ | Raycast: each screen independent vs anchored to one screen |
| Corner Peek (flick the cursor into a screen corner) | ✅ | 3.5 notes |
| Cursor Reveal (overlay fans out from the cursor) | ✅ | 3.5 notes |
| URL scheme for Shell, AppleScript and Shortcuts | ✅ | 3.0 notes |
| Raycast extension with 26 commands | ✅ | Third-party extension by Emilio Sánchez, with the developer listed as a contributor |
| `brew install --cask monocle-app` | ✅ | 3.0 notes |
| Shift + shake to peek | ❓ | No source found; the official peek is Corner Peek |
| Shake sensitivity slider and modifier keys | ❓ | Sensitivity work is confirmed; the exact controls are not |
| Drag-and-drop auto-hide | ❓ | No source found |
| Swipe to dismiss Settings | ❓ | No source found |
| Before/after GIF generator | ⚠️ | Existed as an experiment and was removed in 3.0.3 |
| Auto-toggle with macOS Focus modes | — | The developer tried it, found it unreliable and shelved it |

Treat the ❓ items as your own design choices. Several are good ideas and show up in this spec as P2 features.

### 1.4 What we know about how Monocle is built

A binary analysis on Desktop Insights describes a native Swift app, a roughly 13 MB universal binary, Developer ID signed, notarized and hardened, with Sparkle detected (medium confidence) for updates. Its entitlement list includes keys for the App Sandbox, Apple Events automation plus a temporary Apple Events exception, a read-only shared-preference exception, mach-lookup and SBPL exceptions, and file-access exceptions. Two inferences, not confirmed facts: Apple Events are there to tell System Events to auto-hide the Dock and menu bar, and the shared-preference exception lets a sandboxed app read system preference domains such as Stage Manager state.

The rendering clues are stronger. The developer says custom blur intensity came from hacking `NSVisualEffectView`, which offers no public radius control, and the download page warns that with Reduce Transparency switched on you get a gray overlay instead of a blur. Both point to the window server's own backdrop blur, the machinery behind `NSVisualEffectView`, rather than screen capture. A backdrop approach needs no Screen Recording permission, and it's the one this spec takes.

For performance, the developer reports about 1.8% CPU on an M3 with blur on and idle, 0% while inactive, and higher usage during window switches because the blur is genuinely re-rendered.

### 1.5 Prior art worth reading

**OpenHaze** (MIT; Swift and AppKit, about 1,700 lines) is an open-source HazeOver recreation that uses exactly the core trick in this spec: click-through full-screen overlay windows inserted directly beneath the focused window with `NSWindow.order(.below, relativeTo:)`, two overlays per display that crossfade, and focus changes taken from Accessibility events with a cheap window-list poll as a drift corrector. It dims rather than blurs; replace its overlay content with the backdrop view in §4.4 and you have most of a Monocle. Read its `macos/` folder before writing code.

**Blurred** by Dwarves Foundation (MIT, Swift) is an older dimmer and a handy reference for menu bar slider UX. **HazeOver** (commercial) is the classic window dimmer and the behavioral reference for this whole category.

For the custom blur: Oskar Groth's write-up on reverse-engineering `NSVisualEffectView` (cited in the Luminare library, whose `VisualEffectView` sets `filters.gaussianBlur.inputRadius` on the internal backdrop layer); the "DIY NSVisualEffectView" gists that drive a `CABackdropLayer` with `gaussianBlur` and `colorSaturate` filters; and the private `CGSSetWindowBackgroundBlurRadius` call that iTerm2 and Alacritty use for window background blur.

---

## 2. Product spec for Hush

### 2.1 Problem, goals, non-goals

On a large display, every window you aren't using competes for attention. Hush keeps the focused window crisp and quiets everything else with blur, tint, grain and desaturation, without closing, moving or hiding anything, and gets out of the way the moment you ask.

Goals:

1. Toggling feels instant: the overlay starts animating within 50 ms of a shake, hotkey or click.
2. The window you switch to is never blurred for more than one frame; the window you left blurs over the crossfade (0.3 s by default).
3. It's cheap: Hush itself sits at about 0% CPU when off and under 1% when on and idle, with WindowServer overhead in the same range Monocle reports (about 2% on Apple silicon).
4. It never leaves the Mac modified: Dock and menu bar auto-hide settings are always restored, including after a crash or force-quit.
5. It's fully scriptable: every toggle and setting is reachable from a URL.

Non-goals for this version: licensing, trials and payments; App Store distribution and the sandbox (they complicate private APIs and Apple Events for no gain in a personal build); screen-capture-based effects (heavier, and they need Screen Recording permission); automatic switching with macOS Focus modes (Monocle's own developer shelved it as unreliable); Windows or Linux.

### 2.2 Requirements

P0 is the MVP, P1 brings parity with Monocle, P2 is polish and extras.

| ID | Pri | Requirement | Acceptance (abbreviated Given/When/Then) |
|---|---|---|---|
| R1 | P0 | Toggle the overlay from a menu bar click and a global hotkey, with a fade | Toggling fades the overlay over the crossfade duration; the menu bar icon reflects the state |
| R2 | P0 | Deep mode: blur everything behind the focused window | The focused window, menus, Dock, menu bar and floating panels stay sharp; other windows, desktop icons and wallpaper are blurred; clicks still reach blurred windows |
| R3 | P0 | Focus tracking with crossfade | Clicking a blurred window makes it sharp immediately while the previous one blurs over the crossfade; Cmd-` between windows of one app retargets |
| R4 | P0 | Live blur slider, 0–100 | Dragging the slider changes the blur in real time without flicker |
| R5 | P0 | Ignore list | When an ignored app becomes frontmost the overlay fades out, and it returns when a non-ignored app is frontmost |
| R6 | P0 | One overlay pair per display | Every display is covered; plugging or unplugging a display while on leaves no stray overlays |
| R7 | P0 | Hush's own windows never become the target | Opening the panel or Settings keeps the previously focused window sharp |
| R8 | P0 | Accessibility onboarding | First launch explains and requests Accessibility; the overlay won't turn on until trusted and says why |
| R9 | P1 | Ambient mode | Blur is strongest at the bottom edge and fades to nothing at a configurable height |
| R10 | P1 | Tint (off, presets, accent, hex; opacity), grain, monochrome (toggle and intensity), blur-free | Every control is live; blur 0 with mono off renders a plain dimmer with no backdrop cost |
| R11 | P1 | Shake to toggle | A deliberate shake toggles reliably on mouse and trackpad; ordinary pointing, scrolling and dragging never trigger it; sensitivity and an optional modifier are configurable |
| R12 | P1 | App-wide focus and App Groups | In app-wide mode, every visible part of the front app's windows stays sharp; grouped apps stay sharp together |
| R13 | P1 | Auto-hide Dock and menu bar while on | The originals come back on turn-off, on quit, and at the next launch after a crash |
| R14 | P1 | URL scheme and Shortcuts actions | Every command in §4.16 works via `open -g` without stealing focus |
| R15 | P1 | Per-screen vs global display mode | Per-screen: each display keeps its own top window sharp. Global: only the focused window is sharp and other displays are fully blurred |
| R16 | P1 | Menu bar behaviors and launch at login | Click toggles (or opens the panel, configurable), Shift-click switches mode, right-click or Control-click opens the panel |
| R17 | P1 | Desktop reveal | When the front app has no windows (for example after clicking the desktop) the overlay fades out; configurable |
| R18 | P2 | Corner Peek and hold-to-peek | Moving into a screen corner, or holding a chosen modifier for 250 ms, hides the overlay until you leave or release |
| R19 | P2 | Cursor Reveal transition | The overlay appears and disappears as a circle growing or shrinking from the cursor, continuous across displays |
| R20 | P2 | Stage Manager strip stays sharp | With Stage Manager on, the side strip is never blurred |
| R21 | P2 | Drag peek | During a file drag the overlay hides so drop targets are visible |
| R22 | P2 | Polish | Liquid Glass panel on macOS 26, optional Sparkle updates, Raycast script commands |
| R23 | P2 | Energy awareness | In Low Power Mode, cap the blur radius and shorten crossfades |

### 2.3 Settings model

| Key | Type | Range or values | Default | Notes |
|---|---|---|---|---|
| `mode` | enum | ambient, deep | deep | Monocle defaulted to Ambient; some users asked for Deep |
| `blur` | Double | 0–100 | 60 | 0 means blur-free |
| `monoEnabled`, `mono` | Bool, Double | 0–100 | false, 100 | Saturation is 1 − mono/100 while enabled |
| `grain` | Double | 0–100 | 15 | |
| `tintPreset` | enum | off, accent, graphite, blue, purple, pink, red, orange, yellow, green, custom | off | |
| `tintHex` | String | RRGGBB | 1E1E1E | Used when the preset is custom |
| `tintOpacity` | Double | 0–100 | 20 | |
| `scope` | enum | window, app | window | |
| `appGroups` | [[bundle ID]] | | empty | |
| `ignoredBundleIDs` | [bundle ID] | | Raycast, Alfred, Spotlight | Launchers would otherwise cause flicker |
| `displayMode` | enum | perScreen, global | perScreen | |
| `crossfade` | Double (seconds) | 0–1.0 | 0.3 | |
| `revealStyle` | enum | fade, cursor | fade | |
| `ambientCoverage` | Double | 0.2–1.0 | 0.6 | Fraction of screen height |
| `hideWhenNoWindow` | Bool | | true | Desktop reveal |
| `autoHideDock`, `autoHideMenuBar` | Bool | | false, false | |
| `shakeEnabled`, `shakeSensitivity`, `shakeModifiers` | Bool, Double, flags | 0–100 | true, 50, none | |
| `cornerPeek`, `holdToPeekModifiers` | Bool, flags | | true, none | |
| `menuBarClick` | enum | toggle, panel | toggle | |
| `launchAtLogin` | Bool | | true | Via `SMAppService` |

### 2.4 State machine

Hush is either `Off` or `On`. While `On`, two sub-states suppress drawing without switching Hush off. `Suspended` applies when the front app is ignored, or has no windows and desktop reveal is enabled. `Peeking` applies during a corner, hold or drag peek. Leaving either sub-state re-runs targeting and fades the overlay back in. Turning on requires Accessibility trust. Turning off removes the overlays from the screen entirely (ordered out, not merely transparent) so the window server stops compositing the backdrop, detaches observers, stops polling and restores the Dock and menu bar.

---

## 3. Architecture

### 3.1 The core trick

```
 z-order, front → back               what the user sees
 ────────────────────────────────    ──────────────────────────────────────
 menu bar, Dock, menus, popovers     sharp (higher window levels)
 focused window         (level 0)    sharp
 ▒▒▒▒ Hush overlay ▒▒▒▒ (level 0)    click-through; blurs whatever is behind it
 other app windows      (level 0)    blurred / tinted / grained / desaturated
 desktop icons, wallpaper            blurred
```

Each overlay is a borderless, transparent, click-through window the size of one display, living at the normal window level. Its content is a behind-window backdrop, so the window server blurs whatever is composited behind it. Ordering the overlay directly beneath the focused window with `order(.below, relativeTo: focusedWindowID)` keeps everything in front of it sharp (the focused window plus anything at a higher level) and applies the effect to everything behind it. Nothing is captured, so no Screen Recording permission is needed, and moving or resizing the focused window costs nothing because the overlay doesn't depend on its frame.

Two overlays per display make crossfades possible. When focus moves, the spare overlay is ordered under the new target at zero opacity and faded in while the old one fades out. The window you clicked is already sharp, because macOS raised it above the old overlay; the window you left blurs gradually as the new overlay fades in on top of it.

App-wide focus, App Groups and the Stage Manager strip need some windows *behind* the overlay to stay sharp. Those get "holes": a mask on the overlay with transparent regions over the visible parts of those windows (§4.6). Ambient mode uses the same mask with a vertical gradient.

### 3.2 Module layout

```
Hush/
├── App/
│   ├── HushApp.swift               @main, NSApplicationDelegateAdaptor
│   └── AppDelegate.swift           launch, URL opens, crash recovery, quit cleanup
├── Core/
│   ├── Settings.swift              HushSettings (Codable) + SettingsStore (@Observable)
│   ├── OverlayController.swift     on/off/peek state, retargeting, owns the OverlayPairs
│   ├── OverlayPair.swift           two OverlayWindows per display + crossfade
│   ├── OverlayWindow.swift         click-through borderless window
│   ├── OverlayContentView.swift    BackdropView + tint + grain, mask application
│   ├── BackdropView.swift          ⚠️ NSVisualEffectView backdrop tuning (radius, saturation)
│   ├── MaskBuilder.swift           ambient gradient + holes → CGImage
│   ├── WindowList.swift            CGWindowList snapshot, geometry helpers
│   ├── Planner.swift               which window each overlay sits under, plus holes
│   ├── AX.swift                    ⚠️ trust, focused window → CGWindowID
│   ├── FocusTracker.swift          NSWorkspace + AXObserver events
│   ├── ShakeDetector.swift
│   ├── PeekMonitor.swift           corner / hold-modifier / drag peeks
│   ├── SystemChrome.swift          Dock & menu bar auto-hide with safe restore
│   ├── StageManager.swift
│   ├── URLRouter.swift
│   └── Intents.swift               App Intents for Shortcuts
├── UI/
│   ├── StatusItemController.swift  NSStatusItem, click semantics, popover
│   ├── QuickPanel.swift            SwiftUI control-centre-style panel
│   └── SettingsView.swift          tabs: General, Appearance, Triggers, Apps, Displays, Automation, Debug
└── Resources/                      Info.plist, Hush.entitlements, Assets
```

### 3.3 Runtime flow

```
NSWorkspace: app activated / hidden / Space changed / wake ─┐
AXObserver: focused/main window changed, moved, resized… ───┼─► scheduleRetarget()  (coalesced to the next runloop turn)
3 Hz poll: cheap signature changed (drift corrector) ───────┘            │
Display reconfigured ──► rebuildScreens() ───────────────────────────────┤
                                                                          ▼
                                                    retarget()
                                                      frontmost app, ignoring Hush itself
                                                      ignored app? → Suspended (fade out)
                                                      WindowList.snapshot()            (~1 ms)
                                                      Planner → per display {target, holes, ambient}
                                                      OverlayPair.apply → reorder + crossfade, or mask refresh
```

### 3.4 Coordinates cheat sheet

AppKit (`NSScreen.frame`, `NSEvent.mouseLocation`, `NSWindow.frame`) puts the origin at the bottom-left of the primary display with y pointing up. The CoreGraphics window list (`kCGWindowBounds`) and Accessibility positions put it at the top-left of the primary display with y pointing down. The primary display is `NSScreen.screens[0]`. Convert CoreGraphics to AppKit with `y = primaryHeight − (cgY + height)`. Masks are drawn in screen-local AppKit coordinates, so subtract the screen's `frame.origin` as well.

---

## 4. Implementation guide

### 4.1 Project setup and app entry

Create a macOS App in Xcode (SwiftUI lifecycle, Swift), deployment target macOS 14.0, and set the Swift language mode to 5 for this target; AppKit callbacks produce a wall of Sendable diagnostics under Swift 6 strict concurrency that buys you nothing here. Add one Swift package, `https://github.com/sindresorhus/KeyboardShortcuts`, for user-recordable global hotkeys that need no extra permission. Sparkle is optional and only matters if you'll copy builds to other Macs.

Info.plist additions:

```xml
<key>LSUIElement</key><true/>   <!-- menu bar app: no Dock icon by default -->
<key>NSAppleEventsUsageDescription</key>
<string>Hush asks System Events to auto-hide the Dock and menu bar while focus is on.</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.yourname.hush</string>
    <key>CFBundleURLSchemes</key><array><string>hush</string></array>
  </dict>
</array>
```

Under Signing & Capabilities, remove App Sandbox and keep Hardened Runtime with "Apple Events" ticked (that adds `com.apple.security.automation.apple-events`). Sign with your Apple ID's development team rather than "Sign to Run Locally". An ad-hoc signature changes on every build, and macOS then quietly stops honoring the Accessibility permission you granted. If tracking stops working after a rebuild, run `tccutil reset Accessibility com.yourname.hush` and grant it again.

```swift
import SwiftUI

@main
struct HushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }   // Hush manages its own windows
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let shake = ShakeDetector()
    private let peek = PeekMonitor()

    func applicationDidFinishLaunching(_ note: Notification) {
        SystemChrome.restoreIfNeeded()                     // crash recovery for Dock / menu bar
        if !AX.isTrusted { AX.requestTrust() }

        let overlay = OverlayController.shared
        let store = SettingsStore.shared
        statusItem = StatusItemController(overlay: overlay, store: store)
        Hotkeys.register(overlay: overlay)

        shake.onShake = { _ in overlay.toggle() }
        peek.onPeek = { overlay.setPeeking($0) }
        apply(store.value)
        store.onChange = { [weak self] settings in
            overlay.settingsChanged()
            self?.apply(settings)
        }
    }

    private var lastTriggers: [String] = []

    private func apply(_ s: HushSettings) {
        // Only restart monitors when trigger settings change, not on every blur-slider tick.
        let triggers = ["\(s.shakeEnabled)", "\(s.shakeSensitivity)", "\(s.shakeModifiers)",
                        "\(s.cornerPeek)", "\(s.holdToPeekModifiers)"]
        guard triggers != lastTriggers else { return }
        lastTriggers = triggers
        shake.tuning = .from(sensitivity: s.shakeSensitivity)
        shake.requiredModifiers = NSEvent.ModifierFlags(rawValue: s.shakeModifiers)
        s.shakeEnabled ? shake.start() : shake.stop()
        peek.cornerEnabled = s.cornerPeek
        peek.holdModifiers = NSEvent.ModifierFlags(rawValue: s.holdToPeekModifiers)
        peek.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { URLRouter.handle($0) }
    }

    func applicationWillTerminate(_ note: Notification) {
        OverlayController.shared.turnOff(animated: false)
        SystemChrome.restoreIfNeeded(sync: true)
    }
}
```

### 4.2 Settings model and store

```swift
import AppKit
import Observation

enum FocusMode: String, Codable, CaseIterable {
    case ambient, deep
    mutating func toggle() { self = (self == .ambient) ? .deep : .ambient }
}
enum FocusScope: String, Codable, CaseIterable { case window, app }
enum DisplayMode: String, Codable, CaseIterable { case perScreen, global }
enum TintPreset: String, Codable, CaseIterable {
    case off, accent, graphite, blue, purple, pink, red, orange, yellow, green, custom
}
enum RevealStyle: String, Codable, CaseIterable { case fade, cursor }
enum MenuBarClick: String, Codable, CaseIterable { case toggle, panel }

struct HushSettings: Codable, Equatable {
    var mode: FocusMode = .deep
    var blur = 60.0
    var monoEnabled = false
    var mono = 100.0
    var grain = 15.0
    var tintPreset: TintPreset = .off
    var tintHex = "1E1E1E"
    var tintOpacity = 20.0
    var scope: FocusScope = .window
    var appGroups: [[String]] = []
    var ignoredBundleIDs = ["com.raycast.macos", "com.runningwithcrayons.Alfred", "com.apple.Spotlight"]
    var displayMode: DisplayMode = .perScreen
    var crossfade = 0.3
    var revealStyle: RevealStyle = .fade
    var ambientCoverage = 0.6
    var hideWhenNoWindow = true
    var autoHideDock = false
    var autoHideMenuBar = false
    var shakeEnabled = true
    var shakeSensitivity = 50.0
    var shakeModifiers: UInt = 0            // NSEvent.ModifierFlags.rawValue
    var cornerPeek = true
    var holdToPeekModifiers: UInt = 0
    var menuBarClick: MenuBarClick = .toggle
    var launchAtLogin = true
    // Synthesized Decodable throws on missing keys, so adding a field later would reset everything.
    // Before you ship to yourself twice, write init(from:) with decodeIfPresent for each key.
}

extension HushSettings {
    /// PIDs of running apps that share an App Group with `bundleID` (empty if it isn't grouped).
    func groupPIDs(for bundleID: String) -> Set<pid_t> {
        guard let group = appGroups.first(where: { $0.contains(bundleID) }) else { return [] }
        return Set(NSWorkspace.shared.runningApplications
            .filter { group.contains($0.bundleIdentifier ?? "") }
            .map(\.processIdentifier))
    }
}

@MainActor @Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var value: HushSettings {
        didSet {
            guard value != oldValue else { return }
            onChange?(value)
            scheduleSave()
        }
    }
    @ObservationIgnored var onChange: ((HushSettings) -> Void)?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    private init() {
        let data = UserDefaults.standard.data(forKey: "settings")
        value = data.flatMap { try? JSONDecoder().decode(HushSettings.self, from: $0) } ?? HushSettings()
    }

    /// Slider drags fire dozens of changes per second; write to disk once they settle.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = value
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: "settings")
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
```

### 4.3 Overlay window

```swift
import AppKit

/// Full-display, click-through, borderless window at the normal level.
/// It is re-ordered directly beneath the focused window; it never takes focus.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true            // clicks fall through to the window underneath
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .normal                      // same level as app windows, so z-ordering works
        // .transient hides it in Mission Control; try .stationary if you prefer it to stay put.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        alphaValue = 0
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

Leave `sharingType` at its default. Overlays then appear in screen shares and recordings, which is exactly what people use Monocle for during calls and tutorials.

### 4.4 The backdrop: blur and saturation ⚠️

This is the part Monocle's developer describes as taking almost a year, and it's the only piece of the core that needs private API. There are three ways to get a behind-window blur with an adjustable radius. Prototype Path A first and keep B and C as fallbacks.

**Path A: tune `NSVisualEffectView`'s internal backdrop (recommended; it matches Monocle's own description).** Use a `.behindWindow` visual effect view as the overlay's content. Internally it hosts a private `CABackdropLayer` whose `filters` include a Gaussian blur and usually a saturation filter. Find that layer and set `filters.gaussianBlur.inputRadius` and `filters.colorSaturate.inputAmount` by key path. Saturation 0 gives you Monochrome for free, rendered by the window server, and a near-zero radius with saturation below 1 gives you Blur-Free plus Monochrome.

```swift
import AppKit
import QuartzCore

/// ⚠️ Private-API territory: CABackdropLayer + CAFilter key paths. Re-verify on every macOS release.
final class BackdropView: NSVisualEffectView {
    var blurRadius: CGFloat = 24 { didSet { applyFilters() } }
    var saturation: CGFloat = 1  { didSet { applyFilters() } }    // 1 = normal colour, 0 = grayscale

    override init(frame: NSRect) {
        super.init(frame: frame)
        blendingMode = .behindWindow      // sample the windows behind this window
        material = .fullScreenUI          // also try .hudWindow and .underWindowBackground
        state = .active                   // the overlay is never key; don't let it render "inactive"
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.applyFilters() }   // layers exist only once attached
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        DispatchQueue.main.async { [weak self] in self?.applyFilters() }   // AppKit may rebuild its filters
    }

    /// Also call after wake, display changes and turning the overlay on (AppKit can rebuild the tree).
    func applyFilters() {
        guard let backdrop = Self.findBackdrop(in: layer) else { return }
        let names = Self.filterNames(of: backdrop)          // unknown key paths raise ObjC exceptions: check first
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if names.contains("gaussianBlur") {
            backdrop.setValue(max(blurRadius, 0.01), forKeyPath: "filters.gaussianBlur.inputRadius")
        }
        if names.contains("colorSaturate") {
            backdrop.setValue(saturation, forKeyPath: "filters.colorSaturate.inputAmount")
        } else if saturation < 0.999, let saturate = PrivateCA.filter("colorSaturate") {
            saturate.setValue(saturation, forKey: "inputAmount")
            backdrop.filters = (backdrop.filters ?? []) + [saturate]
        }
        CATransaction.commit()
    }

    static func findBackdrop(in layer: CALayer?) -> CALayer? {
        guard let layer else { return nil }
        if NSStringFromClass(type(of: layer)) == "CABackdropLayer" { return layer }
        for sub in layer.sublayers ?? [] {
            if let hit = findBackdrop(in: sub) { return hit }
        }
        return nil
    }

    static func filterNames(of layer: CALayer) -> Set<String> {
        Set((layer.filters as? [NSObject] ?? []).compactMap { $0.value(forKey: "name") as? String })
    }
}

enum PrivateCA {
    /// Creates a private CAFilter such as "gaussianBlur" or "colorSaturate"; nil if unavailable.
    static func filter(_ type: String) -> NSObject? {
        guard let cls: AnyClass = NSClassFromString("CAFilter") else { return nil }
        let made = (cls as AnyObject).perform(NSSelectorFromString("filterWithType:"), with: type)
        return made?.takeUnretainedValue() as? NSObject
    }
}

#if DEBUG
/// Run once per macOS version and read the output before trusting any layer or filter names.
func dumpLayerTree(_ layer: CALayer, depth: Int = 0) {
    let filters = BackdropView.filterNames(of: layer).sorted()
    print(String(repeating: "  ", count: depth)
          + "\(NSStringFromClass(type(of: layer))) name=\(layer.name ?? "–") filters=\(filters)")
    layer.sublayers?.forEach { dumpLayerTree($0, depth: depth + 1) }
}
#endif
```

The material still contributes its own tint layers on top of the blur. If the result looks too milky or too dark, use the dump to identify the material's non-backdrop sublayers on your macOS version and hide them (match on what the dump shows rather than hard-coding names), then supply your own tint (§4.5).

**Path B: own the `CABackdropLayer`.** Same private class, but you create and configure it yourself, which gives you full control of the filter chain and a `scale` knob that renders the backdrop at reduced resolution (cheap, and indistinguishable at large radii). The host view needs `wantsLayer = true` and `layerUsesCoreImageFilters = false`, and the layer must be window-server aware or nothing shows.

```swift
/// ⚠️ Sketch. Verify every property name with dumpLayerTree / runtime checks first.
func makeBackdropLayer(radius: CGFloat, saturation: CGFloat) -> CALayer? {
    guard let cls = NSClassFromString("CABackdropLayer") as? NSObject.Type,
          let backdrop = cls.init() as? CALayer,
          let blur = PrivateCA.filter("gaussianBlur"),
          let saturate = PrivateCA.filter("colorSaturate") else { return nil }
    backdrop.setValue(true, forKey: "windowServerAware")
    blur.setValue(radius, forKey: "inputRadius")
    blur.setValue(true, forKey: "inputNormalizeEdges")        // avoids dark fringes at screen edges
    saturate.setValue(saturation, forKey: "inputAmount")
    backdrop.filters = [blur, saturate]
    backdrop.setValue(0.5, forKey: "scale")                   // half-resolution backdrop: cheaper
    return backdrop
}
```

**Path C: `CGSSetWindowBackgroundBlurRadius`.** The private CoreGraphics Services call iTerm2 and Alacritty use. It blurs whatever sits behind a transparent window, with no `NSVisualEffectView` involved. It only blurs, so Monochrome isn't available on this path, and tint and grain come from §4.5 as usual.

```swift
import Darwin

/// ⚠️ Private CGS call, resolved at runtime so a missing symbol can't crash the app.
enum CGSBlur {
    private typealias ConnectionFn = @convention(c) () -> UInt32
    private typealias BlurFn = @convention(c) (UInt32, UInt32, UInt32) -> Int32
    private static let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    private static let connection: ConnectionFn? =
        dlsym(handle, "CGSDefaultConnectionForThread").map { unsafeBitCast($0, to: ConnectionFn.self) }
    private static let setBlur: BlurFn? =
        dlsym(handle, "CGSSetWindowBackgroundBlurRadius").map { unsafeBitCast($0, to: BlurFn.self) }

    /// Clamped to 1…64: other projects report that 0 can disable blur on a window until it is recreated,
    /// and that very large radii misbehave.
    static func set(_ window: NSWindow, radius: Int) {
        guard let connection, let setBlur else { return }
        _ = setBlur(connection(), UInt32(window.windowNumber), UInt32(min(max(radius, 1), 64)))
    }
}
```

Slider mapping (a perceptual curve keeps the low end subtle and lets the top end get heavy quickly):

```swift
enum EffectMath {
    static func blurRadius(_ v: Double) -> CGFloat { CGFloat(pow(v / 100, 1.4) * 60) }       // 0…60 pt
    static func saturation(monoOn: Bool, mono: Double) -> CGFloat { monoOn ? CGFloat(1 - mono / 100) : 1 }
    static func tintAlpha(_ v: Double) -> Float { Float(v / 100 * 0.55) }
    static func grainAlpha(_ v: Double) -> Float { Float(v / 100 * 0.35) }
}
```

**Reduce Transparency.** With Accessibility › Display › Reduce Transparency on, every backdrop path renders a flat gray slab. Check `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`, observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter`, and when it's on, hide the backdrop, raise the tint to a dark dimmer (around 40% black) and show a one-line hint in the panel.

### 4.5 Tint and grain

Tint and grain are ordinary layers stacked above the backdrop inside the same overlay window, so they're cheap and need no private API.

```swift
import AppKit

/// Plain layer-backed view used for the tint and grain layers.
final class LayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var allowsVibrancy: Bool { false }
}

/// Content of one overlay window: backdrop (blur + saturation) → tint → grain.
final class OverlayContentView: NSView {
    let backdrop = BackdropView()
    let tint = LayerView()
    let grain = LayerView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for view in [backdrop, tint, grain] as [NSView] {
            view.frame = bounds
            addSubview(view)
        }
        grain.layer?.magnificationFilter = .nearest
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ s: HushSettings, screenSize: CGSize) {
        backdrop.isHidden = s.blur < 0.5 && !s.monoEnabled     // blur-free without mono: no backdrop cost at all
        backdrop.blurRadius = EffectMath.blurRadius(s.blur)
        backdrop.saturation = EffectMath.saturation(monoOn: s.monoEnabled, mono: s.mono)
        tint.layer?.backgroundColor = s.resolvedTint.cgColor
        tint.layer?.opacity = s.tintPreset == .off ? 0 : EffectMath.tintAlpha(s.tintOpacity)
        grain.layer?.contents = GrainTexture.image(for: screenSize)
        grain.layer?.opacity = EffectMath.grainAlpha(s.grain)
    }
}

extension HushSettings {
    var resolvedTint: NSColor {
        switch tintPreset {
        case .off:      return .clear
        case .accent:   return .controlAccentColor   // re-apply on NSColor.systemColorsDidChangeNotification
        case .graphite: return .systemGray
        case .blue:     return .systemBlue
        case .purple:   return .systemPurple
        case .pink:     return .systemPink
        case .red:      return .systemRed
        case .orange:   return .systemOrange
        case .yellow:   return .systemYellow
        case .green:    return .systemGreen
        case .custom:   return NSColor(hex: tintHex) ?? .black
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

enum GrainTexture {
    private static var cache: [String: CGImage] = [:]

    /// Display-sized grain at 1× (grain doesn't need Retina), tiled from a 256×256 noise tile.
    /// Cached per size and shared by both overlays on a display.
    static func image(for size: CGSize) -> CGImage? {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let hit = cache[key] { return hit }
        guard size.width >= 1, size.height >= 1, let tile = makeTile(),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: tile.width, height: tile.height), byTiling: true)
        let image = ctx.makeImage()
        cache[key] = image
        return image
    }

    /// Black and white specks with random alpha read as film grain under normal blending.
    private static func makeTile(size: Int = 256) -> CGImage? {
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let alpha = UInt8.random(in: 0...96)
            let value: UInt8 = Bool.random() ? alpha : 0          // premultiplied white, or black
            px[i] = value; px[i + 1] = value; px[i + 2] = value; px[i + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
```

If full-display grain images cost too much memory on a 6K display, swap in two nested `CAReplicatorLayer`s that repeat the 256×256 tile across x and y.

### 4.6 Masks: Ambient gradient and holes

One mask image per overlay carries both the Ambient gradient and any holes. White means "effect visible", transparent means "keep sharp". `NSVisualEffectView.maskImage` clips the backdrop; ordinary `CALayer` masks clip the tint and grain. Build masks at 1×: alpha masks don't need Retina resolution.

```swift
import AppKit

struct AmbientSpec: Equatable {
    var coverage: CGFloat          // fraction of screen height the gradient spans
    var fromBottom = true
}

enum MaskBuilder {
    /// Screen-local AppKit coordinates (origin bottom-left), which match CGContext's.
    static func make(size: CGSize, ambient: AmbientSpec?, holes: [CGRect],
                     cornerRadius: CGFloat = 10) -> CGImage? {
        let w = Int(size.width.rounded(.up)), h = Int(size.height.rounded(.up))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        if let ambient {
            let transparent = CGColor(red: 1, green: 1, blue: 1, alpha: 0)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [white, transparent] as CFArray, locations: [0, 1])!
            let edge = ambient.fromBottom ? 0 : CGFloat(h)
            let stop = ambient.fromBottom ? CGFloat(h) * ambient.coverage : CGFloat(h) * (1 - ambient.coverage)
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: edge), end: CGPoint(x: 0, y: stop), options: [])
        } else {
            ctx.setFillColor(white)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        if !holes.isEmpty {
            ctx.setBlendMode(.clear)
            for r in holes {
                // Rounded holes match window corners. Fragments from occlusion get rounded too,
                // which leaves tiny blurred notches; refine later if they bother you.
                let radius = min(cornerRadius, r.width / 2, r.height / 2)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            ctx.fillPath()
        }
        return ctx.makeImage()
    }
}

extension OverlayContentView {
    func applyMask(_ image: CGImage?) {
        backdrop.maskImage = image.map { NSImage(cgImage: $0, size: bounds.size) }
        for view in [tint, grain] {
            guard let image else { view.layer?.mask = nil; continue }
            let mask = CALayer()
            mask.frame = view.bounds
            mask.contents = image
            view.layer?.mask = mask
        }
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
```

Spike this early: confirm that `maskImage` with partial alpha (the gradient) and with holes clips the behind-window blur the way you expect on your macOS version.

### 4.7 Window list, Accessibility and planning

The window list gives z-order, owners and frames for every on-screen window without Screen Recording permission (only window *titles* need that, and Hush never reads them). Accessibility adds the precise focused window.

```swift
import AppKit
import ApplicationServices

struct WinInfo: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let layer: Int
    let cgFrame: CGRect                          // CoreGraphics global coordinates (top-left origin)
    var frame: CGRect { Geometry.toAppKit(cgFrame) }
}

enum Geometry {
    /// Height of the primary display, NSScreen.screens[0], whose frame origin is (0, 0).
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAppKit(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The screen showing the largest part of a rect (AppKit coordinates).
    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

enum WindowList {
    /// Front-to-back list of on-screen windows, excluding Hush's own.
    static func snapshot() -> [WinInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { d -> WinInfo? in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let layer = d[kCGWindowLayer as String] as? Int,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  (d[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }
            return WinInfo(id: id, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "",
                           layer: layer, cgFrame: rect)
        }
    }

    /// Normal app windows that can be a focus target.
    static func isCandidate(_ w: WinInfo) -> Bool {
        w.layer == 0 && w.cgFrame.width >= 80 && w.cgFrame.height >= 60
    }
}

// ⚠️ Private but long-lived and widely used (AltTab, yabai): AXUIElement → CGWindowID.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// CGWindowID of the app's focused window, when Accessibility can tell us.
    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)          // a hung app must never stall Hush
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(value as! AXUIElement, &id) == .success ? id : nil
    }
}
```

The planner turns a snapshot into one `ScreenPlan` per display: which window the overlay sits under, which holes to cut, and whether it's visible at all.

```swift
struct ScreenPlan: Equatable {
    var visible = true
    var targetID: CGWindowID?       // overlay goes directly below this window; nil = cover every window
    var holes: [CGRect] = []        // screen-local AppKit rects kept sharp
    var ambient: AmbientSpec?
}

enum Planner {
    /// Windows that stay sharp besides the target: the front app's other windows (app-wide scope),
    /// grouped apps' windows, and the Stage Manager strip.
    static func clearIDs(snapshot: [WinInfo], frontPID: pid_t, groupPIDs: Set<pid_t>,
                         scope: FocusScope, stageManager: Bool) -> Set<CGWindowID> {
        let candidates = snapshot.filter(WindowList.isCandidate)
        var ids = Set<CGWindowID>()
        for pid in groupPIDs.union([frontPID]) {
            let mine = candidates.filter { $0.pid == pid }
            if scope == .app { ids.formUnion(mine.map(\.id)) }
            else if let top = mine.first { ids.insert(top.id) }
        }
        if stageManager {
            // Verify the owner name with a snapshot dump while Stage Manager is on.
            ids.formUnion(snapshot.filter { $0.owner == "WindowManager" }.map(\.id))
        }
        return ids
    }

    static func plan(snapshot snap: [WinInfo], frontPID: pid_t, focusedID: CGWindowID?,
                     clear: Set<CGWindowID>, settings s: HushSettings) -> [CGDirectDisplayID: ScreenPlan] {
        let candidates = snap.filter(WindowList.isCandidate)
        var focus = candidates.first { $0.id == focusedID && $0.pid == frontPID }
                 ?? candidates.first { $0.pid == frontPID }
        if let f = focus { focus = parentIfSheet(f, in: candidates) }
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
        let start = target.flatMap { t in snap.firstIndex(of: t).map { $0 + 1 } } ?? 0
        let behind = snap[start...].filter { $0.layer == 0 }
        var rects: [CGRect] = []
        for (k, w) in behind.enumerated() where clear.contains(w.id) {
            let occluders = behind.prefix(k).filter { !clear.contains($0.id) }.map(\.frame)
            rects += RectMath.subtract(w.frame, all: occluders)
        }
        return rects.compactMap { r in
            let c = r.intersection(screen.frame)
            return (c.isNull || c.isEmpty) ? nil : c.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        }
    }

    /// Sheets are separate windows stacked just above their parent. Targeting the sheet would blur
    /// the parent, so target the parent instead (heuristic: same app, next window down, contains it).
    private static func parentIfSheet(_ t: WinInfo, in candidates: [WinInfo]) -> WinInfo {
        guard let i = candidates.firstIndex(of: t),
              let parent = candidates[(i + 1)...].first(where: { $0.pid == t.pid }),
              parent.cgFrame.insetBy(dx: -2, dy: -2).contains(t.cgFrame) else { return t }
        return parent
    }
}
```

### 4.8 Focus tracking

Events give low latency; the 3 Hz poll in §4.9 catches whatever they miss. Re-attach the Accessibility observer each time a different app becomes frontmost.

```swift
import AppKit
import ApplicationServices

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
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.onChange?() }
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
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
```

Moves and resizes only matter when there are holes (app-wide scope, groups, Stage Manager); otherwise the overlay doesn't care where the focused window is. Window-closed events registered on the application element are unreliable, which is one reason the poll exists.

### 4.9 Overlay controller and crossfade

`OverlayPair` owns the two windows for one display and performs the crossfade. A generation counter stops a late animation-completion handler from ordering out a window that a newer transition is fading back in.

```swift
import AppKit

@MainActor
final class OverlayPair {
    let screen: NSScreen
    private let windows: [OverlayWindow]
    private var active = 0
    private var plan: ScreenPlan?
    private var generation = 0

    init(screen: NSScreen) {
        self.screen = screen
        windows = (0..<2).map { _ in
            let window = OverlayWindow(screen: screen)
            window.contentView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
            return window
        }
    }

    private var current: OverlayWindow { windows[active] }
    private var spare: OverlayWindow { windows[1 - active] }
    private func content(_ w: OverlayWindow) -> OverlayContentView { w.contentView as! OverlayContentView }

    func configure(_ s: HushSettings) {
        windows.forEach { content($0).apply(s, screenSize: screen.frame.size) }
    }

    func apply(_ new: ScreenPlan, duration: TimeInterval) {
        guard new.visible else { hide(duration: duration); return }
        let old = plan
        plan = new

        // Same target and already showing: at most the mask changed (moves, resizes, holes).
        if let old, old.targetID == new.targetID, current.isVisible {
            if old.holes != new.holes || old.ambient != new.ambient {
                content(current).applyMask(mask(for: new))
            }
            return
        }

        // New target: slide the spare overlay under it and crossfade.
        let incoming = spare, outgoing = current
        content(incoming).applyMask(mask(for: new))
        incoming.alphaValue = 0
        if let id = new.targetID {
            incoming.order(.below, relativeTo: Int(id))
        } else {
            incoming.orderFrontRegardless()            // nothing to keep sharp on this display
        }
        active = 1 - active
        generation += 1
        let gen = generation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if self.generation == gen { outgoing.orderOut(nil) }   // stop compositing its backdrop
            }
        }
    }

    func hide(duration: TimeInterval) {
        plan = nil
        generation += 1
        let gen = generation
        let all = windows
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            all.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                if self.generation == gen { all.forEach { $0.orderOut(nil) } }
            }
        }
    }

    func tearDown() { windows.forEach { $0.orderOut(nil) } }

    private func mask(for p: ScreenPlan) -> CGImage? {
        guard !p.holes.isEmpty || p.ambient != nil else { return nil }
        return MaskBuilder.make(size: screen.frame.size, ambient: p.ambient, holes: p.holes)
    }
}
```

`OverlayController` owns state, observers and the per-display pairs. It's `@Observable` so the panel can bind to `isOn`.

```swift
import AppKit
import Observation

@MainActor @Observable
final class OverlayController {
    static let shared = OverlayController()

    private(set) var isOn = false
    private(set) var isPeeking = false

    private let store = SettingsStore.shared
    @ObservationIgnored private var pairs: [CGDirectDisplayID: OverlayPair] = [:]
    private let tracker = FocusTracker()
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var lastExternalPID: pid_t?
    @ObservationIgnored private var lastSignature = ""
    @ObservationIgnored private var retargetQueued = false
    private let myPID = ProcessInfo.processInfo.processIdentifier

    private var s: HushSettings { store.value }

    // MARK: On / off / peek

    func toggle() { isOn ? turnOff() : turnOn() }

    func turnOn() {
        guard !isOn else { return }
        guard AX.isTrusted else { AX.requestTrust(); return }      // also surface a message in the panel
        isOn = true
        rebuildScreens()
        tracker.start(onChange: { [weak self] in self?.scheduleRetarget() },
                      onScreensChanged: { [weak self] in self?.rebuildScreens(); self?.scheduleRetarget() })
        poll = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retargetIfDrifted() }
        }
        poll?.tolerance = 0.1
        SystemChrome.hide(dock: s.autoHideDock, menuBar: s.autoHideMenuBar)
        retarget()
    }

    func turnOff(animated: Bool = true) {
        guard isOn else { return }
        isOn = false
        isPeeking = false
        tracker.stop()
        poll?.invalidate()
        poll = nil
        pairs.values.forEach { $0.hide(duration: animated ? s.crossfade : 0) }
        SystemChrome.restoreIfNeeded()
    }

    func setPeeking(_ peeking: Bool) {
        guard isOn, peeking != isPeeking else { return }
        isPeeking = peeking
        if peeking { pairs.values.forEach { $0.hide(duration: 0.15) } } else { retarget() }
    }

    func settingsChanged() {
        pairs.values.forEach { $0.configure(s) }
        if isOn { retarget() }
    }

    /// nil toggles. Used by the hotkey, the panel button and hush://app/…
    func setFrontAppExcluded(_ excluded: Bool?) {
        guard let pid = externalFrontPID(),
              let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return }
        let isExcluded = store.value.ignoredBundleIDs.contains(id)
        let want = excluded ?? !isExcluded
        if want && !isExcluded { store.value.ignoredBundleIDs.append(id) }
        if !want { store.value.ignoredBundleIDs.removeAll { $0 == id } }
    }

    // MARK: Targeting

    func scheduleRetarget() {
        guard !retargetQueued else { return }
        retargetQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retargetQueued = false
            self.retarget()
        }
    }

    private func retarget() {
        guard isOn, !isPeeking, let pid = externalFrontPID() else { return }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        if s.ignoredBundleIDs.contains(bundleID) {                     // Suspended
            pairs.values.forEach { $0.hide(duration: s.crossfade) }
            return
        }
        let snap = WindowList.snapshot()
        let clear = Planner.clearIDs(snapshot: snap, frontPID: pid, groupPIDs: s.groupPIDs(for: bundleID),
                                     scope: s.scope, stageManager: StageManager.isEnabled)
        let plans = Planner.plan(snapshot: snap, frontPID: pid, focusedID: AX.focusedWindowID(pid: pid),
                                 clear: clear, settings: s)
        for (displayID, plan) in plans { pairs[displayID]?.apply(plan, duration: s.crossfade) }
        lastSignature = signature(snap, pid)
    }

    /// Cheap drift check: catches new windows, reorders and moves the event stream missed.
    private func retargetIfDrifted() {
        guard isOn, !isPeeking, let pid = externalFrontPID() else { return }
        if signature(WindowList.snapshot(), pid) != lastSignature { retarget() }
    }

    private func signature(_ snap: [WinInfo], _ pid: pid_t) -> String {
        "\(pid)|" + snap.filter { $0.layer == 0 }.prefix(24).map {
            "\($0.id):\(Int($0.cgFrame.minX)),\(Int($0.cgFrame.minY)),\(Int($0.cgFrame.width)),\(Int($0.cgFrame.height))"
        }.joined(separator: ";")
    }

    /// Hush's own popover, Settings and URL handling must never become the focus target.
    func externalFrontPID() -> pid_t? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myPID {
            lastExternalPID = front.processIdentifier
        }
        return lastExternalPID
    }

    // MARK: Displays

    func rebuildScreens() {
        let screens = Dictionary(NSScreen.screens.map { (Geometry.displayID(of: $0), $0) },
                                 uniquingKeysWith: { first, _ in first })
        for (id, pair) in pairs where screens[id]?.frame != pair.screen.frame {
            pair.tearDown()
            pairs[id] = nil
        }
        for (id, screen) in screens where pairs[id] == nil {
            let pair = OverlayPair(screen: screen)
            pair.configure(s)
            pairs[id] = pair
        }
    }
}
```

While a window is being dragged in app-wide mode, `retarget` runs on every move event and rebuilds that display's mask. If you see CPU spikes, throttle mask rebuilds to about 30 per second with a trailing update, or build masks at half resolution.

### 4.10 Shake detection

Count horizontal direction reversals within a short window, ignoring wiggles shorter than a minimum travel distance. Use the event's raw `deltaX`, which keeps reporting motion even when the cursor is pinned against a screen edge. Only `mouseMoved` is monitored, so drags never trigger it.

```swift
import AppKit

@MainActor
final class ShakeDetector {
    struct Tuning {
        var window: TimeInterval        // reversals must happen within this span
        var minReversals: Int
        var minSegment: CGFloat         // points of travel before a direction change counts

        /// 0 = hard to trigger, 100 = very easy.
        static func from(sensitivity v: Double) -> Tuning {
            let t = max(0, min(1, v / 100))
            return Tuning(window: 0.45 + 0.35 * t, minReversals: t > 0.66 ? 3 : 4, minSegment: CGFloat(70 - 45 * t))
        }
    }

    var tuning = Tuning.from(sensitivity: 50)
    var requiredModifiers: NSEvent.ModifierFlags = []
    var cooldown: TimeInterval = 0.8
    var onShake: ((NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var lastSign: CGFloat = 0
    private var segment: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var lastFire: TimeInterval = 0

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
    }

    private func feed(_ e: NSEvent) {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        if !requiredModifiers.isEmpty, e.modifierFlags.intersection(relevant) != requiredModifiers { return }
        let dx = e.deltaX
        guard abs(dx) >= 1 else { return }
        let sign: CGFloat = dx > 0 ? 1 : -1
        if sign == lastSign || lastSign == 0 {
            segment += abs(dx)
        } else {
            if segment >= tuning.minSegment { reversals.append(e.timestamp) }
            segment = abs(dx)
        }
        lastSign = sign
        reversals.removeAll { e.timestamp - $0 > tuning.window }
        if reversals.count >= tuning.minReversals, e.timestamp - lastFire > cooldown {
            lastFire = e.timestamp
            reversals.removeAll()
            onShake?(NSEvent.mouseLocation)
        }
    }
}
```

Tune with real hardware: log reversal counts and segment lengths for ten minutes of normal work on both a mouse and a trackpad, then pick defaults that never fired. macOS's own "Shake mouse pointer to locate" (Accessibility › Display › Pointer) will still enlarge the cursor during a shake; both behaviors fire, which is harmless.

### 4.11 Peeking and the cursor reveal

Peeks temporarily hide the overlay without turning Hush off. The corner peek is the confirmed Monocle feature; hold-to-peek (OpenHaze has an Fn-to-reveal equivalent) and drag peek are extras.

```swift
import AppKit

@MainActor
final class PeekMonitor {
    var onPeek: ((Bool) -> Void)?
    var cornerEnabled = true
    var holdModifiers: NSEvent.ModifierFlags = []

    private var monitors: [Any] = []
    private var inCorner = false, holding = false, dragging = false
    private var holdTimer: Timer?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    func start() {
        stop()
        let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCorner(NSEvent.mouseLocation) }
        }
        let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            MainActor.assumeIsolated { self?.checkHold(e.modifierFlags) }       // key-type events need AX trust
        }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            MainActor.assumeIsolated { self?.checkDrag(e) }
        }
        monitors = [moved, flags, drag].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private var isPeeking: Bool { inCorner || holding || dragging }

    private func update(_ change: () -> Void) {
        let before = isPeeking
        change()
        if isPeeking != before { onPeek?(isPeeking) }
    }

    private func checkCorner(_ p: NSPoint) {
        guard cornerEnabled else { return }
        let zone: CGFloat = 3
        let hit = NSScreen.screens.contains { screen in
            let f = screen.frame
            guard f.insetBy(dx: -1, dy: -1).contains(p) else { return false }
            let nearX = p.x <= f.minX + zone || p.x >= f.maxX - zone
            let nearY = p.y <= f.minY + zone || p.y >= f.maxY - zone
            return nearX && nearY      // refinement: ignore corners where another display continues
        }
        update { inCorner = hit }
    }

    private func checkHold(_ flags: NSEvent.ModifierFlags) {
        guard !holdModifiers.isEmpty else { return }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        holdTimer?.invalidate()
        if flags.intersection(relevant) == holdModifiers {
            // Wait 250 ms so ordinary shortcuts that use the same modifiers don't flash the overlay.
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.update { self?.holding = true } }
            }
        } else {
            update { holding = false }
        }
    }

    private func checkDrag(_ e: NSEvent) {
        if e.type == .leftMouseUp { update { dragging = false }; return }
        let count = NSPasteboard(name: .drag).changeCount
        if count != dragChangeCount {           // a new drag session wrote to the drag pasteboard
            dragChangeCount = count
            update { dragging = true }
        }
    }
}
```

Corner Peek collides with any Hot Corners the user has configured in System Settings › Desktop & Dock, so either skip those corners or require a short dwell. The drag-pasteboard trick for detecting file drags is worth a quick test before you rely on it.

**Cursor Reveal (P2).** Compute the largest distance from the cursor to any corner of any display. To show, grow a radial mask from zero to that radius over about 450 ms; to hide, shrink it. Drive the frames with a display link (`NSView.displayLink(target:selector:)` on macOS 14) and render each frame's mask at quarter resolution per display, with the circle centered on the cursor converted into that display's local coordinates. The center can sit outside a display, which is what makes the wave travel continuously from one monitor to the next. Combine it with the plan's own mask (multiply alphas). If stepping `maskImage` at 60 fps proves too costly, animate a `CAShapeLayer` mask on the tint and grain layers and fall back to a plain fade for the blur.

### 4.12 Dock and menu bar auto-hide

Apple Events to System Events toggle the same switches as System Settings, with no `killall Dock`. Save the user's original state before changing anything, and restore it on turn-off, on quit and at launch, so a crash can never leave the Dock hidden.

```swift
import Foundation

enum SystemChrome {
    private static let queue = DispatchQueue(label: "hush.system-chrome")
    private static let savedKey = "savedChromeState"      // persisted, so it survives crashes

    static func hide(dock: Bool, menuBar: Bool) {
        guard dock || menuBar else { return }
        queue.async {
            let defaults = UserDefaults.standard
            if defaults.dictionary(forKey: savedKey) == nil {          // remember the ORIGINAL state only once
                defaults.set(["dock": run("get autohide of dock preferences") == "true",
                              "menuBar": run("get autohide menu bar of dock preferences") == "true"],
                             forKey: savedKey)
            }
            if dock { run("set autohide of dock preferences to true") }
            if menuBar { run("set autohide menu bar of dock preferences to true") }
        }
    }

    /// On turn-off, on quit (sync: true) and at launch (crash recovery).
    static func restoreIfNeeded(sync: Bool = false) {
        let work = {
            let defaults = UserDefaults.standard
            guard let saved = defaults.dictionary(forKey: savedKey) as? [String: Bool] else { return }
            run("set autohide of dock preferences to \(saved["dock"] ?? false)")
            run("set autohide menu bar of dock preferences to \(saved["menuBar"] ?? false)")
            defaults.removeObject(forKey: savedKey)
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// osascript off the main thread: System Events can take 100+ ms to answer.
    @discardableResult
    private static func run(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to \(command)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

The first call triggers macOS's Automation prompt ("Hush wants to control System Events"). Test on macOS 26 specifically; at least one user has reported trouble reading the menu bar setting this way on Tahoe.

### 4.13 Stage Manager

```swift
import Foundation

enum StageManager {
    static var isEnabled: Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool) ?? false
    }
}
```

When it's on, the planner treats the strip's windows as "clear", so they become holes (§4.7). Before relying on the owner-name check, dump `WindowList.snapshot()` with Stage Manager enabled and confirm which process owns the strip and at which layer it sits. If the strip turns out to live above level 0, it's already sharp and you can drop the special case.

### 4.14 Menu bar item, quick panel and Settings

Use an `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because you need to tell plain clicks, Shift-clicks and right-clicks apart.

```swift
import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let overlay: OverlayController
    private let store: SettingsStore

    init(overlay: OverlayController, store: SettingsStore) {
        self.overlay = overlay
        self.store = store
        super.init()
        item.button?.image = NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: "Hush")
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuickPanel(store: store, overlay: overlay))
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) { togglePanel(); return }
        if event.modifierFlags.contains(.shift) { store.value.mode.toggle(); return }
        if store.value.menuBarClick == .toggle { overlay.toggle() } else { togglePanel() }
    }

    func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate()                       // lets the panel's controls take focus
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Call whenever isOn or the front app's exclusion state changes.
    func refreshIcon(isOn: Bool, frontAppExcluded: Bool) {
        let symbol = frontAppExcluded ? "eye.slash" : "eyeglasses"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hush")
        item.button?.appearsDisabled = !isOn
    }
}

struct QuickPanel: View {
    @Bindable var store: SettingsStore
    var overlay: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Focus", isOn: Binding(get: { overlay.isOn },
                                          set: { $0 ? overlay.turnOn() : overlay.turnOff() }))
                .toggleStyle(.switch)
                .font(.headline)
            Picker("Mode", selection: $store.value.mode) {
                Text("Ambient").tag(FocusMode.ambient)
                Text("Deep").tag(FocusMode.deep)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LabeledContent("Blur") { Slider(value: $store.value.blur, in: 0...100) }
            LabeledContent("Grain") { Slider(value: $store.value.grain, in: 0...100) }
            Toggle("Monochrome", isOn: $store.value.monoEnabled)
            if store.value.monoEnabled { Slider(value: $store.value.mono, in: 0...100) }
            Picker("Tint", selection: $store.value.tintPreset) {
                ForEach(TintPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            LabeledContent("Tint strength") { Slider(value: $store.value.tintOpacity, in: 0...100) }
            Picker("Keep sharp", selection: $store.value.scope) {
                Text("Window").tag(FocusScope.window)
                Text("Whole app").tag(FocusScope.app)
            }
            .pickerStyle(.segmented)
            Divider()
            HStack {
                Button("Exclude this app") { overlay.setFrontAppExcluded(nil) }
                Spacer()
                Button("Settings…") { SettingsWindow.shared.show() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Plain NSWindow hosting SwiftUI; switches the app to a regular app (Dock icon, menu) while open.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: .shared)))
            w.title = "Hush Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

`SettingsView` tabs, for you to fill in:

| Tab | Contents |
|---|---|
| General | Launch at login, menu bar click action, desktop reveal, auto-hide Dock and menu bar |
| Appearance | Mode, Ambient coverage, blur, monochrome, tint (presets, accent, hex well), tint strength, grain, crossfade, reveal style, live preview note |
| Triggers | Shake on/off, sensitivity, required modifier; Corner Peek; hold-to-peek modifier; `KeyboardShortcuts.Recorder` rows |
| Apps | Ignore list with "+" (pick a running app or an `.app` bundle); App Groups editor |
| Displays | Per-screen vs global |
| Automation | Every URL from §4.16 with copy buttons; Raycast script command template |
| Debug | Accessibility status, Reduce Transparency status, "dump layer tree", "dump window list", private-API path in use |

On macOS 26 you can give the panel the Liquid Glass look through the new glass effect APIs, with materials as the fallback on 14 and 15.

### 4.15 Hotkeys and launch at login

```swift
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    // These defaults come from your notes; Monocle's real defaults are unconfirmed. Change freely.
    static let toggleOverlay = Self("toggleOverlay", default: .init(.f, modifiers: [.control, .option, .command]))
    static let toggleMode    = Self("toggleMode",    default: .init(.m, modifiers: [.control, .option, .command]))
    static let toggleExclude = Self("toggleExclude", default: .init(.e, modifiers: [.control, .option, .command]))
    static let showPanel     = Self("showPanel",     default: .init(.c, modifiers: [.control, .option, .command]))
}

@MainActor
enum Hotkeys {
    static func register(overlay: OverlayController) {
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { overlay.toggle() }
        KeyboardShortcuts.onKeyUp(for: .toggleMode) { SettingsStore.shared.value.mode.toggle() }
        KeyboardShortcuts.onKeyUp(for: .toggleExclude) { overlay.setFrontAppExcluded(nil) }
        // .showPanel → StatusItemController.togglePanel()
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item update failed: \(error)")
        }
    }
}
```

### 4.16 Automation

A URL scheme covers Shell, AppleScript, Shortcuts ("Open URLs") and Raycast in one go. The command set mirrors what Monocle's Raycast extension exposes.

| URL | Effect |
|---|---|
| `hush://overlay/on`, `/off`, `/toggle` | Overlay state |
| `hush://mode/ambient`, `/deep`, `/toggle` | Focus mode |
| `hush://app/exclude`, `/include`, `/toggle` | Ignore list, for the current frontmost app |
| `hush://mono/on`, `/off`, `/toggle` | Monochrome |
| `hush://appwide/on`, `/off`, `/toggle` | Window vs app-wide scope |
| `hush://display/per-screen`, `/global` | Multi-display mode |
| `hush://set?blur=70&grain=20&mono=50&tintOpacity=30` | Numeric settings, each 0–100 |
| `hush://set?tint=4A90E2` or `hush://set?tintPreset=accent` | Tint colour |
| `hush://settings`, `hush://quit` | Open Settings, quit |

```swift
import AppKit

@MainActor
enum URLRouter {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "hush" else { return }
        let overlay = OverlayController.shared
        let store = SettingsStore.shared
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        let noun = parts.first ?? ""
        let verb = parts.count > 1 ? parts[1] : "toggle"
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                                   .map { ($0.name.lowercased(), $0.value ?? "") },
                               uniquingKeysWith: { _, last in last })
        func percent(_ key: String) -> Double? { query[key].flatMap { Double($0) }.map { min(max($0, 0), 100) } }
        func onOff(_ current: Bool) -> Bool { verb == "on" ? true : verb == "off" ? false : !current }

        switch noun {
        case "overlay":
            if onOff(overlay.isOn) { overlay.turnOn() } else { overlay.turnOff() }
        case "mode":
            switch verb {
            case "ambient": store.value.mode = .ambient
            case "deep":    store.value.mode = .deep
            default:        store.value.mode.toggle()
            }
        case "app":
            overlay.setFrontAppExcluded(verb == "exclude" ? true : verb == "include" ? false : nil)
        case "mono":
            store.value.monoEnabled = onOff(store.value.monoEnabled)
        case "appwide":
            store.value.scope = onOff(store.value.scope == .app) ? .app : .window
        case "display":
            store.value.displayMode = (verb == "global") ? .global : .perScreen
        case "set":
            if let v = percent("blur")        { store.value.blur = v }
            if let v = percent("grain")       { store.value.grain = v }
            if let v = percent("mono")        { store.value.mono = v; store.value.monoEnabled = v > 0 }
            if let v = percent("tintopacity") { store.value.tintOpacity = v }
            if let hex = query["tint"], NSColor(hex: hex) != nil {
                store.value.tintHex = hex.uppercased()
                store.value.tintPreset = .custom
            }
            if let preset = query["tintpreset"].flatMap({ TintPreset(rawValue: $0) }) {
                store.value.tintPreset = preset
            }
        case "settings":
            SettingsWindow.shared.show()
        case "quit":
            NSApp.terminate(nil)
        default:
            NSSound.beep()
        }
    }
}
```

Native Shortcuts actions via App Intents (nicer than "Open URLs" because they take typed parameters):

```swift
import AppIntents

struct ToggleFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Hush"

    @MainActor
    func perform() async throws -> some IntentResult {
        OverlayController.shared.toggle()
        return .result()
    }
}

struct SetBlurIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Hush Blur"
    @Parameter(title: "Blur", inclusiveRange: (0, 100)) var amount: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        SettingsStore.shared.value.blur = Double(amount)
        return .result()
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleFocusIntent(), phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle Hush", systemImageName: "eyeglasses")
    }
}
```

Shell, AppleScript and Raycast:

```bash
open -g "hush://overlay/toggle"            # -g keeps Hush from coming to the front
open -g "hush://set?blur=70&mono=40"
osascript -e 'do shell script "open -g hush://mode/toggle"'
```

```bash
#!/bin/bash
# Raycast script command: save as hush-toggle.sh in your Raycast script commands folder.
# @raycast.schemaVersion 1
# @raycast.title Hush: Toggle Focus
# @raycast.mode silent
# @raycast.icon 👓
open -g "hush://overlay/toggle"
```

---

## 5. Pitfalls and edge cases

| Issue | What you'll see | Fix |
|---|---|---|
| Hush's own UI becomes frontmost | The focused window blurs when you open the panel, Settings, or run a URL command | Remember the last external PID (§4.9); use `open -g` for URLs |
| Ad-hoc code signing | Accessibility shows as granted, but nothing tracks after a rebuild | Sign with a development team; `tccutil reset Accessibility <bundle id>` |
| Reduce Transparency on | A gray slab instead of blur | Detect it, show a hint, fall back to a tint-only dimmer (§4.4) |
| `NSVisualEffectView` rebuilds its filters | Blur radius snaps back after a Light/Dark switch, wake or display change | Re-apply on appearance change, wake, screen change, and about 0.5 s after turning on |
| Effect view renders "inactive" | Flat material, no blur | `state = .active`; the overlay is never key |
| Unknown key path on a private layer | Instant crash (Objective-C exception) | Check filter names before every key-path write (§4.4) |
| Sheets and dialogs | The parent window blurs when a Save sheet opens | Parent-if-sheet heuristic (§4.7) |
| Floating windows (picture-in-picture, utility panels) | They stay sharp | Expected: they live above level 0, and only level-0 windows are targets |
| Launchers (Raycast, Alfred, Spotlight) | Flicker when you invoke them | Keep them in the default ignore list |
| Front app has no windows, or you click the desktop | Everything blurred, nothing sharp | Desktop reveal (`hideWhenNoWindow`) |
| Display plugged, unplugged or resized | Overlay wrong size or on the wrong display | Rebuild pairs on `didChangeScreenParametersNotification` and on wake |
| "Displays have separate Spaces" off | Only one display blurs (Monocle's own bug until 3.5) | One overlay per display, sized to that display, joined to all Spaces; test it explicitly |
| Full-screen apps and Mission Control | Overlay visible in Mission Control or odd in full-screen Spaces | Compare `.transient` and `.stationary`; skip retargeting when the front window is full-screen |
| Hung target app | Hush freezes for seconds | `AXUIElementSetMessagingTimeout(app, 0.2)`; no AX calls in loops on the main thread |
| Desktop icons hidden | Blur fails or looks wrong (a real Monocle 1.x bug) | Test with Finder desktop icons hidden |
| Dock left hidden after a crash | Dock stays hidden after Hush dies | Saved original state plus restore at launch (§4.12) |
| User changes Dock settings while Hush is on | Their change is reverted on turn-off | Accept it, or only restore keys whose current value is still what Hush set |
| Corner Peek vs Hot Corners | Mission Control or Quick Note fires while peeking | Avoid corners used by Hot Corners, or require a dwell |
| Slider drags | Stutter while dragging Blur | Only update layer properties during the drag; debounce mask rebuilds and saves |
| Mask rebuilds during window drags (holes) | CPU spikes while dragging windows | Throttle to about 30 Hz; build masks at 1× or 0.5× |
| App Nap while off | Shake or hotkeys feel sluggish after long idle | If you notice it, set `NSAppSleepDisabled` to YES in Info.plist |
| macOS update changes private APIs | Blur radius stops responding | Keep Paths A, B and C behind one protocol with runtime capability checks, and fall back to dimming |

---

## 6. Test plan

### 6.1 Manual test matrix

| # | Scenario | Expected |
|---|---|---|
| 1 | Click between windows of two apps on one display | The clicked window is sharp at once; the previous one blurs over the crossfade |
| 2 | Cmd-` between windows of one app | Retargets to the new window |
| 3 | Cmd-Tab to Finder with no windows open | Overlay fades out (desktop reveal) |
| 4 | Open a Save sheet in TextEdit | Parent window and sheet both sharp |
| 5 | Invoke Raycast or Spotlight | No flicker |
| 6 | Click a blurred window | It activates and becomes sharp; the click reaches it |
| 7 | App-wide scope; two TextEdit windows with Safari between them | Visible parts of both TextEdit windows sharp, Safari blurred |
| 8 | App Group of Safari and Notes | Both sharp while either is active |
| 9 | Ambient mode | Blur strongest at the bottom, fading out at the coverage height |
| 10 | Mono 100, blur 0 | Background in grayscale and sharp; active window in colour |
| 11 | Blur 0, mono off, tint 40 | Classic dimmer; Hush CPU near 0% |
| 12 | Two displays, per-screen mode | Each display's top window sharp |
| 13 | Two displays, global mode | Only the focused window sharp; the other display fully blurred |
| 14 | "Displays have separate Spaces" off | Both displays behave as in 12 and 13 |
| 15 | Unplug the external display while on | Overlays rebuilt, nothing left behind |
| 16 | Sleep and wake | Overlay back, with the correct blur radius |
| 17 | Switch Light ↔ Dark while on | Blur radius and saturation persist |
| 18 | Reduce Transparency on | Hint shown, dimmer fallback used |
| 19 | Stage Manager on | Strip stays sharp |
| 20 | Full-screen app, then Mission Control | No artifacts |
| 21 | Share your screen in a call, or record with QuickTime | Viewers see the overlay (desired) |
| 22 | Auto-hide Dock on, `kill -9` Hush, relaunch | Dock restored |
| 23 | Shake while dragging a file | No toggle |
| 24 | Ten minutes of normal mouse and trackpad use at sensitivity 50 | No accidental toggles; deliberate shakes always work |
| 25 | Every URL in §4.16 via `open -g` | Correct effect, no focus stolen |

### 6.2 Performance budget

Measure in Activity Monitor (the CPU and Energy tabs for both Hush and WindowServer) with the overlay off, on and idle, and during rapid window switching; use Instruments' Animation Hitches and Time Profiler templates for anything that stutters. Targets: Hush at 0% when off, under 1% on and idle, no hitches during crossfades on your main display. As a yardstick, Monocle's developer reports about 1.8% CPU on an M3 with blur on and idle. When off, the overlays must be ordered out, not merely transparent, and the poll timer and Accessibility observer must be stopped.

---

## 7. Milestones

**M0 — Spikes (one or two evenings, throwaway target).** Exit by choosing backdrop Path A, B or C.
- [ ] An overlay window ordered below TextEdit's window stays below it while you click around, and clicks pass through
- [ ] Find the backdrop layer, print the layer tree, change the blur radius live from 0 to 60, and set saturation to 0 for grayscale
- [ ] Settings survive (or are re-applied after) a Light/Dark switch and sleep/wake
- [ ] `maskImage` with a gradient and a rectangular hole clips the blur as expected
- [ ] With Reduce Transparency on, you can detect it and fall back

**M1 — MVP (R1–R8).** Exit: a full workday of use without the focused window ever getting stuck blurred.
- [ ] Menu bar toggle and hotkey with fades
- [ ] FocusTracker, Planner (single target), OverlayPair crossfade, 3 Hz drift poll
- [ ] Ignore list with launcher defaults and "exclude this app"
- [ ] One pair per display, rebuilt on display changes
- [ ] Self-PID guard; Accessibility onboarding

**M2 — Visual system (R9, R10).** Tint presets, accent and hex; grain; monochrome; blur-free; Ambient gradient; the quick panel.

**M3 — Triggers and app chrome (R11, R16).** Shake with sensitivity and modifier; Shift-click and right-click; launch at login; Settings window.

**M4 — Window rules (R12, R17).** App-wide holes, App Groups editor, desktop reveal.

**M5 — Multi-display (R15).** Per-screen and global modes; test with "Displays have separate Spaces" both on and off.

**M6 — Desktop chrome (R13).** Dock and menu bar auto-hide with crash-safe restore.

**M7 — Automation (R14).** URL router, App Intents, Raycast script commands.

**M8 — Polish (R18–R23).** Peeks, Cursor Reveal, Stage Manager strip, Liquid Glass panel, Low Power Mode behavior.

---

## 8. Prompts for an AI coding assistant

Paste these one at a time with `SPEC.md` in the repo. Each prompt is scoped to one milestone so the assistant doesn't wander.

1. "Read SPEC.md §3 and §4.1–4.4. Create a throwaway macOS target `HushSpike` that completes the M0 checklist in §7: one overlay window ordered beneath TextEdit's frontmost window, a BackdropView with live blur and saturation sliders in a small control window, and a button that prints `dumpLayerTree`. Don't build anything else. Then tell me what the layer dump shows."
2. "Using the module layout in §3.2 and the code in §4.1–4.9 (effects can stay at their defaults until M2), implement milestone M1 in the `Hush` target. Fix compile errors as you go, keep private APIs confined to `BackdropView.swift` and `AX.swift`, and finish by listing which rows of the §6.1 test matrix I should run by hand."
3. "Implement M2 from §4.5–4.6 and the quick panel in §4.14. Make slider drags update layer properties only, and debounce mask rebuilds."
4. "Implement M3: the ShakeDetector (§4.10), status item click semantics and the Settings window (§4.14), hotkeys and login item (§4.15). Add a debug log of shake reversal counts that I can switch on from the Debug tab."
5. "Implement M4 and M5 (§4.7 planner holes, App Groups editor, per-screen and global modes). Add a Debug button that dumps the window list with owner, layer and frame."
6. "Implement M6 (§4.12) with crash-safe restore, then M7 (§4.16 URL router, App Intents, Raycast script)."
7. "Implement the M8 items one at a time, starting with Corner Peek; spike Cursor Reveal before integrating it."

---

## 9. Sources

Monocle (first-party and listings)
- Monocle 3.5 release post (App Groups, Stage Manager, Corner Peek, Cursor Reveal, Blur-Free, CPU figures): https://www.producthunt.com/p/monocle-clear-workspace-clear-mind/monocle-3-5-for-macos
- Monocle 3.0 release post (rebuild, NSVisualEffectView hack, shake, grayscale and tints, URL schemes, Homebrew, pricing): https://www.producthunt.com/p/monocle-clear-workspace-clear-mind/monocle-3-0-for-macos
- Monocle 2.0 post: https://www.producthunt.com/p/monocle-clear-workspace-clear-mind/monocle-2-0-for-macos
- Original launch thread: https://www.producthunt.com/p/monocle-clear-workspace-clear-mind/monocle-6
- Store page and changelog (Shift-click, 1.x fixes, 3.0.3 GIF removal, Reduce Transparency note, macOS 14.6+): https://iamdk.gumroad.com/l/monocle-elegant-macos-window-blur-focus
- Binary analysis (Swift, Sparkle, entitlements, release dates): https://desktopinsights.com/apps/monocle
- Raycast extension and its full command list: https://www.raycast.com/emlez/monocle
- Tom's Guide hands-on: https://www.tomsguide.com/computing/this-mac-app-made-me-realize-how-easily-distracted-i-am-and-helped-me-combat-it
- Snazzy Labs, "Your Mac Is Missing All of These" (Monocle segment from 22:37): https://www.youtube.com/watch?v=npxlJdxSv4A

Techniques and prior art
- OpenHaze (overlay-below-focused-window technique, crossfading pairs, AX + poll): https://github.com/jay739/openhaze
- Blurred by Dwarves Foundation: https://github.com/dwarvesf/blurred
- Apple, `NSWindow.order(_:relativeTo:)`: https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:)
- Luminare custom blur radius via the backdrop layer's filter key path: https://github.com/MrKai77/Luminare/pull/30
- Oskar Groth, reverse-engineering NSVisualEffectView: https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview
- DIY NSVisualEffectView with CABackdropLayer (blur radius and saturation key paths): https://gist.github.com/torarnv/8b915957196d1a88e6e2fa81c67be8cb
- CABackdropLayer notes (window-server awareness, filter chains): https://avaidyam.github.io/blog/2018/02/17/
- `CGSSetWindowBackgroundBlurRadius` usage and caveats: https://docs.rs/crate/par-term/latest/source/src/macos_blur.rs
- System Events dock preferences (Dock and menu bar auto-hide): https://github.com/JXA-Cookbook/JXA-Cookbook/wiki/System-Events
- Stage Manager defaults keys: https://gist.github.com/GreyAsteroid/c73028e447d716b02063b0870c12c6be
- KeyboardShortcuts package: https://github.com/sindresorhus/KeyboardShortcuts
