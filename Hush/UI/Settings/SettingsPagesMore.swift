import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Apps

struct AppsPage: View {
    @Bindable private var store = SettingsStore.shared
    @State private var selectedIgnored: String?
    @State private var addAnchor = MenuAnchor()
    private var s: HushSettings { store.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: "Keep sharp") {
                SettingsGroup {
                    radioRow(.window, title: "The window you’re using",
                             subtitle: "Everything else is quieted, including other windows of the same app.")
                    RowDivider()
                    radioRow(.app, title: "Every window of the front app",
                             subtitle: "All visible windows of the app you’re using stay sharp.")
                }
            }

            SettingsSection(title: "Ignored apps") {
                NoteText(text: "Hush fades out while one of these is in front. Launchers are on the list from the start so they don’t flicker.")
                SettingsGroup {
                    ForEach(Array(s.ignoredBundleIDs.enumerated()), id: \.element) { index, bundleID in
                        if index > 0 { RowDivider() }
                        Button {
                            selectedIgnored = selectedIgnored == bundleID ? nil : bundleID
                        } label: {
                            HStack(spacing: 10) {
                                AppIconTile(bundleID: bundleID, size: 24)
                                Text(AppIcons.name(for: bundleID)).foregroundStyle(Theme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(selectedIgnored == bundleID ? Theme.buttonBlue.opacity(0.35) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !s.ignoredBundleIDs.isEmpty { RowDivider() }
                    HStack(spacing: 2) {
                        IconButton(systemName: "plus", size: 24, iconSize: 12, color: Color.white.opacity(0.85),
                                   help: "Add an app to ignore") {
                            AppPicker.show(from: addAnchor.view, excluding: Set(s.ignoredBundleIDs)) { id in
                                store.update { if !$0.ignoredBundleIDs.contains(id) { $0.ignoredBundleIDs.append(id) } }
                            }
                        }
                        .background(MenuAnchorView(anchor: addAnchor))
                        IconButton(systemName: "minus", size: 24, iconSize: 12, color: Color.white.opacity(0.85),
                                   help: "Remove the selected app") {
                            guard let id = selectedIgnored else { NSSound.beep(); return }
                            store.update { $0.ignoredBundleIDs.removeAll { $0 == id } }
                            selectedIgnored = nil
                        }
                        .disabled(selectedIgnored == nil)
                        .opacity(selectedIgnored == nil ? 0.5 : 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 36)
                }
            }

            SettingsSection(title: "App groups") {
                NoteText(text: "Apps in a group stay sharp together whenever one of them is in front.")
                ForEach(s.appGroups) { group in
                    AppGroupCard(groupID: group.id)
                }
                Button("New Group") {
                    store.update { $0.appGroups.append(AppGroup(name: "Group \($0.appGroups.count + 1)", bundleIDs: [])) }
                }
                .buttonStyle(PillButtonStyle(kind: .settings))
            }
        }
    }

    private func radioRow(_ scope: FocusScope, title: String, subtitle: String) -> some View {
        Button {
            store.update { $0.scope = scope }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RadioDot(selected: s.scope == scope).padding(.top, 1)
                RowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(s.scope == scope ? .isSelected : [])
    }
}

struct RadioDot: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(selected ? Theme.blue : Color.white.opacity(0.12))
            if selected {
                Circle().fill(.white).frame(width: 6, height: 6)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct AppGroupCard: View {
    let groupID: UUID
    @Bindable private var store = SettingsStore.shared
    @State private var addAnchor = MenuAnchor()

    private var group: AppGroup? { store.value.appGroups.first { $0.id == groupID } }

    var body: some View {
        if let group {
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Group name", text: Binding(
                            get: { group.name },
                            set: { name in update { $0.name = name } }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 220)
                        Spacer(minLength: 0)
                        IconButton(systemName: "trash", size: 24, iconSize: 12.5, color: Color.white.opacity(0.85),
                                   help: "Delete the \(group.name) group") {
                            store.update { $0.appGroups.removeAll { $0.id == groupID } }
                        }
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(group.bundleIDs, id: \.self) { bundleID in
                            HStack(spacing: 7) {
                                AppIconTile(bundleID: bundleID, size: 20)
                                Text(AppIcons.name(for: bundleID)).foregroundStyle(Theme.text)
                                Button {
                                    update { $0.bundleIDs.removeAll { $0 == bundleID } }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.72))
                                        .frame(width: 18, height: 18)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(AppIcons.name(for: bundleID)) from \(group.name)")
                            }
                            .padding(.leading, 5)
                            .padding(.trailing, 6)
                            .frame(height: 30)
                            .background(Capsule().fill(Color.white.opacity(0.08))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
                        }
                        Button {
                            AppPicker.show(from: addAnchor.view, excluding: Set(group.bundleIDs)) { id in
                                update { if !$0.bundleIDs.contains(id) { $0.bundleIDs.append(id) } }
                            }
                        } label: {
                            Text("+ Add App")
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .background(MenuAnchorView(anchor: addAnchor))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func update(_ change: (inout AppGroup) -> Void) {
        store.update { s in
            guard let i = s.appGroups.firstIndex(where: { $0.id == groupID }) else { return }
            change(&s.appGroups[i])
        }
    }
}

/// Wrapping row layout for the app chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "+" menus: running apps first, then any app on disk.
@MainActor
enum AppPicker {
    static func show(from view: NSView?, excluding: Set<String>, onPick: @escaping (String) -> Void) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        var choices: [String] = []
        let me = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != me }
            .filter { !excluding.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        let pickHandler = MenuHandler { index in
            if index >= 0 && index < choices.count {
                onPick(choices[index])
            } else {
                chooseFromDisk(onPick: onPick)
            }
        }
        if !apps.isEmpty {
            let header = NSMenuItem(title: "Running Apps", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for app in apps {
            guard let id = app.bundleIdentifier else { continue }
            let item = NSMenuItem(title: app.localizedName ?? id, action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = pickHandler
            item.tag = choices.count
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            choices.append(id)
            menu.addItem(item)
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: "Choose Another App…", action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
        other.target = pickHandler
        other.tag = -1
        menu.addItem(other)
        withExtendedLifetime(pickHandler) {
            if let view {
                _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
            } else {
                _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }

    private static func chooseFromDisk(onPick: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            onPick(id)
        }
    }
}

// MARK: - Displays

struct DisplaysPage: View {
    @Bindable private var store = SettingsStore.shared
    private var s: HushSettings { store.value }

    var body: some View {
        SettingsSection(title: "With more than one display") {
            HStack(alignment: .top, spacing: 14) {
                card(.perScreen, title: "Each display", subtitle: "Every display keeps its own front window sharp.")
                card(.global, title: "Only the window you’re using", subtitle: "Other displays are quieted completely.")
            }
            NoteText(text: "This works whether or not “Displays have separate Spaces” is on in Desktop & Dock settings.")
        }
    }

    private func card(_ mode: DisplayMode, title: String, subtitle: String) -> some View {
        let selected = s.displayMode == mode
        return Button {
            store.update { $0.displayMode = mode }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                MonitorPair(quietSecondWindow: mode == .global)
                HStack(alignment: .top, spacing: 10) {
                    RadioDot(selected: selected).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.groupFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.blue : Theme.groupStroke, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Automation

struct AutomationPage: View {
    private let links: [(String, String)] = [
        ("Turn Hush on or off", "hush://overlay/toggle"),
        ("Switch Ambient and Deep", "hush://mode/toggle"),
        ("Ignore the front app", "hush://app/toggle"),
        ("Black and white", "hush://mono/toggle"),
        ("Whole-app focus", "hush://appwide/toggle"),
        ("Display mode", "hush://display/global"),
        ("Set values from 0 to 100", "hush://set?blur=70&grain=20"),
        ("Tint", "hush://set?tintPreset=black"),
        ("Open Settings", "hush://settings"),
    ]
    static let raycastScript = """
    #!/bin/bash
    # @raycast.schemaVersion 1
    # @raycast.title Hush: Toggle Focus
    # @raycast.mode silent
    open -g "hush://overlay/toggle"
    """
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            (Text("Every action has a ") + Text("hush://").font(Theme.mono)
             + Text(" link you can run from Shortcuts, Terminal, AppleScript or Raycast. Open links with ")
             + Text("open -g").font(Theme.mono) + Text(" so Hush stays in the background."))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)

            SettingsSection(title: "Links") {
                SettingsGroup {
                    ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                        if index > 0 { RowDivider() }
                        SettingsRow {
                            RowLabel(title: link.0)
                        } trailing: {
                            HStack(spacing: 4) {
                                Text(link.1)
                                    .font(Theme.mono)
                                    .foregroundStyle(Theme.strongText)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                                IconButton(systemName: copied == link.1 ? "checkmark" : "doc.on.doc", size: 24, iconSize: 12,
                                           help: "Copy \(link.1)") { copy(link.1) }
                            }
                        }
                    }
                }
                NoteText(text: "Toggles also take /on and /off, as in hush://overlay/on. Modes take /ambient or /deep, and tints take a preset name or a hex value, as in hush://set?tint=4A90E2.")
            }

            SettingsSection(title: "Raycast script command") {
                SettingsGroup {
                    SettingsRow {
                        Text("hush-toggle.sh").font(Theme.mono).foregroundStyle(Theme.text)
                    } trailing: {
                        Button(copied == "script" ? "Copied" : "Copy Script") { copy(Self.raycastScript, key: "script") }
                            .buttonStyle(PillButtonStyle(kind: .settings))
                    }
                    RowDivider()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.raycastScript.components(separatedBy: "\n"), id: \.self) { line in
                            Text(line)
                                .font(Theme.mono)
                                .foregroundStyle(line.hasPrefix("# ") ? Color(hex: 0x8A95AD) : Color.white.opacity(0.86))
                                .frame(height: 18, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            SettingsSection(title: "Shortcuts") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Shortcuts actions", subtitle: "Hush adds Toggle Hush and Set Hush Blur to the Shortcuts app.")
                    } trailing: {
                        Button("Open Shortcuts") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        }
                        .buttonStyle(PillButtonStyle(kind: .settings))
                    }
                }
            }
        }
    }

    private func copy(_ text: String, key: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let id = key ?? text
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copied == id { copied = nil } }
    }
}

// MARK: - Debug

struct DebugPage: View {
    @Bindable private var store = SettingsStore.shared
    private var system = SystemState.shared
    private var overlay = OverlayController.shared
    private var log = DebugLog.shared
    @State private var automation = SystemChrome.AutomationStatus.unknown
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: "Status") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Accessibility")
                    } trailing: {
                        if system.accessibilityTrusted {
                            status("Allowed", symbol: "checkmark.circle.fill", color: Theme.green)
                        } else {
                            status("Not allowed", symbol: "exclamationmark.circle.fill", color: Theme.orange)
                        }
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Automation for System Events", subtitle: "Needed only to hide the Dock or menu bar.")
                    } trailing: {
                        switch automation {
                        case .allowed: status("Allowed", symbol: "checkmark.circle.fill", color: Theme.green)
                        case .denied: status("Denied", symbol: "xmark.circle.fill", color: Theme.orange)
                        case .notRequested, .unknown: status("Not requested", symbol: "circle", color: Color.white.opacity(0.6))
                        }
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Reduce Transparency")
                    } trailing: {
                        Text(system.reduceTransparency ? "On" : "Off").foregroundStyle(Theme.text)
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Blur method")
                    } trailing: {
                        Text(overlay.effect.methodDescription).font(Theme.mono).foregroundStyle(Theme.text)
                    }
                }
            }

            SettingsSection(title: "Tools") {
                SettingsGroup {
                    SettingsRow {
                        RowLabel(title: "Layer tree", subtitle: "Prints the overlay’s backdrop layers and their filters.")
                    } trailing: {
                        Button("Dump") { log.log("layer tree\n" + overlay.layerTreeDump()) }
                            .buttonStyle(PillButtonStyle(kind: .settings))
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Window list", subtitle: "Prints every on-screen window with its owner, level and frame.")
                    } trailing: {
                        Button("Dump") { log.log(overlay.windowListDump()) }
                            .buttonStyle(PillButtonStyle(kind: .settings))
                    }
                    RowDivider()
                    SettingsRow {
                        RowLabel(title: "Log shake reversals")
                    } trailing: {
                        HushSwitch(isOn: store.binding(\.logShakeReversals), offFill: Color.white.opacity(0.2),
                                   label: "Log shake reversals")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "Output")
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.plainText, forType: .string)
                    }
                    .buttonStyle(PillButtonStyle(kind: .small))
                    Button("Clear") { log.clear() }
                        .buttonStyle(PillButtonStyle(kind: .small))
                }
                console
            }
        }
        .onAppear { automation = SystemChrome.automationStatus() }
        .onReceive(timer) { _ in automation = SystemChrome.automationStatus() }
    }

    private func status(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).font(.system(size: 13))
            Text(text).foregroundStyle(Theme.strongText)
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if log.lines.isEmpty {
                        Text("Nothing yet. Turn Hush on, switch windows, or use the tools above.")
                            .foregroundStyle(Color.white.opacity(0.52))
                            .frame(height: 18, alignment: .leading)
                    }
                    ForEach(log.lines) { line in
                        HStack(alignment: .top, spacing: 14) {
                            Text(line.time.isEmpty ? "        " : line.time).foregroundStyle(Color.white.opacity(0.52))
                            Text(line.text).foregroundStyle(Color.white.opacity(0.84))
                        }
                        .frame(minHeight: 18, alignment: .leading)
                        .id(line.id)
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x141417)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .onChange(of: log.lines.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}
