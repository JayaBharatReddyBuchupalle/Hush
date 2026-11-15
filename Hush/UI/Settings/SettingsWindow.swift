import AppKit
import Observation
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, triggers, apps, displays, automation, debug
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .triggers: return "Triggers"
        case .apps: return "Apps"
        case .displays: return "Displays"
        case .automation: return "Automation"
        case .debug: return "Debug"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "circle.lefthalf.filled"
        case .triggers: return "cursorarrow.motionlines"
        case .apps: return "square.grid.2x2"
        case .displays: return "display"
        case .automation: return "apple.terminal"
        case .debug: return "ant"
        }
    }
}

@MainActor @Observable
final class SettingsNavigation {
    var page: SettingsPage = SettingsPage(rawValue: UserDefaults.standard.string(forKey: "settingsPage") ?? "") ?? .general {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "settingsPage") }
    }
}

/// Plain NSWindow hosting SwiftUI. Hush becomes a regular app (Dock icon, menus) while it's open.
/// The window fits each page's height like the classic preferences windows, keeping its top edge in place.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    static let width: CGFloat = 760

    let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var pendingHeight: CGFloat?
    var isVisible: Bool { window?.isVisible == true }

    func show(page: SettingsPage? = nil) {
        if let page { navigation.page = page }
        let window = self.window ?? makeWindow()
        NSApp.setActivationPolicy(.regular)
        if !window.isVisible {
            window.center()
            if let h = pendingHeight { resize(to: h, animate: false) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { window?.performClose(nil) }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 610),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Hush Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "HushSettingsToolbar")
        toolbar.displayMode = .iconOnly
        w.toolbar = toolbar
        w.toolbarStyle = .unified
        w.titlebarSeparatorStyle = .none
        w.isMovableByWindowBackground = true
        w.backgroundColor = Theme.nsWindowBackground
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.delegate = self
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        let root = SettingsRootView(navigation: navigation) { [weak self] height in
            self?.contentHeightChanged(height)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        w.contentView = hosting
        window = w
        return w
    }

    private func contentHeightChanged(_ height: CGFloat) {
        pendingHeight = height
        resize(to: height, animate: window?.isVisible == true)
    }

    private func resize(to contentHeight: CGFloat, animate: Bool) {
        guard let window else { return }
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let target = min(max(contentHeight, 420), screenHeight - 40).rounded()
        var frame = window.frame
        guard abs(frame.height - target) > 1 else { return }
        frame.origin.y = frame.maxY - target
        frame.size.height = target
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { AppActivation.update() }
        }
    }
}

/// Hush is a menu bar app; it shows a Dock icon only while one of its windows is open.
@MainActor
enum AppActivation {
    static func update() {
        let anyOpen = SettingsWindowController.shared.isVisible || OnboardingWindowController.shared.isVisible
        NSApp.setActivationPolicy(anyOpen ? .regular : .accessory)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SettingsRootView: View {
    @Bindable var navigation: SettingsNavigation
    var onContentHeight: (CGFloat) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            ScrollView(.vertical) {
                page
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.leading, 20)
                    .padding(.trailing, 28)
                    .padding(.bottom, 28)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    })
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: SettingsWindowController.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 32)          // the traffic lights sit here
            ForEach(SettingsPage.allCases) { page in
                SidebarRow(page: page, selected: navigation.page == page) { navigation.page = page }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(width: 208)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        )
        .padding(8)
    }

    @ViewBuilder
    private var page: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(navigation.page.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 24)
            switch navigation.page {
            case .general: GeneralPage()
            case .appearance: AppearancePage()
            case .triggers: TriggersPage()
            case .apps: AppsPage()
            case .displays: DisplaysPage()
            case .automation: AutomationPage()
            case .debug: DebugPage()
            }
        }
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(page.title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.86))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.buttonBlue : (hovering ? Color.white.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
