import AppKit

// Hush manages its own windows (menu bar panel, Settings, onboarding), so it uses a plain AppKit entry point
// rather than a SwiftUI App, whose built-in Settings scene would open an empty window on ⌘,.
@MainActor
enum AppMain {
    static let delegate = AppDelegate()     // NSApplication.delegate is weak; keep it alive here
}

MainActor.assumeIsolated {
    NSApplication.shared.delegate = AppMain.delegate
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
