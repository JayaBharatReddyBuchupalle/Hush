import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A non-activating panel under the menu bar icon, styled like Control Center. Because it never activates
/// Hush, the app you were using stays frontmost and stays sharp while you adjust things.
final class HushPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Frosted panel chrome: our own backdrop layer (blur 30, saturation 1.7) under a 62% fill, as in the design,
/// or a solid fill with Reduce Transparency on.
final class PanelBackgroundView: NSView {
    private let backdrop = PrivateCA.makeBackdropLayer()
    private let fill = CALayer()
    private let border = CALayer()
    private let radius: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        for l in [backdrop, fill, border].compactMap({ $0 }) {
            l.cornerRadius = radius
            l.cornerCurve = .continuous
            l.masksToBounds = true
            root.addSublayer(l)
        }
        if let backdrop {
            PrivateCA.configureBackdrop(backdrop, radius: 30, saturation: 1.7, variableMask: nil, scale: 0.5)
        }
        border.borderWidth = 1
        border.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [backdrop, fill, border].compactMap({ $0 }) { l.frame = bounds }
        CATransaction.commit()
    }

    func updateAppearance() {
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || backdrop == nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop?.isHidden = solid
        fill.backgroundColor = solid
            ? NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x30 / 255, alpha: 1).cgColor
            : NSColor(srgbRed: 34 / 255, green: 34 / 255, blue: 40 / 255, alpha: 0.62).cgColor
        CATransaction.commit()
    }
}

/// Hosting view that reports size changes and takes the first click even when the panel isn't key.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: HushPanel?
    private var background: PanelBackgroundView?
    private var hosting: PanelHostingView<AnyView>?
    private var monitors: [Any] = []
    private weak var anchorButton: NSStatusBarButton?
    private var anchorTop: CGFloat = 0
    private var rtToken: NSObjectProtocol?

    var makeContent: (() -> AnyView)?
    var onVisibilityChange: ((Bool) -> Void)?

    var isShown: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }

    func toggle(from button: NSStatusBarButton?) {
        isShown ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton?) {
        let panel = self.panel ?? makePanel()
        anchorButton = button
        background?.updateAppearance()
        position(panel, size: contentSize())
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        panel.makeKey()
        installMonitors()
        onVisibilityChange?(true)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue < 0.01 { panel.orderOut(nil) }
            }
        })
        onVisibilityChange?(false)
    }

    private func makePanel() -> HushPanel {
        let panel = HushPanel()
        panel.delegate = self
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let background = PanelBackgroundView(frame: container.bounds)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        let hosting = PanelHostingView(rootView: makeContent?() ?? AnyView(EmptyView()))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.onSizeChange = { [weak self] in
            MainActor.assumeIsolated { self?.contentSizeChanged() }
        }
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
        self.background = background
        self.hosting = hosting
        rtToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.background?.updateAppearance() } }
        return panel
    }

    private func contentSize() -> NSSize {
        guard let hosting else { return NSSize(width: 320, height: 400) }
        let fitting = hosting.fittingSize
        return NSSize(width: 320, height: max(120, ceil(fitting.height)))
    }

    private func contentSizeChanged() {
        guard let panel, panel.isVisible else { return }
        let size = contentSize()
        guard abs(panel.frame.height - size.height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = anchorTop - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        var top: CGFloat
        var midX: CGFloat
        let screen: NSScreen
        if let button = anchorButton, let bw = button.window, let s = bw.screen ?? NSScreen.main {
            let rect = bw.convertToScreen(button.convert(button.bounds, to: nil))
            screen = s
            midX = rect.midX
            top = rect.minY - 6
            if rect.maxY > s.frame.maxY + 1 || rect.minY < s.frame.maxY - 60 { top = s.frame.maxY - 34 }  // menu bar hidden
        } else {
            screen = NSScreen.main ?? NSScreen.screens[0]
            midX = screen.frame.maxX - 14 - size.width / 2
            top = screen.visibleFrame.maxY - 6
        }
        let f = screen.frame
        let x = min(max(midX - size.width / 2, f.minX + 10), f.maxX - size.width - 14)
        anchorTop = top
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown],
                                                        handler: { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel else { return false }
                if event.type == .keyDown {
                    if event.keyCode == UInt16(kVK_Escape), event.window === panel {
                        self.close()
                        return true
                    }
                    return false
                }
                // Clicks on the status item toggle the panel through its own action.
                if event.window !== panel, event.window !== self.anchorButton?.window { self.close() }
                return false
            }
            return consumed ? nil : event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    func windowDidResignKey(_ notification: Notification) {
        // Cmd-Tab or clicking another app: put the panel away like a popover.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
                if NSApp.modalWindow == nil { self.close() }
            }
        }
    }
}
