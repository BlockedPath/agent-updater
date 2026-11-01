import AppKit
import SwiftUI
import UserNotifications

/// UserDefaults keys for everything in Settings.
enum Pref {
    static let appearance = "appearance"
    static let theme = "theme"
    static let showInDock = "showInDock"
    static let sounds = "sounds"
    static let compact = "compact"
    static let menuBar = "menuBar"
    static let dockBadge = "dockBadge"
    static let checkInterval = "checkInterval" // minutes, 0 = only when asked
    static let notify = "notify"
    static let autoUpdate = "autoUpdate"
    static let showDiscover = "showDiscover"
    static let hidden = "hidden"
    static let pinned = "pinned"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            compact: true,
            menuBar: false,
            showInDock: true,
            sounds: true,
            dockBadge: true,
            checkInterval: 360,
            notify: false,
            autoUpdate: false,
            showDiscover: true,
        ])
    }
}

/// Short system sounds for update events (Settings › Updates › Sound effects).
enum Sound {
    case updated, allDone, installed, removed, failed, found

    var name: String {
        switch self {
        case .updated: "Tink"
        case .allDone: "Glass"
        case .installed: "Hero"
        case .removed: "Bottle"
        case .failed: "Basso"
        case .found: "Pop"
        }
    }

    @MainActor
    static func play(_ sound: Sound, force: Bool = false) {
        guard force || (UserDefaults.standard.bool(forKey: Pref.sounds) && !Snapshot.isRequested) else { return }
        NSSound(named: NSSound.Name(sound.name))?.play()
    }
}

