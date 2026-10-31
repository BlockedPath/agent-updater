import AppKit
import SwiftUI
import UserNotifications

@main
struct AgentUpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AgentStore.shared
    @State private var icons = IconStore()
    @AppStorage(Pref.appearance) private var appearance: Appearance = .system
    @AppStorage(Pref.compact) private var compact = true
    @AppStorage(Pref.menuBar) private var menuBar = false
    @AppStorage(Pref.theme) private var themeID = "system"

    init() { Pref.registerDefaults() }

    /// A theme with a fixed light or dark palette sets the appearance; otherwise the
    /// Appearance setting does.
    private func applyAppearance() {
        let theme = Theme.named(themeID)
        NSApp.appearance = theme.dark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? appearance.nsAppearance
    }

    var body: some Scene {
        WindowGroup("Agent Updater", id: "main") {
            let theme = Theme.named(themeID)
            ContentView()
                .id(themeID) // rebuild so every color picks up the new palette
                .environment(store)
                .environment(icons)
                .frame(minWidth: 560, minHeight: 480)
                .modifier(ThemedWindow(theme: theme))
                .onChange(of: themeID, initial: true) { _, id in
                    Palette.theme = Theme.named(id)
                    applyAppearance()
                }
                .onChange(of: appearance) { applyAppearance() }
                .task {
                    await store.refresh()
                    // Fetch every icon up front so cards don't pop in while scrolling.
                    for agent in store.agents { icons.load(name: agent.name, app: agent.app, iconURL: agent.iconURL) }
                    for item in store.available { icons.load(name: item.name, app: nil, iconURL: item.iconURL) }
                    for system in store.systems { icons.load(name: system.name, app: system.app, iconURL: system.iconURL) }
                    store.startScheduler()
                    await Snapshot.applyDebugEnvironment(store: store)
                    await Snapshot.writeIfRequested(store: store, icons: icons)
                }
        }
        .defaultSize(width: 660, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Check for Updates") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(store.isChecking)
                Button("Update All") { store.updateAllBehind() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(store.updatableBehind.isEmpty)
                Divider()
                Button("Find…") { store.searchFocusRequest += 1 }.keyboardShortcut("f")
                Divider()
                Button("All Agents") { store.filter = .all }.keyboardShortcut("1")
                Button("Updates") { store.filter = .behind }.keyboardShortcut("2")
                Button("Discover") { store.filter = .discover }.keyboardShortcut("3")
                Divider()
                Toggle("Compact Layout", isOn: $compact)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(icons)
        }

        MenuBarExtra(isInserted: $menuBar) {
            MenuBarContent()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Debug aid: AGENT_UPDATER_SNAPSHOT=/path/out.png renders the window into a PNG after the first
/// check (no Screen Recording permission needed), then quits.
enum Snapshot {
    static let isRequested = ProcessInfo.processInfo.environment["AGENT_UPDATER_SNAPSHOT"] != nil

    /// Review-only knobs, read from the environment (no effect in normal use):
    /// AGENT_UPDATER_TAB, AGENT_UPDATER_PHASES ("codex=updating,amp=failed"),
    /// AGENT_UPDATER_WINDOW ("560x760"), AGENT_UPDATER_AUTOUPDATE (agent name).
    @MainActor
    static func applyDebugEnvironment(store: AgentStore) async {
        let env = ProcessInfo.processInfo.environment
        if let tab = env["AGENT_UPDATER_TAB"], let filter = Filter(rawValue: tab) {
            store.filter = filter
        }
        if let size = env["AGENT_UPDATER_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
            window.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        for pair in (env["AGENT_UPDATER_PHASES"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=").map(String.init)
            guard parts.count == 2 else { continue }
            let phase: RowPhase? = switch parts[1] {
            case "queued": .queued
            case "updating": .updating
            case "updated": .updated(from: "0.0.0")
            case "installed": .installed
            case "removing": .removing
            case "staged": .staged
            case "unchanged": .unchanged
            case "failed": .failed
            default: nil
            }
            store.phases[parts[0]] = phase
            if phase == .failed { store.logs[parts[0]] = "error: pretend failure for the review render" }
        }
        // AGENT_UPDATER_ACTIONS="updateall;install:opencode;uninstall:herdr" queues real store actions
        // (against the review fixture) so live captures can show runs in progress and their results.
        for action in (env["AGENT_UPDATER_ACTIONS"] ?? "").split(separator: ";") {
            let parts = action.split(separator: ":").map(String.init)
            switch (parts.first, parts.count > 1 ? parts[1] : nil) {
            case ("updateall", _): store.updateAllBehind()
            case ("update", let name?): store.update(name)
            case ("install", let name?): store.install(name)
            case ("uninstall", let name?): store.uninstall(name)
            default: break
            }
        }
        if let name = env["AGENT_UPDATER_AUTOUPDATE"] {
            store.update(name)
            while [.queued, .updating].contains(store.phase(of: name)) {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    @MainActor
    static func writeIfRequested(store: AgentStore, icons: IconStore) async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["AGENT_UPDATER_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(2.5)) // let icons load and animations settle
        let dark = UserDefaults.standard.string(forKey: "appearance") == Appearance.dark.rawValue
        let width = Double(env["AGENT_UPDATER_SNAPSHOT_WIDTH"] ?? "") ?? 660
        let height = Double(env["AGENT_UPDATER_SNAPSHOT_HEIGHT"] ?? "") ?? 1900
        let view = ContentView()
            .environment(store)
            .environment(icons)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: width, height: height)
            .background(dark ? Color(white: 0.14) : Color(white: 0.96))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock icon or menu-bar-only, per Settings (also makes a bare `swift run` binary a real app).
        DockPresence.apply()
        UNUserNotificationCenter.current().delegate = self
    }

    /// With the menu bar icon on, closing the window keeps the app (and its checks) running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Pref.menuBar)
    }

    // Show notifications even while the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
