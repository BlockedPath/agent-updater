import AppKit
import SwiftUI
import Foundation
import Observation

/// Coding agents write code themselves; orchestrators (herdr, T3 Code, …) run and coordinate other agents.
enum AgentKind: String, Decodable, CaseIterable, Identifiable {
    case agent, ade, multiplexer, orchestrator, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: "Coding Agents"
        case .ade: "ADEs"
        case .multiplexer: "Multiplexers"
        case .orchestrator: "Orchestrators"
        case .system: "Agent Systems"
        }
    }
    var subtitle: String {
        switch self {
        case .agent: "Harnesses that write and edit code"
        case .ade: "Agentic development environments"
        case .multiplexer: "Terminals that run many agents side by side"
        case .orchestrator: "Coordinate teams of agents"
        case .system: "Always-on agents that work for you"
        }
    }
    var symbol: String {
        switch self {
        case .agent: "terminal.fill"
        case .ade: "macwindow"
        case .multiplexer: "rectangle.split.3x1.fill"
        case .orchestrator: "square.stack.3d.up.fill"
        case .system: "brain.head.profile.fill"
        }
    }
    var tint: Color {
        switch self {
        case .agent: Palette.accent
        case .ade: Palette.info
        case .multiplexer: Palette.accent.mix(with: Palette.accent2, by: 0.5)
        case .orchestrator: Palette.accent2
        case .system: Palette.accent3
        }
    }
}

/// An always-on agent system (Grok Bot, Muse, Claude Duet): a self-updating desktop app or a web app.
struct AgentSystem: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable {
        case current, behind, ahead, unknown
        case selfUpdating = "self"
        case web
    }

    let name: String
    let kind: AgentKind?
    let description: String
    let homepage: String
    let app: String?
    let status: Status
    let installed: String?
    let build: String?
    let latest: String?
    let lastUpdated: Date?
    let iconURL: String?
    let platforms: [String]?
    let platformNote: String?

    var id: String { name }

    var role: AgentKind { kind ?? .system }

    enum CodingKeys: String, CodingKey {
        case name, kind, description, homepage, app, status, installed, build, latest, platforms
        case platformNote = "platform_note"
        case lastUpdated = "last_updated"
        case iconURL = "icon_url"
    }
}

/// One row of `update-agents --json`. All version logic lives in the script; the app only displays it.
struct Agent: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable {
        case current, behind, ahead, unknown
    }

    let name: String
    let kind: AgentKind?
    let installed: String?
    let latest: String?
    let status: Status
    let updater: String?
    let bin: String
    let installPath: String
    let lastUpdated: Date?
    let app: String?
    let iconURL: String?
    let platforms: [String]?
    let platformNote: String?

    var id: String { name }
    var role: AgentKind { kind ?? .agent }

    enum CodingKeys: String, CodingKey {
        case name, kind, installed, latest, status, updater, bin, app, platforms
        case platformNote = "platform_note"
        case installPath = "install_path"
        case lastUpdated = "last_updated"
        case iconURL = "icon_url"
    }
}

/// A popular agent that isn't installed (the `available` list of `update-agents --json`).
struct CatalogAgent: Decodable, Identifiable, Equatable {
    let name: String
    let kind: AgentKind?
    let description: String
    let homepage: String
    let install: String
    let latest: String?
    let iconURL: String?
    let platforms: [String]?
    let platformNote: String?

    var id: String { name }
    var role: AgentKind { kind ?? .agent }

    enum CodingKeys: String, CodingKey {
        case name, kind, description, homepage, install, latest, platforms
        case platformNote = "platform_note"
        case iconURL = "icon_url"
    }
}

private struct Report: Decodable {
    let checkedAt: Date
    let agents: [Agent]
    let systems: [AgentSystem]
    let available: [CatalogAgent]

