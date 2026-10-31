import AppKit
import SwiftUI

// MARK: - Window

struct ContentView: View {
    @Environment(AgentStore.self) private var store
    @AppStorage("compact") private var compact = true
    @AppStorage(Pref.showDiscover) private var showDiscover = true
    @AppStorage(Pref.appearance) private var appearance: Appearance = .system
    @AppStorage(Pref.theme) private var themeID = "system"
    @AppStorage(Pref.autoUpdate) private var autoUpdate = false
    @AppStorage(Pref.sounds) private var sounds = true
    @AppStorage(Pref.menuBar) private var menuBar = false
    @AppStorage(Pref.showInDock) private var showInDock = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        Scrolling {
            VStack(alignment: .leading, spacing: 18) {
                if store.hasLoaded, let error = store.errorMessage {
                    RefreshFailedBanner(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if store.hasLoaded || store.isChecking {
                    StatusHero()
                }
                listContent
                    .animation(nil, value: store.hasLoaded)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .animation(Motion.standard, value: store.filter)
            .animation(Motion.standard, value: store.errorMessage)
        }
        .safeAreaBar(edge: .top) { filterBar }
        .navigationTitle("Agent Updater")
        .navigationSubtitle(store.statusLine)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFocused)
        .onChange(of: store.searchFocusRequest) { searchFocused = true }
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { ToastView() }
        .onChange(of: showDiscover) { _, on in if !on && store.filter == .discover { store.filter = .all } }
    }

    // MARK: Toolbar

    /// The filter lives in a slim bar under the toolbar so the title, status and actions never
    /// overflow at 560–660 pt (PLAN D1 fallback, agreed with Codex).
    private var filterBar: some View {
        HStack {
            FilterTabs()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // Pass the status in: toolbar items don't reliably re-render from the store on their own.
            WindowTitle(status: store.statusLine, dot: titleDotColor, working: store.isChecking || store.currentJob != nil)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .disabled(store.isChecking)
            .help(lastCheckedHelp)
            .accessibilityHint(lastCheckedHelp)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        if store.queuedCount > 0 {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.cancelQueued()
                } label: {
                    Label("Stop After Current", systemImage: "stop.circle")
                }
                .help("Finish the update that's running, then stop")
            }
        }
        if !store.updatableBehind.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.updateAllBehind()
                } label: {
                    Label("Update \(store.updatableBehind.count)", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.warning)
                .help(updateAllHelp)
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Theme", selection: $themeID) {
                    ForEach(Theme.all) { Text($0.name).tag($0.id) }
                }
                Toggle("Compact Layout", isOn: $compact.animation(Motion.standard))
                Divider()
                Section("Quick Settings") {
                    Toggle("Update Automatically", isOn: Binding(get: { autoUpdate }, set: { on in
                        autoUpdate = on
                        if on { Task { await store.refresh() } } // apply it now, not at the next check
                    }))
                    Toggle("Sound Effects", isOn: $sounds)
                    Toggle("Show in Menu Bar", isOn: $menuBar).disabled(!showInDock)
                    Toggle("Show in Dock", isOn: Binding(get: { showInDock }, set: { showInDock = $0; DockPresence.apply() }))
                }
                Divider()
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
            } label: {
                Label("View Options", systemImage: "slider.horizontal.3")
            }
            .help("Appearance, layout and Settings")
        }
    }

    private var titleDotColor: Color {
        if store.isChecking || store.currentJob != nil { return Palette.accent }
        if !store.hasLoaded || store.errorMessage != nil { return store.hasLoaded ? Palette.warning : .secondary }
        return store.updatesCount > 0 ? Palette.warning : Palette.success
    }

    private var lastCheckedHelp: String {
        guard let checked = store.lastChecked else { return "Check every agent against its latest release (⌘R)" }
        return "Last checked \(checked.formatted(.relative(presentation: .named))) (⌘R)"
    }

    private var updateAllHelp: String {
        let behind = store.activeAgents.filter { $0.status == .behind }
        if !store.updatableBehind.isEmpty { return "Update every agent that has an update, one at a time (⇧⌘U)" }
        if behind.isEmpty { return store.systemsBehind.isEmpty ? "Nothing to update" : "Agent system apps update themselves; open them to finish" }
        return "The agents with updates are pinned or have no updater"
    }

    // MARK: List

    @ViewBuilder
    private var listContent: some View {
        if !store.hasLoaded {
            if store.errorMessage != nil {
                LoadFailedView()
            } else {
                SkeletonList()
            }
        } else if store.filter == .discover {
            DiscoverList()
                .transition(.opacity)
        } else if !store.searchText.isEmpty && store.visibleAgents.isEmpty && store.visibleSystems.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else if store.agents.isEmpty && store.systems.isEmpty {
            EmptyStateView(kind: .nothingInstalled)
        } else if store.installedCount == 0 {
            EmptyStateView(kind: .allHidden)
        } else if store.visibleAgents.isEmpty && store.visibleSystems.isEmpty {
            EmptyStateView(kind: store.unknownCount > 0 ? .noUpdatesSomeUnknown : .allCurrent)
        } else {
            sections
        }
    }

    @ViewBuilder
    /// Each group lists its command-line tools first, then its desktop apps (Rex sits with the
    /// orchestrators, Grok Bot and Muse with the agent systems).
    private var sections: some View {
        ForEach(AgentKind.allCases) { kind in
            let group = store.visibleAgents.filter { $0.role == kind }
            let apps = store.visibleSystems.filter { $0.role == kind }
            if !group.isEmpty || !apps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(kind: kind, count: group.count + apps.count)
                    GroupSurface {
                        AgentRows(agents: group)
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, system in
                            if index > 0 || !group.isEmpty { RowSeparator() }
                            SystemCard(system: system)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// A top-anchored ScrollView, or a plain stack when rendering a snapshot (cacheDisplay can't
/// draw scroll view contents reliably).
struct Scrolling<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if Snapshot.isRequested {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }
                .scrollContentBackground(.hidden)
        }
    }
}

