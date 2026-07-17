import Foundation
import LedgerCore
import Observation

/// Thin app-side facade over the LedgerCore model tree. Views read the
/// observable ``LedgerServices`` state (and bind its settings) directly; this
/// class owns the root and forwards the few app-level intents (launch, refresh,
/// quit teardown, credential edits).
@MainActor
@Observable
final class LedgerSession {
    let services: LedgerServices

    /// The spend-load state the popover renders.
    var loadState: LedgerServices.LoadState {
        services.loadState
    }

    /// When the last successful fetch completed (for the "updated …" caption).
    var lastUpdated: Date? {
        services.lastUpdated
    }

    /// Whether an Admin API key is stored (drives the Settings key field).
    var hasAPIKey: Bool {
        services.hasAPIKey
    }

    /// Settings; `SettingsView` binds these observable properties (persistence
    /// happens in Core).
    var settings: LedgerSettings {
        services.settings
    }

    /// Whether Ledger launches at login. `SettingsView` binds this two-way.
    var startsAtLogin: Bool {
        get { services.startsAtLogin }
        set { services.startsAtLogin = newValue }
    }

    /// The login item is registered but awaiting approval in System Settings.
    var loginItemNeedsApproval: Bool {
        services.loginItemNeedsApproval
    }

    /// The most recent login-item failure (shown in the General settings pane).
    var loginItemError: String? {
        services.loginItemError
    }

    /// The status-bar title: the current-cycle dollar amount when loaded, a
    /// placeholder otherwise. Observed by the app delegate to keep the menu bar
    /// current.
    var statusTitle: String {
        switch services.loadState {
            case let .loaded(member):
                CurrencyFormat.compact(member.totalDollars)
            case .idle, .loading, .failed:
                "—"
        }
    }

    init(services: LedgerServices) {
        self.services = services
    }

    convenience init() {
        self.init(services: LedgerServices())
    }

    /// First fetch and periodic refresh. Called once at app launch.
    func start() {
        services.start()
    }

    /// Stops the periodic refresh; the app's quit path.
    func stop() {
        services.stop()
    }

    /// Fetches spend now (popover open, manual Refresh, after a credential edit).
    func refresh() {
        Task { await services.refresh() }
    }

    /// Stores (or clears, for an empty string) the Admin API key, then refreshes.
    func setAPIKey(_ key: String) throws {
        try services.setAPIKey(key)
        refresh()
    }

    /// Removes the stored Admin API key.
    func clearAPIKey() throws {
        try services.clearAPIKey()
    }

    /// Re-reads the login-item status from the OS.
    func refreshLoginItemStatus() {
        services.refreshLoginItemStatus()
    }

    /// Opens System Settings › General › Login Items (to approve a pending item).
    func openSystemSettingsLoginItems() {
        services.openSystemSettingsLoginItems()
    }
}
