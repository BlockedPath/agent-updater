import AppKit
import SwiftUI

// MARK: - Grouped content

/// Content has a quiet, continuous surface. Liquid Glass belongs to the controls above it.
struct GroupSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(Palette.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border) }
    }
}

struct RowSeparator: View {
    var body: some View { Divider().padding(.leading, 70) }
}

struct AgentRows: View {
    let agents: [Agent]
    @Environment(AgentStore.self) private var store

    private var showsSubgroups: Bool {
        store.filter == .all && agents.contains { $0.status == .behind }
            && agents.contains { $0.status != .behind }
    }

    var body: some View {
        ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
            if index > 0 { RowSeparator() }
            if showsSubgroups && (index == 0 || (agents[index - 1].status == .behind && agent.status != .behind)) {
                Text(agent.status == .behind ? "Updates available" : "Other agents")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            AgentCard(agent: agent)
        }
    }
}

private struct RowChrome: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(hovering ? 0.035 : 0))
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
    }
}

private struct RowDisclosure: View {
    let name: String
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.quick) { expanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Details for \(name)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .help(expanded ? "Hide details for \(name)" : "Show details for \(name)")
    }
}

private struct MoreButton<Content: View>: View {
    let name: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu { content } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 24)
            .accessibilityLabel("More actions for \(name)")
            .help("More actions for \(name)")
    }
}

extension RowPhase {
    var isBusy: Bool { self == .queued || self == .updating || self == .removing }
}

// MARK: - Installed agents

struct AgentCard: View {
    let agent: Agent
    @Environment(AgentStore.self) private var store
    @AppStorage(Pref.compact) private var compact = true
    @State private var expanded = false
    @State private var showLog = false
    @State private var uninstallPlan: [String]?

    private var phase: RowPhase { store.phase(of: agent.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                RowDisclosure(name: agent.displayName, expanded: $expanded)
                AgentIcon(agent: agent, size: compact ? 28 : 40)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(agent.displayName)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .lineLimit(2)
                                if store.pinned.contains(agent.name) {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .accessibilityLabel("Pinned")
                                        .help("Skipped by Update All and automatic updates")
                                }
                            }
                            StatusPill(status: agent.status, phase: phase)
                        }
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                        VersionView(agent: agent, phase: phase, compact: compact)
                            .frame(minWidth: 90, maxWidth: compact ? 205 : 230, alignment: .trailing)
                        ActionButton(agent: agent, phase: phase, showLog: $showLog)
                            .controlSize(.small)
                            .fixedSize()
                    }
                    if !compact {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text(agent.name).font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                UpdatedLabel(date: agent.lastUpdated)
                            }
                            .frame(minWidth: 480)
                            Text(agent.name).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if expanded {
                Details(agent: agent, showLog: $showLog, onUninstall: askUninstall)
                    .padding(.leading, 30)
                    .padding(.top, 12)
            }
        }
        .modifier(RowChrome())
        .contextMenu { AgentMenu(agent: agent, showLog: $showLog, onUninstall: askUninstall) }
        .sheet(isPresented: $showLog) { LogSheet(name: agent.name) }
        .uninstallDialog(name: agent.name, plan: $uninstallPlan)
    }

    private func askUninstall() {
        Task { uninstallPlan = await store.uninstallPlan(agent.name) }
    }
}

struct StatusPill: View {
    let status: Agent.Status
    let phase: RowPhase