    enum CodingKeys: String, CodingKey {
        case checkedAt = "checked_at"
        case agents, systems, available
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try c.decode(Date.self, forKey: .checkedAt)
        agents = try c.decode([Agent].self, forKey: .agents)
        systems = try c.decodeIfPresent([AgentSystem].self, forKey: .systems) ?? []
        available = try c.decodeIfPresent([CatalogAgent].self, forKey: .available) ?? []
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Shared motion values (PLAN D10).
enum Motion {
    static let standard = Animation.spring(duration: 0.35, bounce: 0.15)
    static let quick = Animation.spring(duration: 0.22, bounce: 0.1)
}

/// What the app is doing with a row right now.
enum RowPhase: Equatable {
    case idle
    case queued
    case updating
    case updated(from: String)
    case installed
    case removing
    case staged   // new version installed, takes effect after a restart
    case unchanged
    case failed
}

enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case behind = "Updates"
    case discover = "Discover"
    var id: String { rawValue }
}

/// Human names for the tools we know; the binary name stays visible as secondary text.
enum DisplayName {
    static let known: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "amp": "Amp", "cursor-agent": "Cursor Agent",
        "droid": "Droid", "grok": "Grok", "pi": "Pi", "agy": "Antigravity", "muse": "Muse Code",
        "t3": "T3 Code", "herdr": "herdr", "cmux": "cmux", "Orca": "Orca", "Rex": "Rex", "opencode": "OpenCode", "omp": "oh-my-pi",
        "gemini": "Gemini CLI", "copilot": "Copilot CLI", "goose": "Goose", "qwen": "Qwen Code",
        "crush": "Crush", "aider": "Aider", "auggie": "Auggie", "kilocode": "Kilo Code",
        "cline": "Cline", "claude-squad": "Claude Squad", "vibe-kanban": "Vibe Kanban",
        "hermes": "Hermes", "openclaw": "OpenClaw",
        "dsh": "DeepSeek Harness", "openhands": "OpenHands", "codewhale": "CodeWhale", "reasonix": "Reasonix",
        "freebuff": "Freebuff", "kimi": "Kimi Code", "forge": "Forge", "vibe": "Mistral Vibe", "kode": "Kode",
        "letta": "Letta Code", "nanocoder": "Nanocoder", "cn": "Continue", "paperclipai": "Paperclip",
        "ruflo": "Ruflo", "happy": "Happy", "paseo": "Paseo", "gt": "Gas Town", "aoe": "Agent of Empires",
        "ralph": "Ralph", "workmux": "workmux", "dmux": "dmux", "agent-deck": "Agent Deck",
        "nanobot": "nanobot", "octop": "Octop", "openmausbot": "OpenMausBot",
        "ccmanager": "CCManager", "omnara": "Omnara",
    ]
    static func of(_ name: String) -> String { known[name] ?? name }
}

extension Agent {
    var displayName: String { DisplayName.of(name) }
    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || displayName.localizedCaseInsensitiveContains(query)
    }
}

extension CatalogAgent {
    var displayName: String { DisplayName.of(name) }
    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
            || displayName.localizedCaseInsensitiveContains(query) || description.localizedCaseInsensitiveContains(query)
    }
}

extension AgentSystem {
    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || description.localizedCaseInsensitiveContains(query)
    }
}

@MainActor
@Observable
final class AgentStore {
    static let shared = AgentStore()

    var agents: [Agent] = []
    var available: [CatalogAgent] = []
    var systems: [AgentSystem] = []
    var phases: [String: RowPhase] = [:]
    var logs: [String: String] = [:]
    var isChecking = false
    var hasLoaded = false
    var lastChecked: Date?
    /// Why the most recent check failed (nil when it succeeded). With `hasLoaded` false this is a
    /// first-load failure; otherwise the list shows the last successful check.
    var errorMessage: String?
    /// The script's stderr from the failed check, for the "Details" disclosure.
    var errorDetail: String?
    var filter: Filter = .all
    var searchText = ""

