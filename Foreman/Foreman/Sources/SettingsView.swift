import AppKit
import ForemanCore
import SwiftUI

/// Global settings, laid out like a modern macOS System Settings window: a
/// `NavigationSplitView` sidebar selects one of three panes.
///
/// - **General** — launch Foreman at login.
/// - **Repositories** — the directory scanned for git repositories.
/// - **Agent** — which `cursor-agent` executable to run.
///
/// Hosted by the `Settings` scene (app menu / Cmd-, / the toolbar's
/// `SettingsLink`), so it follows settings-window conventions: edits apply on
/// commit (Return / focus change / panel selection / a toggle flip) — no Save
/// button. Values write through the observable Core (`AppSettings` for the
/// paths, `LoginItemController` for the login item), which persists.
struct SettingsView: View {
    /// The sidebar panes. `Identifiable` (via `id: \.self`) so the sidebar
    /// `List` can iterate `allCases`.
    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case repositories
        case agent

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .general: "General"
                case .repositories: "Repositories"
                case .agent: "Agent"
            }
        }

        var symbol: String {
            switch self {
                case .general: "gearshape"
                case .repositories: "folder"
                case .agent: "terminal"
            }
        }
    }

    let session: ForemanSession

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol)
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detail
        }
        .frame(minWidth: 620, minHeight: 380)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
            // No selection falls back to General — the sidebar always has a
            // meaningful pane on screen.
            case .general, .none:
                GeneralSettingsView(session: session)
            case .repositories:
                RepositoriesSettingsView(session: session)
            case .agent:
                AgentSettingsView(session: session)
        }
    }
}

/// General preferences: whether Foreman launches at login.
private struct GeneralSettingsView: View {
    @Bindable var session: ForemanSession

    @State private var isWindowVisible = true

    var body: some View {
        Form {
            Toggle("Launch Foreman at login", isOn: $session.startsAtLogin)
            Text(
                "Foreman lives in the menu bar. Turn this on to start it automatically when you log in — it will restore any enabled workers.",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        // The OS owns the login-item state and the user can change it in
        // System Settings, so re-read it whenever this pane comes back on
        // screen. The Settings window keeps its hierarchy across opens.
        .onAppear { session.refreshLoginItemStatus() }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        .onChange(of: isWindowVisible) { _, visible in
            if visible { session.refreshLoginItemStatus() }
        }
    }
}

/// Repository discovery: where to scan for git repositories.
private struct RepositoriesSettingsView: View {
    let session: ForemanSession

    @State private var scanDirectory: String
    @State private var isWindowVisible = true
    @FocusState private var isFocused: Bool

    init(session: ForemanSession) {
        self.session = session
        _scanDirectory = State(initialValue: session.settings.scanDirectory?.path ?? "")
    }

    var body: some View {
        Form {
            LabeledContent("Scan directory") {
                HStack(spacing: 4) {
                    TextField(
                        "Scan directory",
                        text: $scanDirectory,
                        prompt: Text("~/Development"),
                    )
                    .labelsHidden()
                    .focused($isFocused)
                    .onSubmit { apply() }
                    Button("Choose…") { chooseScanDirectory() }
                }
            }
            Text("Foreman lists the git repositories directly inside this directory.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Repositories")
        // Tabbing or clicking out of the field commits it, like Return does.
        .onChange(of: isFocused) { _, focused in
            if !focused { apply() }
        }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        // The Settings window keeps its hierarchy across opens, so init-time
        // drafts go stale; re-seed whenever the window comes back.
        .onChange(of: isWindowVisible) { _, visible in
            if visible { scanDirectory = session.settings.scanDirectory?.path ?? "" }
        }
    }

    private func apply() {
        session.settings.scanDirectory = parseURL(from: scanDirectory)
    }

    private func chooseScanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.settings.resolvedScanDirectory
        if panel.runModal() == .OK, let url = panel.url {
            scanDirectory = url.path
            apply()
        }
    }
}

/// Agent settings: which `cursor-agent` executable to run.
private struct AgentSettingsView: View {
    let session: ForemanSession

    @State private var agentExecutable: String
    @State private var isWindowVisible = true
    @FocusState private var isFocused: Bool

    init(session: ForemanSession) {
        self.session = session
        _agentExecutable = State(initialValue: session.settings.agentExecutable?.path ?? "")
    }

    var body: some View {
        Form {
            LabeledContent("cursor-agent") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        "cursor-agent executable",
                        text: $agentExecutable,
                        prompt: Text("Auto-detect"),
                    )
                    .labelsHidden()
                    .focused($isFocused)
                    .onSubmit { apply() }
                    Text(
                        "Leave empty to search: \(CursorAgentLocator.defaultSearchPaths.joined(separator: ", "))",
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Agent")
        .onChange(of: isFocused) { _, focused in
            if !focused { apply() }
        }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        .onChange(of: isWindowVisible) { _, visible in
            if visible { agentExecutable = session.settings.agentExecutable?.path ?? "" }
        }
    }

    private func apply() {
        session.settings.agentExecutable = parseURL(from: agentExecutable)
    }
}

/// Empty means "use the default" (`nil`); otherwise a tilde-expanded file URL.
private func parseURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
}

#if DEBUG
    #Preview {
        SettingsView(session: PreviewSupport.emptySession())
    }
#endif
