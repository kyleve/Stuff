import AppKit
import ForemanCore
import SwiftUI

/// A pane in the settings sidebar: static identity/metadata plus its own
/// content view, built from the session. Conformers are ordinary `View`s;
/// `SettingsView` discovers their title/icon and builds them without a central
/// enum or switch.
private protocol SettingsPane: View {
    /// Sidebar label and navigation title.
    static var title: String { get }
    /// Sidebar SF Symbol.
    static var icon: String { get }

    init(session: ForemanSession)
}

/// Type-erased sidebar entry: a pane's metadata plus a builder for its content.
/// Keyed by the pane type's `ObjectIdentifier`, so the sidebar selection stays
/// a typed token rather than a stringly value.
private struct SettingsPaneItem: Identifiable {
    let id: ObjectIdentifier
    let title: String
    let icon: String
    let makeView: (ForemanSession) -> AnyView

    init(_ pane: (some SettingsPane).Type) {
        id = ObjectIdentifier(pane)
        title = pane.title
        icon = pane.icon
        makeView = { AnyView(pane.init(session: $0)) }
    }
}

/// Global settings, laid out like a modern macOS System Settings window: a
/// `NavigationSplitView` sidebar over the registered ``SettingsPaneItem``s.
///
/// Hosted by the `Settings` scene (app menu / Cmd-, / the toolbar's
/// `SettingsLink`), so it follows settings-window conventions: the toggle in
/// General applies immediately, and the path panes commit through an explicit
/// Save/Cancel sheet. Values write through the observable Core (`AppSettings`
/// for the paths, `LoginItemController` for the login item), which persists.
struct SettingsView: View {
    let session: ForemanSession

    private let panes: [SettingsPaneItem] = [
        SettingsPaneItem(GeneralSettingsPane.self),
        SettingsPaneItem(RepositoriesSettingsPane.self),
        SettingsPaneItem(AgentSettingsPane.self),
    ]

    @State private var selection: ObjectIdentifier?

    var body: some View {
        // The sidebar is always open: pin the visibility and drop the default
        // sidebar-toggle button so the panes can't be collapsed away.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(panes, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            if selection == nil { selection = panes.first?.id }
        }
    }

    /// The selected pane's content, falling back to the first pane so the
    /// detail always shows something meaningful.
    private var detail: AnyView {
        let pane = panes.first { $0.id == selection } ?? panes.first
        return pane?.makeView(session) ?? AnyView(EmptyView())
    }
}

/// General preferences: whether Foreman launches at login.
private struct GeneralSettingsPane: SettingsPane {
    static let title = String(localized: .settingsGeneralTitle)
    static let icon = "gearshape"

    @Bindable var session: ForemanSession

    @State private var isWindowVisible = true

    init(session: ForemanSession) {
        _session = Bindable(session)
    }

    var body: some View {
        Form {
            Toggle(.settingsGeneralLaunchToggle, isOn: $session.startsAtLogin)
            Text(.settingsGeneralLaunchFooter)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Registered but macOS is waiting for the user to approve it.
            if session.loginItemNeedsApproval {
                LabeledContent {
                    Button(.settingsGeneralOpenLoginItems) {
                        session.openSystemSettingsLoginItems()
                    }
                } label: {
                    Label(
                        .settingsGeneralApprovalNeeded,
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
        .navigationTitle(Self.title)
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
private struct RepositoriesSettingsPane: SettingsPane {
    static let title = String(localized: .settingsRepositoriesTitle)
    static let icon = "folder"

    let session: ForemanSession

    @State private var isEditing = false

    init(session: ForemanSession) {
        self.session = session
    }

    var body: some View {
        Form {
            LabeledContent(.settingsRepositoriesScanDirectory) {
                Text(session.settings.scanDirectory?
                    .path ?? String(localized: .settingsRepositoriesDefault))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button(.settingsChange) { isEditing = true }
            Text(.settingsRepositoriesFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle(Self.title)
        .sheet(isPresented: $isEditing) {
            PathEditorSheet(
                title: String(localized: .settingsRepositoriesScanDirectory),
                prompt: String(localized: .settingsRepositoriesPrompt),
                caption: String(localized: .settingsRepositoriesCaption),
                directoryPickerStart: session.settings.resolvedScanDirectory,
                initialValue: session.settings.scanDirectory?.path ?? "",
                onSave: { session.settings.scanDirectory = $0 },
            )
        }
    }
}

/// Agent settings: which `cursor-agent` executable to run. Read-only here;
/// edited via an explicit-commit sheet (see `RepositoriesSettingsPane`).
private struct AgentSettingsPane: SettingsPane {
    static let title = String(localized: .settingsAgentTitle)
    static let icon = "terminal"

    let session: ForemanSession

    @State private var isEditing = false

    init(session: ForemanSession) {
        self.session = session
    }

    var body: some View {
        Form {
            // "cursor-agent" is the CLI executable name (a proper noun), so it
            // stays a literal rather than a catalog entry.
            LabeledContent("cursor-agent") {
                Text(session.settings.agentExecutable?
                    .path ?? String(localized: .settingsAgentAutoDetect))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button(.settingsChange) { isEditing = true }
            Text(.settingsAgentSearchFooter(
                paths: CursorAgentLocator.defaultSearchPaths.joined(separator: ", "),
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .navigationTitle(Self.title)
        .sheet(isPresented: $isEditing) {
            PathEditorSheet(
                title: String(localized: .settingsAgentEditorTitle),
                prompt: String(localized: .settingsAgentAutoDetect),
                caption: String(localized: .settingsAgentCaption),
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
                    Button(.settingsChoose) { choose() }
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(.commonCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(.commonSave) { save() }
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