    /// Update All progress: the job running now and its place in the current run.
    private(set) var currentJob: String?
    private(set) var currentJobVerb = "Updating"
    private(set) var runTotal = 0
    private(set) var runDone = 0
    /// Agents whose uninstall plan is being prepared (the dry run takes a moment).
    private(set) var preparing: Set<String> = []
    /// A short confirmation that outlives the row it's about (installed, moved to Trash, …).
    var toast: Toast?
    /// Bumped by ⌘F so the window can focus its search field.
    var searchFocusRequest = 0

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let symbol: String
        var isError = false
    }

    func showToast(_ message: String, symbol: String = "checkmark.circle.fill", isError: Bool = false) {
        let toast = Toast(message: message, symbol: symbol, isError: isError)
        withAnimation(Motion.standard) { self.toast = toast }
        Task {
            try? await Task.sleep(for: .seconds(isError ? 6 : 4))
            if self.toast == toast { withAnimation(Motion.standard) { self.toast = nil } }
        }
    }

    /// Agents hidden from every list, count and notification.
    var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Pref.hidden) ?? []) {
        didSet { UserDefaults.standard.set(Array(hidden).sorted(), forKey: Pref.hidden); updateDockBadge() }
    }
    /// Agents that Update All and auto-update skip (you can still update them by hand).
    var pinned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Pref.pinned) ?? []) {
        didSet { UserDefaults.standard.set(Array(pinned).sorted(), forKey: Pref.pinned) }
    }

    private enum Job { case update, forceUpdate, install, uninstall }
    private var queue: [(name: String, job: Job)] = []
    private var isUpdating = false

    /// The update-agents script: an override for development, then a command-line install on PATH
    /// (so a newer CLI wins), then the copy bundled inside the app.
    let scriptPath: String = AgentStore.locateScript()

    static var bundledScript: String? { Bundle.main.path(forResource: "update-agents", ofType: nil) }

    static func locateScript() -> String {
        if let custom = ProcessInfo.processInfo.environment["AGENT_UPDATER_SCRIPT"] { return custom }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let installed = "\(home)/.local/bin/update-agents"
        if FileManager.default.isExecutableFile(atPath: installed) { return installed }
        return bundledScript ?? installed
    }

    var activeAgents: [Agent] { agents.filter { !hidden.contains($0.name) } }
    var activeSystems: [AgentSystem] { systems.filter { !hidden.contains($0.name) } }

    var behindCount: Int { activeAgents.filter { $0.status == .behind }.count }
    var systemsBehind: [AgentSystem] { activeSystems.filter { $0.status == .behind } }
    /// What Update All touches: behind, has an updater, not pinned.
    var updatableBehind: [Agent] {
        activeAgents.filter { $0.status == .behind && $0.updater != nil && !pinned.contains($0.name) }
    }

    var visibleSystems: [AgentSystem] {
        let list: [AgentSystem] = switch filter {
        case .all: activeSystems
        case .behind: systemsBehind
        case .discover: []
        }
        return list.filter { $0.matches(searchText) }
    }

    /// Discover's OS filter ("macos", "linux", "windows"), or nil for everything.
    var platformFilter: String?

    var visibleAvailable: [CatalogAgent] {
        available.filter { item in
            item.matches(searchText) && (platformFilter.map { (item.platforms ?? []).contains($0) } ?? true)
        }
    }

    var unknownCount: Int {
        activeAgents.filter { $0.status == .unknown }.count + activeSystems.filter { $0.status == .unknown }.count
    }
    /// Jobs waiting behind the one running now.
    var queuedCount: Int { queue.count }
    var updatesCount: Int { behindCount + systemsBehind.count }
    var installedCount: Int { activeAgents.count + activeSystems.count }

    /// The window subtitle: one short, honest line.
    var statusLine: String {
        if let job = currentJob {
            let what = "\(currentJobVerb) \(DisplayName.of(job))"
            return runTotal > 1 ? "\(what) · \(runDone + 1) of \(runTotal)" : "\(what)…"
        }
        if !hasLoaded { return errorMessage == nil ? "Checking for updates…" : "Couldn't check for updates" }
        if isChecking { return "Checking for updates…" }
        if errorMessage != nil { return "Couldn't refresh · showing the last check" }
        if agents.isEmpty && systems.isEmpty { return "No agents installed" }
        if installedCount == 0 { return "All agents are hidden" }
        switch updatesCount {
        case 0: return unknownCount > 0 ? "No updates · \(unknownCount) couldn't be checked" : "Everything is up to date"
        case 1: return "1 update available"
        default: return "\(updatesCount) updates available"
        }
    }

    /// Behind agents first, then by name; rows being updated keep their place.
    var visibleAgents: [Agent] {
        let list = (filter == .behind
            ? activeAgents.filter { $0.status == .behind || phase(of: $0.name) != .idle }
            : activeAgents).filter { $0.matches(searchText) }
        return list.sorted { a, b in
            let ra = a.status == .behind ? 0 : 1, rb = b.status == .behind ? 0 : 1
            return ra != rb ? ra < rb : a.name < b.name
        }
    }

    func phase(of name: String) -> RowPhase { phases[name] ?? .idle }

    // MARK: Checking

    /// `reconcile` clears finished row states (Updated, Failed, …). Checks the user or the
    /// scheduler starts do that; the refreshes that follow our own jobs don't, so a run's results
    /// stay visible until the next real check.
    func refresh(only names: [String] = [], reconcile: Bool = true) async {
        if names.isEmpty { isChecking = true }
        defer { if names.isEmpty { isChecking = false } }

        let result = await Shell.run(scriptPath, ["--json"] + names, mergeStderr: false)
        guard result.status == 0 else {
            withAnimation(Motion.standard) {
                errorMessage = "The version check didn't finish."
                errorDetail = result.errors.isEmpty ? "update-agents exited with status \(result.status)." : result.errors
            }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let report = try decoder.decode(Report.self, from: Data(result.output.utf8))
            errorMessage = nil
            errorDetail = nil
            withAnimation(Motion.standard) {
                if names.isEmpty {
                    agents = report.agents
                    available = report.available
                    systems = report.systems
                    lastChecked = report.checkedAt
                    if reconcile { reconcilePhases() }
                } else {
                    for fresh in report.agents {
                        if let i = agents.firstIndex(where: { $0.name == fresh.name }) {
                            agents[i] = fresh
                        }
                    }
                }
                hasLoaded = true
            }
            updateDockBadge()
            if names.isEmpty { afterFullCheck() }
        } catch {
            errorMessage = "The version check returned something unexpected."
            errorDetail = "\(error)"
        }
    }

    // MARK: Updating

    /// After a full check, drop finished states (Updated, Failed, …) so they can't hide what the
    /// check just found. Work in flight stays, and so does "Restart to finish" while it still applies.
    private func reconcilePhases() {
        phases = phases.filter { name, phase in
            switch phase {
            case .queued, .updating, .removing: return true
            case .staged: return agents.first { $0.name == name }?.status == .behind
            default: return false
            }
        }
    }

    func update(_ name: String, force: Bool = false) {
        guard !phase(of: name).isBusy else { return }
        withAnimation(Motion.quick) { phases[name] = .queued }
        queue.append((name, force ? .forceUpdate : .update))
        Task { await drainQueue() }
    }

    /// The last kind of job each row ran, so Retry repeats the right thing.
    private var lastJob: [String: Job] = [:]

    /// Runs the last action for a failed row again.
    func retry(_ name: String) {
        switch lastJob[name] {
        case .uninstall: uninstall(name)
        case .install: install(name)
        case .forceUpdate: update(name, force: true)
        default: update(name)
        }
    }

    /// Takes a queued job off the list (the running one always finishes).
    func cancel(_ name: String) {
        guard phase(of: name) == .queued else { return }
        queue.removeAll { $0.name == name }
        runTotal = max(runDone + (currentJob == nil ? 0 : 1), runTotal - 1)
        withAnimation(Motion.quick) { phases[name] = nil }
    }

    /// Stop after the current job: drop everything still waiting.
    func cancelQueued() {
        for job in queue { phases[job.name] = nil }
        queue.removeAll()
        runTotal = runDone + (currentJob == nil ? 0 : 1)
    }

    /// What uninstalling would remove: "cmd:…" and "path:…" lines from the script's dry run, or
    /// a single "error:…" line when the dry run itself fails.
    func uninstallPlan(_ name: String) async -> [String]? {
        guard !preparing.contains(name), !phase(of: name).isBusy else { return nil }
        preparing.insert(name)
        defer { preparing.remove(name) }
        let result = await Shell.run(scriptPath, ["--uninstall", "--dry-run", name], mergeStderr: false)
        let lines = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if result.status != 0 && !lines.contains(where: { $0.hasPrefix("error:") }) {
            return ["error:" + (result.errors.isEmpty ? "the uninstall check didn't finish" : result.errors)]
        }
        return lines
    }

    func uninstall(_ name: String) {
        guard !phase(of: name).isBusy else { return }
        withAnimation(Motion.quick) { phases[name] = .queued }
        queue.append((name, .uninstall))
        Task { await drainQueue() }
    }

    func install(_ name: String) {
        guard !phase(of: name).isBusy else { return }
        withAnimation(Motion.quick) { phases[name] = .queued }
        queue.append((name, .install))
        Task { await drainQueue() }
    }

    func updateAllBehind() {
        for agent in updatableBehind { update(agent.name) }
    }

    // MARK: Background checks

    private var notified: Set<String> = []
    private var hasNotifiedOnce = false
    private var schedulerStarted = false

    /// After every full check: notify about newly behind agents, and update them if asked to.
    private func afterFullCheck() {
        let behindNames = Set(updatableBehind.map(\.name) + systemsBehind.map(\.name))
        let fresh = behindNames.subtracting(notified)
        notified = behindNames
        if hasNotifiedOnce, !fresh.isEmpty { Sound.play(.found) }
        hasNotifiedOnce = true
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Pref.notify), !fresh.isEmpty {
            let names = fresh.sorted().formatted(.list(type: .and))
            Notifier.post(title: fresh.count == 1 ? "Update available" : "\(fresh.count) updates available",
                          body: defaults.bool(forKey: Pref.autoUpdate) ? "Updating \(names)…" : names)
        }
        if defaults.bool(forKey: Pref.autoUpdate), !updatableBehind.isEmpty {
            updateAllBehind()
        }
    }

    /// Re-checks on the interval chosen in Settings, whether or not the window is open.
    func startScheduler() {
        guard !schedulerStarted else { return }
        schedulerStarted = true
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                let minutes = UserDefaults.standard.integer(forKey: Pref.checkInterval)
                guard minutes > 0, !isChecking, !isUpdating else { continue }
                if let last = lastChecked, Date().timeIntervalSince(last) < Double(minutes * 60) { continue }
                await refresh()
            }
        }
    }

    /// Updaters run one at a time, like the CLI (big downloads on an 8 GB Mac).
    private func drainQueue() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        runTotal = queue.count
        runDone = 0
        defer { currentJob = nil; runTotal = 0; runDone = 0 }
        var updated: [String] = []
        var anyFailed = false
        defer {
            if updated.count > 1 { showToast("Updated \(updated.count) agents") }
            if !updated.isEmpty && !anyFailed { Sound.play(.allDone) }
        }
        while !queue.isEmpty {
            let job = queue.removeFirst()
            lastJob[job.name] = job.job
            currentJob = job.name
            currentJobVerb = switch job.job {
            case .install: "Installing"
            case .uninstall: "Removing"
            default: "Updating"
            }
            runTotal = max(runTotal, runDone + 1 + queue.count)
            defer { runDone += 1 }
            if job.job == .uninstall {
                withAnimation(Motion.quick) { phases[job.name] = .removing }
                let result = await Shell.run(scriptPath, ["--uninstall", "--yes", job.name], mergeStderr: true)
                logs[job.name] = result.output
                if result.status == 0 {
                    phases[job.name] = nil
                    await refresh(reconcile: false) // it leaves the list (and shows up in Discover if it's a popular one)
                    showToast("Uninstalled \(DisplayName.of(job.name))", symbol: "trash.circle.fill")
                    Sound.play(.removed)
                } else {
                    anyFailed = true
                    Sound.play(.failed)
                    withAnimation(Motion.standard) { phases[job.name] = .failed }
                    showToast("Couldn't uninstall \(DisplayName.of(job.name))", symbol: "exclamationmark.triangle.fill", isError: true)
                }
                continue
            }
            if job.job == .install {
                withAnimation(Motion.quick) { phases[job.name] = .updating }
                let result = await Shell.run(scriptPath, ["--install", "--yes", job.name], mergeStderr: true)
                logs[job.name] = result.output
                if result.status == 0 {
                    phases[job.name] = nil
                    await refresh(reconcile: false) // moves it from Discover to the installed list
                    phases[job.name] = .installed
                    showToast("Installed \(DisplayName.of(job.name))")
                    Sound.play(.installed)
                } else {
                    anyFailed = true
                    Sound.play(.failed)
                    withAnimation(Motion.standard) { phases[job.name] = .failed }
                    showToast("Couldn't install \(DisplayName.of(job.name))", symbol: "exclamationmark.triangle.fill", isError: true)
                }
                continue
            }
            let before = agents.first { $0.name == job.name }?.installed ?? "?"
            let wasBehind = agents.first { $0.name == job.name }?.status == .behind
            withAnimation(Motion.quick) { phases[job.name] = .updating }

            var args = ["--yes", job.name]
            if job.job == .forceUpdate { args.insert("--all", at: 0) }
            let result = await Shell.run(scriptPath, args, mergeStderr: true)
            logs[job.name] = result.output

            await refresh(only: [job.name])
            let after = agents.first { $0.name == job.name }?.installed ?? "?"

            withAnimation(Motion.standard) {
                if result.status != 0 && after == before {
                    phases[job.name] = .failed
                    anyFailed = true
                    Sound.play(.failed)
                } else if after != before {
                    phases[job.name] = .updated(from: before)
                    updated.append(job.name)
                    if runTotal > 1 { Sound.play(.updated) }
                } else if result.status == 0 && wasBehind {
                    // The script exits 1 when a behind agent's version doesn't move, unless the
                    // updater staged the new version for the next launch ("restart to finish").
                    phases[job.name] = .staged
                } else {
                    phases[job.name] = .unchanged
                }
            }
        }
    }

    // MARK: Helpers

    func updateDockBadge() {
        let total = behindCount + systemsBehind.count
        let show = UserDefaults.standard.bool(forKey: Pref.dockBadge)
        NSApp.dockTile.badgeLabel = show && total > 0 ? "\(total)" : nil
    }

    func togglePinned(_ name: String) {
        withAnimation(.snappy) { if pinned.contains(name) { pinned.remove(name) } else { pinned.insert(name) } }
    }

    func toggleHidden(_ name: String) {
        withAnimation(.snappy) { if hidden.contains(name) { hidden.remove(name) } else { hidden.insert(name) } }
    }

    func revealInFinder(_ agent: Agent) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: agent.installPath)])
    }

    func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

