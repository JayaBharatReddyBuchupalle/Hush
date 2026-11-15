# Hush

A personal, Monocle-style focus overlay for macOS. Hush keeps the window you're using sharp and quiets
everything else with blur, tint, film grain and black-and-white, without moving or hiding anything.
Built from `monocle-clone-build-spec.md` and the designs in `Hush — macOS Focus Overlay.pdf/.html`.

## Run it

- **Ready to run:** `build/Hush.app` (Release build, signed with your Apple Development certificate).
  Move it to `/Applications` before you turn on "Open Hush at login", since the login item points at the
  app's location.
- **From Xcode:** open `Hush.xcodeproj`, pick the **Hush** scheme, press Run.
- **From the terminal:**
  ```bash
  xcodebuild -project Hush.xcodeproj -scheme Hush -configuration Release -derivedDataPath build/DerivedData build
  open build/DerivedData/Build/Products/Release/Hush.app
  ```

Requires macOS 14 or later. Built and tested with Xcode 27.2 on macOS 27.2.

## First launch

1. Hush lives in the menu bar (no Dock icon). The onboarding window asks for **Accessibility** access, which
   Hush uses only to know which window is in front. Turn Hush on in System Settings › Privacy & Security ›
   Accessibility; the onboarding moves on by itself.
2. Turn Hush on with the switch in the panel, ⌃⌥⌘F, a side-to-side shake of the pointer, or a click on the
   menu bar icon (Shift-click switches Ambient/Deep, right-click opens the panel).
3. "Hide while Hush is on" (Dock/menu bar) asks for **Automation** access to System Events the first time.

The target signs manually with "Apple Development" (team 34BNGWA9DH), so the Accessibility grant survives
rebuilds. If you switch to "Sign to Run Locally", run `tccutil reset Accessibility com.jayabharat.hush` after
rebuilding and grant it again.

### Reduce Transparency is on on this Mac

Following the design, Hush **dims instead of blurring** while Reduce Transparency is on, and the panel says
so. Hush's blur engine still works with it on, so you can opt back in: click **Blur anyway** in the panel's
notice, or turn on Settings › Appearance › **Blur with Reduce Transparency on**.

## What's in it

Everything in the spec's P0, P1 and P2 lists:

