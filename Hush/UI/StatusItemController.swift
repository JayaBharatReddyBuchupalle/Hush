import AppKit
import Observation

/// Template images for the four menu bar states in the design (on, off = dimmed, paused, needs access).
enum MenuBarIcon {
    static func image(_ kind: HushGlyph.Kind) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            NSColor.black.withAlphaComponent(kind == .alert ? 0.6 : 0.5).setStroke()
            let outer = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 16.5, height: 12.5),
                                     xRadius: 3.25, yRadius: 3.25)
            outer.lineWidth = 1.5
            outer.stroke()
            NSColor.black.setFill()
            switch kind {
            case .on:
                NSBezierPath(roundedRect: NSRect(x: 5, y: 4, width: 8, height: 6), xRadius: 1.5, yRadius: 1.5).fill()
            case .paused:
                NSBezierPath(roundedRect: NSRect(x: 6.25, y: 3.75, width: 2, height: 6.5), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: NSRect(x: 9.75, y: 3.75, width: 2, height: 6.5), xRadius: 1, yRadius: 1).fill()
            case .alert:
                NSBezierPath(roundedRect: NSRect(x: 8.1, y: 3.2, width: 1.8, height: 4.8), xRadius: 0.9, yRadius: 0.9).fill()
                NSBezierPath(ovalIn: NSRect(x: 8, y: 9.1, width: 2, height: 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hush"
        return image
    }
}

/// NSStatusItem rather than MenuBarExtra, because plain clicks, Shift-clicks and right-clicks differ:
/// click toggles (or opens the panel / Settings), Shift-click switches mode, right/Control-click opens the panel.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay: OverlayController
    private let store: SettingsStore
    var onTogglePanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    var button: NSStatusBarButton? { item.button }

    init(overlay: OverlayController, store: SettingsStore) {
        self.overlay = overlay
        self.store = store
        super.init()
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Hush")
            button.imagePosition = .imageOnly
        }
        refresh()
        observe()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let flags = event.modifierFlags
        if event.type == .rightMouseUp || flags.contains(.control) || !overlay.canTurnOn {
            onTogglePanel?()
            return
        }
        if flags.contains(.shift) {
            store.update { $0.mode.toggle() }
            return
        }
        switch store.value.menuBarClick {
        case .toggle: overlay.toggle()
        case .panel: onTogglePanel?()
        case .settings: onOpenSettings?()
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        item.button?.highlight(highlighted)
    }

    private func observe() {
        withObservationTracking {
            _ = overlay.iconState
            _ = store.value.mode
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.observe()
                }
            }
        }
    }

    private func refresh() {
        guard let button = item.button else { return }
        let state = overlay.iconState
        switch state {
        case .on:
            button.image = MenuBarIcon.image(.on)
            button.toolTip = "Hush is on (\(store.value.mode.title))"
        case .off:
            button.image = MenuBarIcon.image(.on)
            button.toolTip = "Hush is off"
        case .paused:
            button.image = MenuBarIcon.image(.paused)
            button.toolTip = "Hush is paused: the front app is on your ignore list"
        case .needsAccess:
            button.image = MenuBarIcon.image(.alert)
            button.toolTip = "Hush needs Accessibility access"
        }
        button.appearsDisabled = state == .off       // drawn dimmed, like a disabled menu item
    }
}