import SwiftUI

enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var errors: String = ""
    }

    /// Runs the script with /bin/bash off the main thread and returns its exit status and output.
    static func run(_ script: String, _ args: [String], mergeStderr: Bool) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [script] + args
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                process.environment = env

                let pipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = mergeStderr ? pipe : errPipe
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, output: "", errors: "\(error)"))
                    return
                }
                // Drain stderr on its own thread so neither pipe can fill up and block the script.
                var errData = Data()
                let group = DispatchGroup()
                if !mergeStderr {
                    group.enter()
                    DispatchQueue.global().async {
                        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                group.wait()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self),
                    errors: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// How operating systems are named and ordered in the UI.
enum Platform {
    static let order = ["macos", "linux", "windows", "ios", "android", "web"]

    static func label(_ id: String) -> String {
        switch id {
        case "macos": "macOS"
        case "linux": "Linux"
        case "windows": "Windows"
        case "ios": "iOS"
        case "android": "Android"
        case "web": "Web"
        default: id
        }
    }

    /// "macOS, Linux and Windows · Windows via WSL only", or nil when nothing is known.
    static func summary(_ platforms: [String]?, note: String?) -> String? {
        let known = order.filter { (platforms ?? []).contains($0) }.map(label)
        let note = (note ?? "").isEmpty ? nil : note
        if known.isEmpty { return note.map { "Unknown · \($0)" } }
        return known.formatted(.list(type: .and)) + (note.map { " · \($0)" } ?? "")
    }
}