    var body: some View {
        if let (text, symbol, color) = content {
            Label(text, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(color)
                .background(color.opacity(0.10), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
        }
    }

    private var content: (String, String, Color)? {
        switch phase {
        case .queued: return ("Queued", "hourglass", .secondary)
        case .updating: return ("Updating", "arrow.down.circle", Palette.accent)
        case .updated: return ("Updated", "checkmark.circle", Palette.success)
        case .installed: return ("Installed", "checkmark.circle", Palette.success)
        case .failed: return ("Failed", "exclamationmark.triangle", Palette.danger)
        case .staged: return ("Restart to finish", "arrow.clockwise.circle", Palette.info)
        case .removing: return ("Removing", "trash", Palette.danger)
        case .unchanged:
            return status == .current
                ? ("Already up to date", "checkmark.circle", .secondary)
                : ("Version unchanged", "equal.circle", .secondary)
        case .idle: break
        }
        switch status {
        case .current: return nil
        case .behind: return ("Update available", "arrow.up.circle", Palette.warning)
        case .ahead: return ("Ahead of release", "sparkles", Palette.info)
        case .unknown: return ("Couldn't check", "questionmark.circle", .secondary)
        }
    }
}

/// These are display strings from the script. No version comparison or parsing happens here.
private struct VersionNumbers: View {
    let installed: String
    var available: String? = nil
    var comparesVersions = false
    var previous: String? = nil
    var isCurrent = false
    var compact = false

    private var from: String { previous ?? installed }
    private var to: String { previous == nil ? (available ?? "Unknown") : installed }
    private var color: Color { previous == nil ? Palette.warning : Palette.success }

    var body: some View {
        Group {
            if comparesVersions || previous != nil {
                if compact {
                    pair
                } else {
                    ViewThatFits(in: .horizontal) {
                        pair.fixedSize()
                        VStack(alignment: .trailing, spacing: 5) {
                            labeledVersion(previous == nil ? "Installed" : "Previous", from, color: .secondary)
                            labeledVersion(previous == nil ? "Available" : "Installed", to, color: color)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(installed).lineLimit(compact ? 1 : nil).truncationMode(.head)
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .accessibilityLabel("Up to date")
                    }
                }
            }
        }
        .font(compact ? .caption : .callout)
        .monospacedDigit()
        .help((previous.map { "Previous: \($0)\n" } ?? "")
              + "Installed: \(installed)\nAvailable: \(available ?? "Unknown")")
        .accessibilityElement(children: .combine)
    }

    private var pair: some View {
        HStack(spacing: 5) {
            Text(from).foregroundStyle(.secondary)
                .strikethrough(previous != nil)
                .lineLimit(1).truncationMode(.head)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(color)
                .accessibilityHidden(true)
            Text(to).foregroundStyle(color).fontWeight(.medium)
                .lineLimit(1).truncationMode(.head)
        }
    }

    private func labeledVersion(_ label: String, _ version: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(version).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct VersionView: View {
    let agent: Agent
    let phase: RowPhase
    var compact = false

    var body: some View {
        VersionNumbers(installed: agent.installed ?? "Unknown",
                       available: agent.latest, comparesVersions: agent.status == .behind,
                       previous: previous, isCurrent: agent.status == .current, compact: compact)
    }

    private var previous: String? {
        if case .updated(let from) = phase { return from }
        return nil
    }
}

struct ActionButton: View {
    let agent: Agent
    let phase: RowPhase
    @Binding var showLog: Bool
    @Environment(AgentStore.self) private var store

    var body: some View {
        Group {
            switch phase {
            case .updating, .removing:
                ProgressView().controlSize(.small)
                    .accessibilityLabel("\(phase == .removing ? "Removing" : "Updating") \(agent.displayName)")
            case .failed:
                HStack(spacing: 6) {
                    Button("Retry") { store.retry(agent.name) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Retry updating \(agent.displayName)")
                    LogButton(name: agent.displayName) { showLog = true }
                }
            case .queued:
                Button("Cancel") { store.cancel(agent.name) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cancel queued update for \(agent.displayName)")
            case .updated, .installed, .staged:
                EmptyView()
            case .unchanged, .idle:
                if agent.status == .behind, agent.updater != nil {
                    Button("Update") { store.update(agent.name) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Update \(agent.displayName)")
                } else if agent.status == .behind {
                    Text("Manual update").font(.caption).foregroundStyle(.secondary)
                        .help("No automatic updater is available. See this agent's details.")
                }
            }
        }
        .font(.callout)
    }
}

private struct DetailField: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        GridRow(alignment: .top) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Details: View {
    let agent: Agent
    @Binding var showLog: Bool
    var onUninstall: () -> Void
    @Environment(AgentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                DetailField("Installed", agent.installed ?? "Unknown")
                DetailField("Available", agent.latest ?? "Couldn't check")
                DetailField("Command", agent.name)
                DetailField("Updater", agent.updater ?? "No automatic updater available")
                DetailField("Executable", agent.bin)
                DetailField("Location", agent.installPath)
                if let os = Platform.summary(agent.platforms, note: agent.platformNote) { DetailField("Runs on", os) }
                if let date = agent.lastUpdated {
                    DetailField("Last updated", date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption)
            HStack {
                if store.logs[agent.name] != nil {
                    Button("View Log", systemImage: "text.alignleft") { showLog = true }
                        .accessibilityLabel("View log for \(agent.displayName)")
                }
                Spacer()
                MoreButton(name: agent.displayName) {
                    AgentMenu(agent: agent, showLog: $showLog, onUninstall: onUninstall)
                }
            }
            .controlSize(.small)
        }
    }
}

struct AgentMenu: View {
    let agent: Agent
    @Binding var showLog: Bool
    var onUninstall: () -> Void
    @Environment(AgentStore.self) private var store

    var body: some View {
        if agent.updater != nil {
            Button("Force Update") { store.update(agent.name, force: true) }
                .disabled(store.phase(of: agent.name).isBusy)
        }
        Button("Reveal in Finder") { store.revealInFinder(agent) }
        Button("Copy Version") { store.copy(agent.installed ?? "") }.disabled(agent.installed == nil)
        if store.logs[agent.name] != nil { Button("View Log") { showLog = true } }
        Divider()
        Button(store.pinned.contains(agent.name) ? "Unpin" : "Pin — Skip Automatic Updates") { store.togglePinned(agent.name) }
        Button("Hide") { store.toggleHidden(agent.name) }
        Divider()
        Button(store.preparing.contains(agent.name) ? "Preparing Uninstall…" : "Uninstall…", role: .destructive) { onUninstall() }
            .disabled(store.phase(of: agent.name).isBusy || store.preparing.contains(agent.name))
    }
}

/// A compact "show the log" control that sits next to Retry.
struct LogButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "doc.text.magnifyingglass") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("View log for \(name)")
            .help("Show what the updater printed")
    }
}

// MARK: - Agent systems

struct SystemCard: View {
    let system: AgentSystem
    @Environment(AgentStore.self) private var store
    @AppStorage(Pref.compact) private var compact = true
    @State private var expanded = false
    @State private var uninstallPlan: [String]?
    @State private var showLog = false

    private var phase: RowPhase { store.phase(of: system.name) }
    private var status: Agent.Status {
        switch system.status {
        case .behind: .behind
        case .ahead: .ahead
        case .unknown: .unknown
        default: .current
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RowDisclosure(name: system.name, expanded: $expanded)
                AgentIcon(name: system.name, app: system.app, iconURL: system.iconURL, size: compact ? 28 : 40)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(system.name).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(2)
                            StatusPill(status: status, phase: phase)
                            if phase == .idle && system.status == .selfUpdating {
                                Label("Updates itself", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if phase == .idle && system.status == .web {
                                Label("Web & mobile", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                        if let installed = system.installed {
                            VersionNumbers(installed: installed, available: system.latest, comparesVersions: system.status == .behind,
                                           isCurrent: system.status == .current, compact: compact)
                                .frame(minWidth: 60, maxWidth: 200, alignment: .trailing)
                        }
                        if phase == .failed {
                            Button("View Log") { showLog = true }.buttonStyle(.bordered)
                        } else if phase.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(system.app == nil ? "Website" : "Open") { open() }
                                .buttonStyle(.bordered)
                                .help(system.status == .behind ? "Open \(system.name) to finish its update" : "Open \(system.name)")
                                .accessibilityLabel(system.app == nil ? "Website for \(system.name)" : "Open \(system.name)")
                        }
                    }
                    .controlSize(.small)
                    if !compact {
                        Text(system.description).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    Text(system.description).font(.callout).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                        if let version = system.installed { DetailField("Installed", version) }
                        if let latest = system.latest { DetailField("Available", latest) }
                        if let build = system.build { DetailField("Build", build) }
                        if let app = system.app { DetailField("Location", app) }
                        if let os = Platform.summary(system.platforms, note: system.platformNote) { DetailField("Runs on", os) }
                        if let date = system.lastUpdated {
                            DetailField("Last updated", date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .font(.caption)
                    HStack {
                        Button("Website", systemImage: "arrow.up.right") { store.open(system.homepage) }
                        Spacer()
                        MoreButton(name: system.name) { menuContent }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 30).padding(.top, 12)
            }
        }
        .modifier(RowChrome())
        .contextMenu { menuContent }
        .uninstallDialog(name: system.name, plan: $uninstallPlan)
        .sheet(isPresented: $showLog) { LogSheet(name: system.name) }
    }

    @ViewBuilder private var menuContent: some View {
        Button(system.app == nil ? "Open Website" : "Open \(system.name)") { open() }
        if let version = system.installed { Button("Copy Version") { store.copy(version) } }
        if store.logs[system.name] != nil { Button("View Log") { showLog = true } }
        Button("Hide") { store.toggleHidden(system.name) }
        if let app = system.app {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app)]) }
            Divider()
            Button(store.preparing.contains(system.name) ? "Preparing…" : "Move to Trash…", role: .destructive) {
                Task { uninstallPlan = await store.uninstallPlan(system.name) }
            }
            .disabled(phase.isBusy || store.preparing.contains(system.name))
        }
    }

    private func open() {
        if let app = system.app {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app), configuration: .init())
        } else {
            store.open(system.homepage)
        }
    }
}

// MARK: - Discover

struct DiscoverList: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        if store.platformFilter != nil && store.visibleAvailable.isEmpty && !store.available.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                PlatformFilter()
                ContentUnavailableView("Nothing for \(Platform.label(store.platformFilter ?? ""))",
                                       systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                                       description: Text("No tool you don't have yet is confirmed to run there."))
            }
        } else if !store.searchText.isEmpty && store.visibleAvailable.isEmpty && !store.available.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else if store.visibleAvailable.isEmpty {
            ContentUnavailableView {
                Label("You Have Them All", systemImage: "square.stack.3d.up")
            } description: { Text("Every agent on the popular list is installed.") }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                PlatformFilter()
                ForEach(AgentKind.allCases) { kind in
                    let group = store.visibleAvailable.filter { $0.role == kind }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(kind: kind, count: group.count)
                            GroupSurface {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { RowSeparator() }
                                    DiscoverCard(item: item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DiscoverCard: View {
    let item: CatalogAgent
    @Environment(AgentStore.self) private var store
    @AppStorage(Pref.compact) private var compact = true
    @State private var expanded = false
    @State private var showLog = false
    @State private var confirmInstall = false

    private var phase: RowPhase { store.phase(of: item.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RowDisclosure(name: item.displayName, expanded: $expanded)
                AgentIcon(catalog: item, size: compact ? 28 : 40)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.displayName).font(.system(.body, design: .rounded).weight(.semibold))
                        if let version = item.latest {
                            Text(version).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head).help(version)
                        }
                    }
                    Text(item.description).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 3).fixedSize(horizontal: false, vertical: true)
                    PlatformChips(platforms: item.platforms, note: item.platformNote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                getAction.fixedSize()
            }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    Text(item.description).font(.callout).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                        DetailField("Command", item.name)
                        if let version = item.latest { DetailField("Available", version) }
                        DetailField("Install with", item.install)
                        if let os = Platform.summary(item.platforms, note: item.platformNote) { DetailField("Runs on", os) }
                    }
                    .font(.caption)
                    HStack {
                        Button("Website", systemImage: "arrow.up.right") { store.open(item.homepage) }
                            .accessibilityLabel("Website for \(item.displayName)")
                        Spacer()
                        MoreButton(name: item.displayName) { menuContent }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 30).padding(.top, 12)
            }
        }
        .modifier(RowChrome())
        .contextMenu { menuContent }
        .sheet(isPresented: $showLog) { LogSheet(name: item.name) }
        .confirmationDialog("Install \(item.displayName)?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Install") { store.install(item.name) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs:\n\(item.install)\n\nIt installs \(item.displayName) for your user account. You can uninstall it from Agent Updater later.")
        }
    }

    @ViewBuilder private var getAction: some View {
        switch phase {
        case .queued:
            Button("Cancel") { store.cancel(item.name) }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Cancel installing \(item.displayName)")
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Installing").font(.caption)
            }
            .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 6) {
                Button("Retry") { store.retry(item.name) }.buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("Retry installing \(item.displayName)")
                LogButton(name: item.displayName) { showLog = true }
            }
        case .installed:
            Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
        default:
            Button(action: askInstall) { Text("Get").fontWeight(.semibold).frame(minWidth: 40) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.secondary)
                .controlSize(.small)
                .accessibilityLabel("Get \(item.displayName)")
        }
    }

    @ViewBuilder private var menuContent: some View {
        Button("Get \(item.displayName)", action: askInstall).disabled(phase.isBusy)
        Button("Open Website") { store.open(item.homepage) }
        Button("Copy Install Command") { store.copy(item.install) }
        if store.logs[item.name] != nil { Button("View Log") { showLog = true } }
    }

    /// Get and the context menu both confirm first, showing the exact command (PLAN D15).
    private func askInstall() { confirmInstall = true }
}

// MARK: - Platforms

/// Small "macOS · Linux · Windows" chips, with the note (e.g. "Windows via WSL only") as a tooltip.
struct PlatformChips: View {
    let platforms: [String]?
    let note: String?

    var body: some View {
        let known = Platform.order.filter { (platforms ?? []).contains($0) }
        if !known.isEmpty {
            HStack(spacing: 4) {
                ForEach(known, id: \.self) { id in
                    Text(Platform.label(id))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .foregroundStyle(.secondary)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
                if let note, !note.isEmpty {
                    Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .help(Platform.summary(platforms, note: note) ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Runs on " + (Platform.summary(platforms, note: note) ?? "unknown"))
        }
    }
}

/// Discover's "Runs on" filter.
struct PlatformFilter: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Text("Runs on").font(.caption).foregroundStyle(.secondary)
            ForEach([nil, "macos", "linux", "windows"], id: \.self) { (id: String?) in
                let selected = store.platformFilter == id
                Button {
                    withAnimation(Motion.quick) { store.platformFilter = id }
                } label: {
                    Text(id.map(Platform.label) ?? "Any")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .background(selected ? AnyShapeStyle(Palette.accent2.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by operating system")
    }
}
