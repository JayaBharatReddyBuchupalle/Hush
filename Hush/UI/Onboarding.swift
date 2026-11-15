import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class OnboardingModel {
    var step = 1
    var openAtLogin = true
}

/// First launch: step 1 explains and requests Accessibility, step 2 shows how to use Hush.
/// Step 1 advances by itself once access is allowed.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    static let completedKey = "onboardingComplete"

    private var window: NSWindow?
    private let model = OnboardingModel()
    private var observing = false
    var onTurnOn: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { window?.isVisible == true }

    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    func show() {
        model.step = OverlayController.shared.canTurnOn ? 2 : 1
        let window = self.window ?? makeWindow()
        NSApp.setActivationPolicy(.regular)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        observeTrust()
    }

    func close() { window?.close() }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 684),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Welcome to Hush"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = Theme.nsWindowBackground
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        w.delegate = self
        let view = OnboardingView(
            model: model,
            quit: { NSApp.terminate(nil) },
            openAccessibility: {
                AX.requestTrust()
                AX.openAccessibilitySettings()
            },
            openSettings: { [weak self] in self?.finish(turnOn: false) },
            turnOn: { [weak self] in self?.finish(turnOn: true) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        w.contentView = hosting
        window = w
        return w
    }

    /// Step 1 → 2 as soon as Accessibility is allowed, and bring the window back to the front.
    private func observeTrust() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = SystemState.shared.accessibilityTrusted
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.observing = false
                    if SystemState.shared.accessibilityTrusted, self.model.step == 1, self.isVisible {
                        withAnimation(.easeInOut(duration: 0.25)) { self.model.step = 2 }
                        self.window?.makeKeyAndOrderFront(nil)
                        NSApp.activate()
                    }
                    if self.isVisible { self.observeTrust() }
                }
            }
        }
    }

    private func finish(turnOn: Bool) {
        Self.isComplete = true
        LoginItem.set(model.openAtLogin)
        window?.close()
        if turnOn { onTurnOn?() } else { onOpenSettings?() }
    }

    func windowWillClose(_ notification: Notification) {
        if model.step == 2 { Self.isComplete = true }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { AppActivation.update() }
        }
    }
}

struct OnboardingView: View {
    var model: OnboardingModel
    var quit: () -> Void
    var openAccessibility: () -> Void
    var openSettings: () -> Void
    var turnOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.step == 1 { stepOne } else { stepTwo }
        }
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(width: 600, height: 684, alignment: .topLeading)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    // MARK: Step 1

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroScene().frame(height: 170)
            stepLabel("Step 1 of 2").padding(.top, 22)
            title("Allow Accessibility access")
            bodyText("Hush keeps the window you’re using sharp by following which window is in front. macOS calls this Accessibility access. Hush only uses window positions and never records your screen.")
            VStack(alignment: .leading, spacing: 10) {
                numbered(1, "Click Open Accessibility Settings.")
                HStack(spacing: 12) {
                    numberDot(2)
                    Text("Turn on Hush in the list.")
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        HushIconView(size: 18)
                        Text("Hush").font(.system(size: 12))
                        ZStack(alignment: .trailing) {
                            Capsule().fill(Theme.blue)
                            Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                        }
                        .frame(width: 30, height: 18)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .accessibilityHidden(true)
                }
                .frame(minHeight: 28)
                numbered(3, "Come back here. Hush continues on its own.")
            }
            .padding(.top, 18)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 14, height: 14)
                Text("Waiting for access…").font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.72))
            }
            .accessibilityElement(children: .combine)
            HStack {
                Button("Quit Hush", action: quit).buttonStyle(PillButtonStyle(kind: .onboarding))
                Spacer()
                Button("Open Accessibility Settings", action: openAccessibility)
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
    }

    // MARK: Step 2

    private var stepTwo: some View {
        let shortcut = SettingsStore.shared.value.shortcut(.toggleOverlay)
        return VStack(alignment: .leading, spacing: 0) {
            HushIconView(size: 72).shadow(color: .black.opacity(0.4), radius: 12, y: 8)
            stepLabel("Step 2 of 2").padding(.top, 20)
            title("Hush is ready")
            bodyText("Here’s how to quiet your screen whenever it gets busy.")
            VStack(spacing: 0) {
                tipRow(icon: AnyView(Image(systemName: "cursorarrow.motionlines").font(.system(size: 17))),
                       title: "Shake the pointer",
                       detail: "A quick side-to-side shake turns Hush on or off."
                           + (SettingsStore.shared.value.shakePeekEnabled ? " Hold Shift while you shake to peek." : ""))
                RowDivider()
                tipRow(icon: AnyView(Image(systemName: "keyboard").font(.system(size: 16))),
                       title: shortcut.map { "Press \($0.displayString)" } ?? "Set a keyboard shortcut",
                       detail: shortcut.map { "\($0.spokenString). You can change it in Settings, under Triggers." }
                           ?? "Add one in Settings, under Triggers.")
                RowDivider()
                tipRow(icon: AnyView(HushGlyph(kind: .on, width: 18)),
                       title: "Click Hush in the menu bar",
                       detail: "Shift-click switches between Ambient and Deep. Right-click opens the panel.")
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.groupFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupStroke, lineWidth: 1))
            .padding(.top, 18)
            HStack {
                Text("Open Hush at login")
                Spacer()
                HushSwitch(isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }),
                           offFill: Color.white.opacity(0.2), label: "Open Hush at login")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.groupFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.groupStroke, lineWidth: 1))
            .padding(.top, 14)
            Spacer(minLength: 0)
            HStack {
                Button("Open Settings…", action: openSettings).buttonStyle(PillButtonStyle(kind: .onboarding))
                Spacer()
                Button("Turn On Hush", action: turnOn)
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Pieces

    private func stepLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.62)).padding(.bottom, 6)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold)).tracking(-0.22).foregroundStyle(.white).padding(.bottom, 8)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(Color.white.opacity(0.78))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func numberDot(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white.opacity(0.1)))
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            numberDot(n)
            Text(text)
        }
        .frame(minHeight: 28)
    }

    private func tipRow(icon: AnyView, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            icon
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.62))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }
}
