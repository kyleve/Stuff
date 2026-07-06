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
        // The sidebar is always open: pin the visibility and drop the default
        // sidebar-toggle button so the panes can't be collapsed away.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol)
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(minWidth: 420, minHeight: 380)
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

            // Registered but macOS is waiting for the user to approve it.
            if session.loginItemNeedsApproval {
                LabeledContent {
                    Button("Open Login Items…") {
                        session.openSystemSettingsLoginItems()
                    }
                } label: {
                    Label(
                        "Approve Foreman in System Settings to finish enabling this.",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
            }

            // A failed register/unregister — shown here (not the main-window
            // banner) because the toggle lives in this window.
            if let error = session.loginItemError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
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

/// Repository discovery: where to scan for git repositories. The value is
/// read-only here; editing happens in an explicit-commit sheet so switching
/// panes can't drop a half-typed path.
private struct RepositoriesSettingsView: View {
    let session: ForemanSession

    @State private var isEditing = false

    var body: some View {
        Form {
            LabeledContent("Scan directory") {
                Text(session.settings.scanDirectory?.path ?? "~/Development (default)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Change…") { isEditing = true }
            Text("Foreman lists the git repositories directly inside this directory.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("Repositories")
        .sheet(isPresented: $isEditing) {
            PathEditorSheet(
                title: "Scan directory",
                prompt: "~/Development",
                caption: "Leave empty to use the default (~/Development).",
                directoryPickerStart: session.settings.resolvedScanDirectory,
                initialValue: session.settings.scanDirectory?.path ?? "",
                onSave: { session.settings.scanDirectory = $0 },
            )
        }
    }
}

/// Agent settings: which `cursor-agent` executable to run. Read-only here;
/// edited via an explicit-commit sheet (see `RepositoriesSettingsView`).
private struct AgentSettingsView: View {
    let session: ForemanSession

    @State private var isEditing = false

    var body: some View {
        Form {
            LabeledContent("cursor-agent") {
                Text(session.settings.agentExecutable?.path ?? "Auto-detect")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Change…") { isEditing = true }
            Text(
                "Leave empty to search: \(CursorAgentLocator.defaultSearchPaths.joined(separator: ", "))",
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .navigationTitle("Agent")
        .sheet(isPresented: $isEditing) {
            PathEditorSheet(
                title: "cursor-agent executable",
                prompt: "Auto-detect",
                caption: "Leave empty to auto-detect from the known install locations.",
                directoryPickerStart: nil,
                initialValue: session.settings.agentExecutable?.path ?? "",
                onSave: { session.settings.agentExecutable = $0 },
            )
        }
    }
}

/// A modal editor for a single optional path setting. The draft only commits
/// when the user taps Save (Cancel/Escape discards it), so there is no
/// commit-on-blur and no way to lose a half-typed value by navigating away.
/// Empty commits as `nil` (the setting's default).
private struct PathEditorSheet: View {
    let title: String
    let prompt: String
    let caption: String
    /// When non-nil, shows a "Choose…" folder picker starting at this URL.
    let directoryPickerStart: URL?
    let initialValue: String
    let onSave: (URL?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        title: String,
        prompt: String,
        caption: String,
        directoryPickerStart: URL?,
        initialValue: String,
        onSave: @escaping (URL?) -> Void,
    ) {
        self.title = title
        self.prompt = prompt
        self.caption = caption
        self.directoryPickerStart = directoryPickerStart
        self.initialValue = initialValue
        self.onSave = onSave
        _draft = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                TextField(title, text: $draft, prompt: Text(prompt))
                    .labelsHidden()
                    .focused($isFocused)
                    .onSubmit { save() }
                if directoryPickerStart != nil {
                    Button("Choose…") { choose() }
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { isFocused = true }
    }

    private func save() {
        onSave(parseURL(from: draft))
        dismiss()
    }

    private func choose() {
        guard let directoryPickerStart else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryPickerStart
        if panel.runModal() == .OK, let url = panel.url {
            draft = url.path
        }
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
