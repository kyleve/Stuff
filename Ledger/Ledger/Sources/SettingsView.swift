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

    /// Auto-refresh cadence options, in seconds.
    private let refreshOptions: [(label: String, seconds: TimeInterval)] = [
        ("Every minute", 60),
        ("Every 5 minutes", 5 * 60),
        ("Every 15 minutes", 15 * 60),
        ("Every 30 minutes", 30 * 60),
        ("Every hour", 60 * 60),
    ]

    var body: some View {
        Form {
            Toggle("Launch Ledger at login", isOn: $session.startsAtLogin)
            Text(
                "Ledger starts automatically when you log in and keeps your Cursor spend in the menu bar.",
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("Refresh", selection: $session.refreshInterval) {
                ForEach(refreshOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            Text(
                "How often Ledger fetches your latest spend. The Refresh button in the popover updates it immediately.",
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

/// Account settings: how Ledger authenticates to the Cursor dashboard. It
/// auto-detects the session from your local Cursor app; a pasted token is an
/// optional override for when that isn't available (or has expired).
private struct AccountSettingsPane: SettingsPane {
    static let title = "Account"
    static let icon = "person.crop.circle"

    let session: LedgerSession

    @State private var tokenDraft: String = ""
    @State private var tokenError: String?

    init(session: LedgerSession) {
        self.session = session
    }

    var body: some View {
        Form {
            Section("Cursor session") {
                if session.hasManualToken {
                    Label("Using a pasted session token", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                } else if session.autoTokenAvailable {
                    Label("Using your signed-in Cursor session", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        "No Cursor session found — sign in to Cursor, or paste a token below",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Session token (optional)") {
                SecureField("Session token", text: $tokenDraft, prompt: Text(
                    session.hasManualToken ? "•••••••• (stored)" : "Paste WorkosCursorSessionToken",
                ))
                HStack {
                    Button(session.hasManualToken ? "Update Token" : "Save Token") { saveToken() }
                        .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if session.hasManualToken {
                        Button("Clear Token", role: .destructive) { clearToken() }
                    }
                }
                if let tokenError {
                    Label(tokenError, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Text(
                    "Only needed if auto-detect fails. Stored securely in your Keychain. Copy the "
                        +
                        "WorkosCursorSessionToken cookie from cursor.com (DevTools › Application › Cookies).",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Self.title)
    }

    private func saveToken() {
        do {
            try session.setManualToken(tokenDraft)
            tokenDraft = ""
            tokenError = nil
        } catch {
            tokenError = "Couldn't save the token: \(error.localizedDescription)"
        }
    }

    private func clearToken() {
        do {
            try session.clearManualToken()
            tokenDraft = ""
            tokenError = nil
        } catch {
            tokenError = "Couldn't clear the token: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(session: PreviewSupport.loadedSession())
    }
#endif