/// Dock icon on or off. Off makes Agent Updater a menu bar app (the menu bar icon turns on so
/// there's always a way back to the window).
enum DockPresence {
    @MainActor
    static func apply() {
        let defaults = UserDefaults.standard
        let inDock = defaults.bool(forKey: Pref.showInDock)
        if !inDock && !defaults.bool(forKey: Pref.menuBar) { defaults.set(true, forKey: Pref.menuBar) }
        NSApp.setActivationPolicy(inDock ? .regular : .accessory)
        if inDock { NSApp.activate() }
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

// MARK: - Settings window

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Updates", systemImage: "arrow.down.circle") { UpdateSettings() }
            Tab("Agents", systemImage: "square.stack.3d.up") { AgentSettings() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver") { AdvancedSettings() }
        }
        .frame(width: 520)
        .frame(minHeight: 340)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Pref.appearance) private var appearance: Appearance = .system
    @AppStorage(Pref.theme) private var themeID = "system"
    @AppStorage(Pref.compact) private var compact = true
    @AppStorage(Pref.menuBar) private var menuBar = false
    @AppStorage(Pref.showInDock) private var showInDock = true
    @AppStorage(Pref.dockBadge) private var dockBadge = true
    @AppStorage(Pref.showDiscover) private var showDiscover = true
    @Environment(AgentStore.self) private var store

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(Theme.all) { theme in
                        ThemeSwatch(theme: theme, selected: theme.id == themeID) { themeID = theme.id }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(Theme.named(themeID).dark != nil)
                if let dark = Theme.named(themeID).dark {
                    Text("\(Theme.named(themeID).name) is a \(dark ? "dark" : "light") theme, so it sets the appearance.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Compact layout", isOn: $compact)
                Text("One line per agent. Toggle it anytime with ⇧⌘C.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Where it shows up") {
                Toggle("Show in menu bar", isOn: $menuBar)
                    .disabled(!showInDock) // a menu bar app needs its menu bar icon
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { DockPresence.apply() }
                Text(showInDock
                     ? "Turn off to run Agent Updater from the menu bar only."
                     : "Agent Updater lives in the menu bar. Click its icon to open the window.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("A menu bar icon with the number of updates, quick updates, and Check Now. "
                     + "With it on, closing the window keeps Agent Updater running.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Dock badge with the number of updates", isOn: $dockBadge)
                    .onChange(of: dockBadge) { store.updateDockBadge() }
                Toggle("Show the Discover tab", isOn: $showDiscover)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @Environment(AgentStore.self) private var store
    @AppStorage(Pref.checkInterval) private var checkInterval = 360
    @AppStorage(Pref.notify) private var notify = false
    @AppStorage(Pref.autoUpdate) private var autoUpdate = false
    @AppStorage(Pref.sounds) private var sounds = true

    var body: some View {
        Form {
            Section("Checking") {
                Picker("Check for updates", selection: $checkInterval) {
                    Text("Only when I click Check").tag(0)
                    Text("Every hour").tag(60)
                    Text("Every 6 hours").tag(360)
                    Text("Once a day").tag(1440)
                }
                Text("Checks run while Agent Updater is open, including from the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("When something is behind") {
                Toggle("Send a notification", isOn: $notify)
                    .onChange(of: notify) { _, on in if on { Notifier.requestAuthorization() } }
                Toggle("Update automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in if on { Task { await store.refresh() } } }
                HStack {
                    Toggle("Sound effects", isOn: $sounds)
                    Spacer()
                    Button("Preview") {
                        Task {
                            for sound in [Sound.updated, .allDone, .failed] {
                                Sound.play(sound, force: true)
                                try? await Task.sleep(for: .milliseconds(700))
                            }
                        }
                    }
                    .controlSize(.small)
                }
                Text("Updates run one at a time and skip pinned agents. Agent system apps like Muse "
                     + "update themselves, so they're only reported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentSettings: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        Form {
            ForEach(AgentKind.allCases) { kind in
                let agents = store.agents.filter { $0.role == kind }
                let systems = store.systems.filter { $0.role == kind }
                if !agents.isEmpty || !systems.isEmpty {
                    Section(kind.title) {
                        ForEach(agents) { agent in
                            row(name: agent.name, icon: AgentIcon(agent: agent, size: 24), detail: agent.installed, canPin: agent.updater != nil)
                        }
                        ForEach(systems) { system in
                            row(name: system.name,
                                icon: AgentIcon(name: system.name, app: system.app, iconURL: system.iconURL, size: 24),
                                detail: system.installed ?? "web", canPin: false)
                        }
                    }
                }
            }
            Section {
                Text("Pinned agents are skipped by Update All and automatic updates. Hidden ones disappear "
                     + "from the lists, counts and notifications.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(name: String, icon: AgentIcon, detail: String?, canPin: Bool) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 28, height: 28)
            Text(name)
            if let detail {
                Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            if canPin {
                Toggle("Pin", isOn: Binding(
                    get: { store.pinned.contains(name) },
                    set: { _ in store.togglePinned(name) }))
                    .toggleStyle(.checkbox)
            }
            Toggle("Hide", isOn: Binding(
                get: { store.hidden.contains(name) },
                set: { _ in store.toggleHidden(name) }))
                .toggleStyle(.checkbox)
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AgentStore.self) private var store
    @Environment(IconStore.self) private var icons
    @State private var confirmReset = false
    @State private var cliInstalled = FileManager.default.fileExists(
        atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/update-agents").path)

    /// Symlinks ~/.local/bin/update-agents to the bundled script.
    private func installCLI(from bundled: String) {
        let bin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("update-agents")
        do {
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: bundled)
            cliInstalled = true
            store.showToast("Installed update-agents in ~/.local/bin")
            Task { await checkPath() }
        } catch {
            store.showToast("Couldn't install the command: \(error.localizedDescription)",
                            symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    /// Whether a new Terminal window has ~/.local/bin on PATH. nil until the login shell answers,
    /// or if it can't be read, so no warning flickers in.
    @State private var onPath: Bool?
    @State private var startupFile: URL?
    @State private var pathNote: String?

    private func checkPath() async {
        guard let shell = await TerminalPath.read() else { onPath = nil; return }
        onPath = TerminalPath.path(shell.path, contains: TerminalPath.binDirectory)
        startupFile = TerminalPath.startupFile(zdotdir: shell.zdotdir)
    }

    private func addToPath(_ file: URL) {
        let name = file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        do {
            try TerminalPath.addFix(to: file)
        } catch {
            pathNote = "Couldn't write to \(name): \(error.localizedDescription)"
            return
        }
        Task {
            await checkPath()
            // nil means the shell couldn't be read again; the line was still written.
            pathNote = onPath == false
                ? "Added to \(name), but a new shell still can't see ~/.local/bin. Check that file."
                : "Added to \(name). Open a new Terminal window to use update-agents."
        }
    }

    var body: some View {
        Form {
            Section("update-agents script") {
                LabeledContent("Path") {
                    Text(store.scriptPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let bundled = AgentStore.bundledScript, !cliInstalled {
                    HStack {
                        Text("Use it from Terminal too:").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Install Command-Line Tool") { installCLI(from: bundled) }
                            .help("Links ~/.local/bin/update-agents to the copy inside this app")
                    }
                }
                if cliInstalled, onPath == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Terminal can't find update-agents: ~/.local/bin isn't on your PATH.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                        }
                        .font(.caption)
                        HStack {
                            Text(TerminalPath.fixLine())
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            if let file = startupFile {
                                Button("Add to \(file.lastPathComponent)") { addToPath(file) }
                                    .help("Appends this line to \(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                            } else {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(TerminalPath.fixLine(), forType: .string)
                                }
                                .help("Copies the line to add to your shell's startup file")
                            }
                        }
                    }
                }
                if let pathNote {
                    Text(pathNote).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.scriptPath)])
                    }
                    Button("Open Logs Folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSTemporaryDirectory()))
                    }
                    .help("Update logs are in the update-agents-… folders here")
                }
            }
            Section("Maintenance") {
                HStack {
                    Button("Check Now") { Task { await store.refresh() } }
                        .disabled(store.isChecking)
                    Button("Clear Icon Cache") { icons.clearCache() }
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .task { if cliInstalled { await checkPath() } }
        .confirmationDialog("Reset all Agent Updater settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
                store.pinned = []
                store.hidden = []
            }
        } message: {
            Text("Appearance, layout, checking, pinned and hidden agents go back to their defaults.")
        }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @Environment(AgentStore.self) private var store

    /// The app's own icon, sized for the menu bar (full color, not a template glyph).
    private static let icon: NSImage = {
        let source = NSApp.applicationIconImage ?? NSImage()
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }()

    var body: some View {
        let count = store.behindCount + store.systemsBehind.count
        Image(nsImage: Self.icon)
        if count > 0 {
            Text("\(count)")
        }
    }
}

struct MenuBarContent: View {
    @Environment(AgentStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let behind = store.activeAgents.filter { $0.status == .behind }
        Text(store.statusLine)
        if let error = store.errorMessage, store.hasLoaded {
            Text("Couldn't refresh: \(error)")
        }
        if !behind.isEmpty || !store.systemsBehind.isEmpty {
            Section("Updates available") {
                ForEach(behind) { agent in
                    Button(menuTitle(for: agent)) { store.update(agent.name) }
                        .disabled(agent.updater == nil || store.phase(of: agent.name).isBusy)
                }
                ForEach(store.systemsBehind) { system in
                    Button("Open \(system.name) to Update (\(system.latest ?? "new version"))") {
                        if let app = system.app {
                            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app), configuration: .init())
                        } else {
                            store.open(system.homepage)
                        }
                    }
                }
            }
        }
        Divider()
        Button(store.updatableBehind.isEmpty ? "Update All" : "Update All (\(store.updatableBehind.count))") {
            store.updateAllBehind()
        }
        .disabled(store.updatableBehind.isEmpty)
        if store.queuedCount > 0 {
            Button("Stop After Current") { store.cancelQueued() }
        }
        Button("Check for Updates") { Task { await store.refresh() } }
            .disabled(store.isChecking)
        Divider()
        Button("Open Agent Updater") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Agent Updater") { NSApp.terminate(nil) }
    }

    /// "Codex  0.166.0 → 0.167.0", with the row's current state when it's busy or pinned.
    private func menuTitle(for agent: Agent) -> String {
        let versions = "\(agent.installed ?? "?") → \(agent.latest ?? "?")"
        let state: String? = switch store.phase(of: agent.name) {
        case .queued: "queued"
        case .updating: "updating…"
        case .failed: "failed, click to retry"
        default: store.pinned.contains(agent.name) ? "pinned" : (agent.updater == nil ? "manual update" : nil)
        }
        return "Update \(agent.displayName)   \(versions)" + (state.map { "  (\($0))" } ?? "")
    }
}