/// Shows "Uninstall NAME?" with exactly what will be removed, once `plan` is loaded.
struct UninstallDialog: ViewModifier {
    let name: String
    @Binding var plan: [String]?
    @Environment(AgentStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog("Uninstall \(DisplayName.of(name))?", isPresented: Binding(
            get: { plan != nil },
            set: { if !$0 { plan = nil } }
        ), titleVisibility: .visible) {
            if canUninstall {
                Button(runsCommand ? "Uninstall" : "Move to Trash", role: .destructive) { store.uninstall(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private var lines: [String] { plan ?? [] }
    private var runsCommand: Bool { lines.contains { $0.hasPrefix("cmd:") } }
    private var canUninstall: Bool { !lines.isEmpty && !lines.contains { $0.hasPrefix("error:") } }

    private var message: String {
        if let error = lines.first(where: { $0.hasPrefix("error:") }) {
            return "Can't uninstall: " + error.dropFirst(6) + "."
        }
        if lines.isEmpty { return "Nothing to remove." }
        let home = NSHomeDirectory()
        var parts: [String] = []
        let commands = lines.filter { $0.hasPrefix("cmd:") }.map { "Runs " + $0.dropFirst(4) }
        if !commands.isEmpty { parts.append(commands.joined(separator: "\n")) }
        let paths = lines.filter { $0.hasPrefix("path:") }
            .map { String($0.dropFirst(5)).replacingOccurrences(of: home, with: "~") }
        if !paths.isEmpty {
            parts.append("Moves to the Trash, so you can put it back:\n" + paths.joined(separator: "\n"))
        }
        parts.append("Settings and history are kept. Quit running sessions first.")
        return parts.joined(separator: "\n\n")
    }
}

extension View {
    func uninstallDialog(name: String, plan: Binding<[String]?>) -> some View {
        modifier(UninstallDialog(name: name, plan: plan))
    }
}

struct UpdatedLabel: View {
    let date: Date?
    var short = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
            if let date {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(short
                         ? date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
                         : "Updated \(date.formatted(.relative(presentation: .named)))")
                }
                .help(date.formatted(date: .complete, time: .shortened))
            } else {
                Text(short ? "—" : "Install date unknown")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct LogSheet: View {
    let name: String
    @Environment(AgentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AgentIcon(name: name, size: 28)
                Text("\(DisplayName.of(name)) Log").font(.headline)
                Spacer()
                Button("Copy") { store.copy(store.logs[name] ?? "") }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(store.logs[name] ?? "No log yet.")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .frame(width: 620, height: 420)
    }
}

struct SectionHeader: View {
    let kind: AgentKind
    let count: Int
    @AppStorage("compact") private var compact = true

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: kind.tint.opacity(0.3), radius: 2, y: 1)
                .accessibilityHidden(true)
            Text(kind.title).font(.system(compact ? .headline : .title3, design: .rounded).weight(.semibold))
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .contentTransition(.numericText())
            Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.top, 4)
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Title and tabs

/// The window title, drawn by us: app icon, name, and the status line with a colored dot.
/// (The system title is hidden so this doesn't show twice; navigationTitle still names the window.)
struct WindowTitle: View {
    let status: String
    let dot: Color
    let working: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Updater")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(dot.gradient)
                        .frame(width: 7, height: 7)
                        .scaleEffect(working && pulse ? 1.35 : 1)
                        .opacity(working && pulse ? 0.6 : 1)
                        .animation(working && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                                   value: pulse)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 4)
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent Updater, \(status)")
    }
}

/// All / Updates / Discover as pill tabs with a sliding, colored selection.
struct FilterTabs: View {
    @Environment(AgentStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Pref.showDiscover) private var showDiscover = true
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            tab(.all, "All", symbol: "square.grid.2x2.fill", tint: Palette.accent, shortcut: "⌘1")
            tab(.behind, "Updates", symbol: "arrow.down.circle.fill", tint: Palette.warning, count: store.updatesCount, shortcut: "⌘2")
            if showDiscover {
                tab(.discover, "Discover", symbol: "sparkles", tint: Palette.accent2, shortcut: "⌘3")
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    private func tab(_ filter: Filter, _ title: String, symbol: String, tint: Color,
                     count: Int = 0, shortcut: String) -> some View {
        let selected = store.filter == filter
        return Button {
            withAnimation(reduceMotion ? nil : Motion.standard) { store.filter = filter }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .foregroundStyle(.white)
                        .background(selected ? AnyShapeStyle(.white.opacity(0.28)) : AnyShapeStyle(tint.gradient), in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.8)))
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: tint.opacity(0.35), radius: 5, y: 2)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(title) (\(shortcut))")
    }
}

// MARK: - Status hero

/// The colorful card at the top of the list: what's going on, at a glance, with the one action
/// that matters. Its color follows the state: green (all current), orange (updates ready),
/// blue (checking or working), purple (Discover), amber (couldn't refresh).
struct StatusHero: View {
    @Environment(AgentStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Pref.compact) private var compact = true

    private struct Look {
        var colors: [Color]
        var symbol: String
        var title: String
        var detail: String
    }

    var body: some View {
        let look = self.look
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: compact ? 12 : 16) {
                badge(look)
                VStack(alignment: .leading, spacing: 3) {
                    Text(look.title)
                        .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Text(look.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1) // the words win; chips give way when space is tight
                Spacer(minLength: 8)
                trailing
            }
            if store.currentJob != nil, store.runTotal > 1 {
                ProgressView(value: Double(store.runDone), total: Double(store.runTotal))
                    .tint(look.colors[0])
                    .accessibilityLabel("Update progress")
            }
        }
        .padding(compact ? 14 : 18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.surface.opacity(scheme == .dark ? 0.7 : 0.85))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [look.colors[0].opacity(scheme == .dark ? 0.28 : 0.20),
                                                  look.colors[1].opacity(scheme == .dark ? 0.12 : 0.07)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [look.colors[0].opacity(0.45), look.colors[1].opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : Motion.standard, value: look.title)
        .accessibilityElement(children: .contain)
    }

    private func badge(_ look: Look) -> some View {
        let size: CGFloat = compact ? 44 : 54
        return ZStack {
            Circle().fill(LinearGradient(colors: look.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Image(systemName: look.symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isWorking && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .shadow(color: look.colors[0].opacity(0.35), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var trailing: some View {
        if store.filter != .discover, store.currentJob == nil, !store.updatableBehind.isEmpty {
            Button {
                store.updateAllBehind()
            } label: {
                Label("Update \(store.updatableBehind.count)", systemImage: "arrow.down.circle.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Palette.warning)
            .controlSize(.large)
            .help("Update every agent that has an update, one at a time (⇧⌘U)")
        } else if !isWorking {
            // Full chips, then one total, then nothing: never squeeze the numbers.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }.fixedSize()
                totalChip.fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(AgentKind.allCases) { kind in
            let count = chipCount(kind)
            if count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: kind.symbol).font(.system(size: 9, weight: .bold))
                    Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(kind.tint)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(kind.tint.opacity(0.12), in: Capsule())
                .fixedSize()
                .help("\(count) \(kind.title.lowercased())")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) \(kind.title.lowercased())")
            }
        }
    }

    /// The fallback when the per-group chips don't fit: one chip with the total.
    private var totalChip: some View {
        let total = AgentKind.allCases.map(chipCount).reduce(0, +)
        return HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9, weight: .bold))
            Text("\(total)").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .help("\(total) tools")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) tools")
    }

    private func chipCount(_ kind: AgentKind) -> Int {
        if store.filter == .discover { return store.visibleAvailable.filter { $0.role == kind }.count }
        return store.activeAgents.filter { $0.role == kind }.count + store.activeSystems.filter { $0.role == kind }.count
    }

    private var isWorking: Bool { store.isChecking || store.currentJob != nil }

    private var look: Look {
        if let job = store.currentJob {
            let detail = store.runTotal > 1 ? "\(store.runDone + 1) of \(store.runTotal) · one at a time" : "This usually takes under a minute"
            return Look(colors: [Palette.accent, Palette.accent2], symbol: "arrow.triangle.2.circlepath",
                        title: "\(store.statusLine.components(separatedBy: " · ").first ?? DisplayName.of(job))", detail: detail)
        }
        if store.isChecking {
            return Look(colors: [Palette.accent, Palette.accent2], symbol: "arrow.triangle.2.circlepath",
                        title: "Checking for updates…", detail: "Asking each agent's release feed")
        }
        if store.filter == .discover {
            let n = store.visibleAvailable.count
            return Look(colors: [Palette.accent2, Palette.accent3], symbol: "sparkles", title: "Discover",
                        detail: n == 1 ? "1 popular tool you don't have yet" : "\(n) popular tools you don't have yet")
        }
        if store.errorMessage != nil {
            return Look(colors: [Palette.warning, Palette.caution], symbol: "exclamationmark.triangle.fill",
                        title: "Couldn't refresh", detail: "Showing the results of the last check")
        }
        let updates = store.updatesCount
        if updates > 0 {
            let names = (store.activeAgents.filter { $0.status == .behind }.map(\.displayName)
                         + store.systemsBehind.map(\.name))
            let shown = names.count > 3 ? names.prefix(3) + ["\(names.count - 3) more"] : names[...]
            return Look(colors: [Palette.warning, Palette.danger], symbol: "arrow.down.circle.fill",
                        title: updates == 1 ? "1 update ready" : "\(updates) updates ready",
                        detail: Array(shown).formatted(.list(type: .and)))
        }
        var detail = "\(store.installedCount) tools"
        if let checked = store.lastChecked { detail += " · checked \(checked.formatted(.relative(presentation: .named)))" }
        if store.unknownCount > 0 { detail += " · \(store.unknownCount) couldn't be checked" }
        if UserDefaults.standard.bool(forKey: Pref.autoUpdate) { detail += " · auto-update on" }
        return Look(colors: [Palette.success, Palette.info], symbol: "checkmark.seal.fill",
                    title: "Everything's up to date", detail: detail)
    }
}

// MARK: - Toast

/// A short confirmation at the bottom of the window ("Installed OpenCode", "Uninstalled Amp").
struct ToastView: View {
    @Environment(AgentStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let toast = store.toast {
            Label(toast.message, systemImage: toast.symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(toast.isError ? Palette.warning : .primary)
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 18)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear {
                    AccessibilityNotification.Announcement(toast.message).post()
                }
        }
    }
}

// MARK: - States

struct SkeletonList: View {
    @AppStorage("compact") private var compact = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Capsule().frame(width: 140, height: 12).padding(.bottom, 4)
            ForEach(0..<7, id: \.self) { index in
                HStack(spacing: compact ? 10 : 14) {
                    RoundedRectangle(cornerRadius: compact ? 7 : 11)
                        .frame(width: compact ? 28 : 46, height: compact ? 28 : 46)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().frame(width: 110, height: 11)
                        if !compact { Capsule().frame(width: 160, height: 8) }
                    }
                    Spacer()
                    Capsule().frame(width: 80, height: 10)
                }
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 9 : 14)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: compact ? 12 : 18))
                .opacity(1 - Double(index) * 0.1)
            }
        }
        .foregroundStyle(.quaternary)
        .phaseAnimator(reduceMotion ? [1.0] : [0.55, 1.0]) { view, opacity in
            view.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 1.1) }
        .accessibilityElement()
        .accessibilityLabel("Checking installed agents")
    }
}

