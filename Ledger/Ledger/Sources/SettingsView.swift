import AppKit
import LedgerCore
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

    init(session: LedgerSession)
}

/// Type-erased sidebar entry: a pane's metadata plus a builder for its content.
/// Keyed by the pane type's `ObjectIdentifier`, so the sidebar selection stays
/// a typed token rather than a stringly value.
private struct SettingsPaneItem: Identifiable {
    let id: ObjectIdentifier
    let title: String
    let icon: String
    let makeView: (LedgerSession) -> AnyView

    init(_ pane: (some SettingsPane).Type) {
        id = ObjectIdentifier(pane)
        title = pane.title
        icon = pane.icon
        makeView = { AnyView(pane.init(session: $0)) }
    }
}

/// Global settings, laid out like a modern macOS System Settings window: a
/// `NavigationSplitView` sidebar over the registered ``SettingsPaneItem``s.
struct SettingsView: View {
    let session: LedgerSession

    private let panes: [SettingsPaneItem] = [
        SettingsPaneItem(GeneralSettingsPane.self),
        SettingsPaneItem(AccountSettingsPane.self),
    ]

    @State private var selection: ObjectIdentifier?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(panes, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(minWidth: 460, minHeight: 360)
        .onAppear {
            if selection == nil { selection = panes.first?.id }
        }
    }

    private var detail: AnyView {
        let pane = panes.first { $0.id == selection } ?? panes.first
        return pane?.makeView(session) ?? AnyView(EmptyView())
    }
}

/// General preferences: whether Ledger launches at login.
private struct GeneralSettingsPane: SettingsPane {
    static let title = "General"
    static let icon = "gearshape"

    @Bindable var session: LedgerSession

    @State private var isWindowVisible = true

    init(session: LedgerSession) {
        _session = Bindable(session)
    }

    var body: some View {
        Form {
            Toggle("Launch Ledger at login", isOn: $session.startsAtLogin)
            Text(
                "Ledger starts automatically when you log in and keeps your Cursor spend in the menu bar.",
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if session.loginItemNeedsApproval {
                LabeledContent {
                    Button("Open Login Items") {
                        session.openSystemSettingsLoginItems()
                    }
                } label: {
                    Label(
                        "Approval needed in System Settings",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
            }

            if let error = session.loginItemError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Self.title)
        .onAppear { session.refreshLoginItemStatus() }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        .onChange(of: isWindowVisible) { _, visible in
            if visible { session.refreshLoginItemStatus() }
        }
    }
}

/// Account settings: the team-member email and the Admin API key (stored in the
/// Keychain). Both commit explicitly on Save so a half-typed value can't leak
/// out by navigating away.
private struct AccountSettingsPane: SettingsPane {
    static let title = "Account"
    static let icon = "person.crop.circle"

    let session: LedgerSession

    @State private var emailDraft: String = ""
    @State private var keyDraft: String = ""
    @State private var keyError: String?

    init(session: LedgerSession) {
        self.session = session
    }

    var body: some View {
        Form {
            Section("Team member") {
                TextField("Email", text: $emailDraft, prompt: Text("you@company.com"))
                    .textContentType(.username)
                Button("Save Email") { saveEmail() }
                    .disabled(emailDraft.trimmingCharacters(in: .whitespaces)
                        == (session.settings.teamMemberEmail ?? ""))
                Text("Ledger shows the spend for this member of your Cursor team.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Admin API key") {
                SecureField("Admin API key", text: $keyDraft, prompt: Text(
                    session.hasAPIKey ? "•••••••• (stored)" : "Paste your Admin API key",
                ))
                HStack {
                    Button(session.hasAPIKey ? "Update Key" : "Save Key") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if session.hasAPIKey {
                        Button("Clear Key", role: .destructive) { clearKey() }
                    }
                }
                if let keyError {
                    Label(keyError, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Text(
                    "Stored securely in your Keychain. Create a key in the Cursor dashboard (Admin API).",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Self.title)
        .onAppear {
            emailDraft = session.settings.teamMemberEmail ?? ""
        }
    }

    private func saveEmail() {
        let trimmed = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        session.settings.teamMemberEmail = trimmed.isEmpty ? nil : trimmed
        session.refresh()
    }

    private func saveKey() {
        do {
            try session.setAPIKey(keyDraft)
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = "Couldn't save the key: \(error.localizedDescription)"
        }
    }

    private func clearKey() {
        do {
            try session.clearAPIKey()
            keyDraft = ""
            keyError = nil
        } catch {
            keyError = "Couldn't clear the key: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(session: PreviewSupport.loadedSession())
    }
#endif
