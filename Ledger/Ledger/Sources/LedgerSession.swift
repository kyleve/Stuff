import Foundation
import LedgerCore
import Observation

/// Thin app-side facade over the LedgerCore model tree. Views read the
/// observable ``LedgerServices`` state (and bind its settings) directly; this
/// class owns the root and forwards the few app-level intents (launch, refresh,
/// quit teardown, token edits).
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

    /// Whether a token was pasted (a manual override) vs. auto-detected.
    var hasManualToken: Bool {
        services.hasManualToken
    }

    /// Whether a token can be auto-detected from the local Cursor app.
    var autoTokenAvailable: Bool {
        services.autoTokenAvailable
    }

    /// Settings; `SettingsView` binds these observable properties.
    var settings: LedgerSettings {
        services.settings
    }

    /// Whether Ledger launches at login. `SettingsView` binds this two-way.
    var startsAtLogin: Bool {
        get { services.startsAtLogin }
        set { services.startsAtLogin = newValue }
    }

    var loginItemNeedsApproval: Bool {
        services.loginItemNeedsApproval
    }

    var loginItemError: String? {
        services.loginItemError
    }

    /// The status-bar title: the current-cycle dollar amount when loaded, a
    /// placeholder otherwise. Observed by the app delegate.
    var statusTitle: String {
        switch services.loadState {
            case let .loaded(snapshot):
                CurrencyFormat.dollars(snapshot.currentCycleDollars)
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

    func start() {
        services.start()
    }

    func stop() {
        services.stop()
    }

    /// Fetches spend now (popover open, manual Refresh, after a token edit).
    func refresh() {
        Task { await services.refresh() }
    }

    /// Stores (or clears, for an empty string) a pasted session token, then refreshes.
    func setManualToken(_ token: String) throws {
        try services.setManualToken(token)
        refresh()
    }

    /// Removes any pasted token (falls back to auto-detection), then refreshes.
    func clearManualToken() throws {
        try services.clearManualToken()
        refresh()
    }

    func refreshLoginItemStatus() {
        services.refreshLoginItemStatus()
    }

    func openSystemSettingsLoginItems() {
        services.openSystemSettingsLoginItems()
    }
}