/// The first check failed, so there's nothing to show yet.
struct LoadFailedView: View {
    @Environment(AgentStore.self) private var store
    @State private var showDetails = false

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Check for Updates", systemImage: "exclamationmark.icloud")
        } description: {
            Text("\(store.errorMessage ?? "Something went wrong.") Check your connection and try again.")
        } actions: {
            Button("Try Again") { Task { await store.refresh() } }
                .buttonStyle(.glassProminent)
                .disabled(store.isChecking)
            if let detail = store.errorDetail, !detail.isEmpty {
                DisclosureGroup("Details", isExpanded: $showDetails) {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 420)
            }
        }
        .padding(.top, 40)
    }
}

/// A later check failed; the list below is the last good result.
struct RefreshFailedBanner: View {
    let message: String
    @Environment(AgentStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't refresh").font(.callout.weight(.semibold))
                Text(lastGood).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Try Again") { Task { await store.refresh() } }
                .disabled(store.isChecking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.warning.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.warning.opacity(0.25)))
        .help(store.errorDetail ?? message)
        .accessibilityElement(children: .contain)
    }

    private var lastGood: String {
        guard let checked = store.lastChecked else { return message }
        return "\(message) Showing results from \(checked.formatted(date: .omitted, time: .shortened))."
    }
}