- Deep and Ambient modes; blur 0–100 (0 = blur-free), grain, black and white with strength, 12 tints
  (including the design's Black, system accent and custom hex/colour well) with strength.
- Focus tracking with crossfades (Accessibility events plus a 3 Hz drift poll), sheet-aware targeting,
  z-order repair, desktop reveal, ignore list (launchers ignored by default), app-wide focus and App Groups
  (sharp "holes"), Stage Manager strip kept sharp, per-display or global multi-display modes.
- Triggers: a shake turns Hush on or off (one shake, one toggle, with or without Shift), with sensitivity
  and an optional modifier; opt-in Shift-shake to peek; corner peek (skips your Hot Corners), hold-a-key
  peek, peek while dragging files, four rebindable global shortcuts.
- Dock/menu bar auto-hide with crash-safe restore, Cursor Reveal ("From the pointer"), Low Power Mode
  behaviour, launch at login, `hush://` URL scheme, Shortcuts actions, Raycast script, Debug tools.

### Where it departs from the spec, and why

| Spec | Hush | Reason |
|---|---|---|
| Blur via tuned `NSVisualEffectView` (Path A) | Own `CABackdropLayer` (Path B) | On macOS 27 with Reduce Transparency on, `NSVisualEffectView` collapses to a flat fill; Path C (`CGSSetWindowBackgroundBlurRadius`) didn't blur at all |
| One mask on the overlay | A mask on each effect layer | A partial-alpha mask on a group containing the backdrop renders it offscreen and the blur vanishes |
| Cursor Reveal with an animated `CAShapeLayer` | Stepped quarter-resolution mask images | Changing a shape mask on a backdrop in a window ordered below another app's window stops the window drawing on macOS 27; swapping mask images works |
| Ambient as an alpha-faded blur | Private `variableBlur` (progressive blur) plus alpha fade | Smoother "rising" blur without the double-image look |
| `KeyboardShortcuts` package | Carbon `RegisterEventHotKey` plus a recorder styled like the design | No dependency, and the recorder matches the design |
| SwiftUI `MenuBarExtra`/popover | Non-activating panel styled like the design | The app you're using stays frontmost and sharp while you adjust things |

Small additions not in the design: the Reduce Transparency opt-in above, a "Peek while dragging files"
switch (spec R21), and a "No update feed" note on Check Now (there is no Sparkle feed for a personal build).

"Hold Shift and shake to peek" is **off by default** (the design has it on). With it on, a shake with Shift
held only hid Hush until Shift was released, which read as the shake not working. Now any shake turns Hush
on or off; switch peeking back on in Settings › Triggers if you want it. Saved settings from earlier builds
are migrated once.

## Automation

```bash
open -g "hush://overlay/toggle"           # also /on, /off
open -g "hush://mode/ambient"             # /deep, /toggle
open -g "hush://app/toggle"               # ignore or un-ignore the front app
open -g "hush://set?blur=70&grain=20&mono=50&tintOpacity=30"
open -g "hush://set?tint=4A90E2"          # or ?tintPreset=black
open -g "hush://settings/triggers"        # open Settings on a page; hush://panel opens the panel
```

Shortcuts gets **Toggle Hush** and **Set Hush Blur**. Settings › Automation lists every link with copy buttons.

## Project layout

```
Hush/App        entry point, app delegate, Debug-only snapshot harness
Hush/Core       settings, overlay windows/pairs/controller, private backdrop layer, planner, window list and
                Accessibility, focus tracking, shake/peek triggers, hotkeys, Dock/menu bar, URL scheme, intents
Hush/UI         menu bar item, panel, Settings (7 pages), onboarding, shared controls and illustrations
Hush/Resources  Info.plist, entitlements, asset catalog (app icon drawn from the design)
```

Private APIs are confined to `Core/BackdropLayer.swift` (`CABackdropLayer`, `CAFilter`) and
`Core/WindowList.swift` (`_AXUIElementGetWindow`), and every private key is checked before use.
Settings › Debug › Layer tree prints what the running macOS provides.

## Verification

Checked on this Mac (macOS 27.2, one 1280×832 display) with real screen captures:

- Deep blur, the Reduce Transparency dimmer, Ambient, black and white, app-wide holes, retargeting with a
  crossfade when focus moves, desktop reveal, ignore list suspend/resume, Cursor Reveal in and out, overlays
  fully ordered out when off, and Hush's own CPU at 0.1–0.3% while on and idle.
- Every panel state and Settings page, plus both onboarding steps, compared against the design files.

Not machine-tested, because they need real input devices or permissions this session didn't have:
shake detection, global shortcuts, corner/hold/drag peeks, Accessibility-driven focus events, Dock and menu
bar hiding, the login item, Shortcuts actions, multiple displays and Stage Manager. Run through the spec's
§6.1 test matrix for those.

## Debug builds only

- `defaults write com.jayabharat.hush HushDevSkipAXCheck -bool YES` lets Hush turn on without Accessibility.
- `defaults write com.jayabharat.hush HushDevForceNeedsAccess -bool YES` shows the "needs Accessibility" screens
  even when access is allowed (for screenshots).
- `HUSH_SNAPSHOT_DIR=<dir>` (via `open --env`) saves PNGs of the panel, every Settings page and onboarding;
  `HUSH_SNAPSHOT_ONLY=panel,onboarding` limits it to those screens.
- `HUSH_DEBUG_SETTINGS='{"mode":"ambient"}'` merges settings at launch; `hush://debug/layers`,
  `hush://debug/windows` and `hush://debug/reapply` log to Settings › Debug.
- `hush://debug/shake?shift=1&reversals=6&gestures=2&gap=0.6` feeds synthetic shakes through the real
  detector (verifies toggling, one-toggle-per-shake and Shift handling without touching the mouse).
