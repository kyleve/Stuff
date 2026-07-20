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

    /// Whether a fetch is in flight (drives the header spinner without clearing
    /// the shown data).
    var isRefreshing: Bool {
        services.isRefreshing
    }

    /// Whether the shown data is stale — the last refresh failed but prior data
    /// is still displayed.
    var isStale: Bool {
        services.loadError != nil
    }

    /// Why the data is stale, for a tooltip on the warning.
    var staleMessage: String? {
        services.loadError?.message
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

    /// How often spend is auto-refreshed, in seconds. `SettingsView` binds this
    /// two-way; the change is persisted in Core and picked up by the refresh
    /// loop on its next cycle.
    var refreshInterval: TimeInterval {
        get { services.settings.refreshInterval }
        set { services.settings.refreshInterval = newValue }
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

    /// The status-bar title: the current-cycle dollar amount once loaded, and a
    /// `$—` placeholder until then (so the item always shows something findable
    /// in the menu bar). Observed by the app delegate.
    var statusTitle: String {
        switch services.loadState {
            case let .loaded(snapshot):
                CurrencyFormat.menuBar(snapshot.currentCycleDollars)
            case .idle, .loading, .failed:
                "$—"
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

    /// Fetches spend now (the manual Refresh button, or after a token edit).
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