struct EmptyStateView: View {
    enum Kind { case nothingInstalled, allHidden, allCurrent, noUpdatesSomeUnknown }
    let kind: Kind
    @Environment(AgentStore.self) private var store
    @AppStorage(Pref.showDiscover) private var showDiscover = true

    var body: some View {
        switch kind {
        case .nothingInstalled:
            ContentUnavailableView {
                Label("No Agents Installed", systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("None of the coding agents this app knows about are installed yet.")
            } actions: {
                if showDiscover {
                    Button("Browse Popular Agents") { store.filter = .discover }.buttonStyle(.glassProminent)
                }
            }
        case .allHidden:
            ContentUnavailableView {
                Label("Everything Is Hidden", systemImage: "eye.slash")
            } description: {
                Text("You've hidden every agent. Hidden agents stay installed and can be shown again in Settings.")
            } actions: {
                SettingsLink { Text("Show Hidden Agents…") }
            }
        case .allCurrent:
            ContentUnavailableView {
                Label("Everything Is Up to Date", systemImage: "checkmark.seal")
            } description: {
                Text("Every agent matches its latest release.")
            }
        case .noUpdatesSomeUnknown:
            ContentUnavailableView {
                Label("No Updates Available", systemImage: "checkmark.circle")
            } description: {
                Text(store.unknownCount == 1
                     ? "1 agent couldn't be checked, so it might still have an update."
                     : "\(store.unknownCount) agents couldn't be checked, so they might still have updates.")
            } actions: {
                Button("Show All Agents") { store.filter = .all }
            }
        }
    }
}
