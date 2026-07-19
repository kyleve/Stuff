import Foundation
import Observation

/// The root of the Ledger model tree. Resolves a Cursor session token
/// (auto-detected from the local Cursor app, or pasted and kept in the
/// Keychain), fetches the current cycle's usage summary and the year's monthly
/// invoices from the dashboard API, and exposes a single observable
/// ``LoadState`` the UI renders.
@MainActor
@Observable
public final class LedgerServices {
    /// The spend-load state machine: exactly one of these holds at a time, so
    /// the UI can't see a half-loaded mix of value + error + spinner.
    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded(SpendSnapshot)
        case failed(LoadError)
    }

    /// Why a spend fetch couldn't produce a value.
    public enum LoadError: Sendable, Equatable {
        /// No session token could be found (Cursor signed out / not installed,
        /// and nothing pasted).
        case missingCredentials
        /// HTTP 401 — the token is expired or malformed.
        case notAuthenticated
        /// Another non-2xx HTTP response.
        case http(Int)
        /// The transport failed (offline, DNS, TLS, timeout).
        case network(String)
        /// A 2xx response that didn't decode.
        case decode(String)

        /// A short, user-facing explanation for the popover.
        public var message: String {
            switch self {
                case .missingCredentials:
                    "Sign in to the Cursor app, or paste a session token in Settings."
                case .notAuthenticated:
                    "Your Cursor session expired. Reopen Cursor (or paste a fresh token in Settings)."
                case let .http(status):
                    "The dashboard request failed (HTTP \(status))."
                case let .network(reason):
                    "Couldn't reach Cursor: \(reason)"
                case let .decode(reason):
                    "Couldn't read the dashboard response: \(reason)"
            }
        }
    }

    /// The current spend-load state. Observable so the UI reflects it.
    public private(set) var loadState: LoadState = .idle

    /// When the last successful fetch completed, for the "updated …" caption.
    public private(set) var lastUpdated: Date?

    /// Whether a fetch is currently in flight. Distinct from `loadState`:
    /// during a refresh the last loaded data stays visible (so the UI doesn't
    /// clear), and this drives only a subtle in-progress indicator.
    public private(set) var isRefreshing: Bool = false

    /// Whether a token was pasted into the Keychain (a manual override).
    public private(set) var hasManualToken: Bool = false

    /// Whether a token can be auto-detected from the local Cursor app.
    public private(set) var autoTokenAvailable: Bool = false

    /// Settings; created from the loaded configuration.
    @ObservationIgnored
    public private(set) lazy var settings: LedgerSettings = .init(
        refreshInterval: configuration.refreshInterval,
        onPersistentChange: { [unowned self] in settingsDidChange() },
    )

    /// Whether Ledger is registered to launch at login. Backed by
    /// `SMAppService` (the OS owns the real state).
    public var startsAtLogin: Bool {
        get { loginItem.isEnabled }
        set {
            do {
                try loginItem.setEnabled(newValue)
                loginItemError = nil
            } catch {
                Self.logger.error("Couldn't update the login item: \(error)")
                loginItemError = newValue
                    ? "Couldn't turn on Launch at login: \(error.localizedDescription)"
                    : "Couldn't turn off Launch at login: \(error.localizedDescription)"
            }
        }
    }

    /// The login item is registered but macOS needs the user to approve it.
    public var loginItemNeedsApproval: Bool {
        loginItem.needsApproval
    }

    /// The most recent login-item failure, surfaced in Settings.
    public private(set) var loginItemError: String?

    private static let logger = LedgerLog.channel(.services)

    @ObservationIgnored private var configuration: LedgerConfiguration
    @ObservationIgnored private let configStore: LedgerConfigStore
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private let tokenSource: any SessionTokenSource
    @ObservationIgnored private let provider: any DashboardProvider
    @ObservationIgnored private let loginItem: LoginItemController
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    /// Increments per fetch so a slow earlier response can't clobber a newer one.
    @ObservationIgnored private var requestGeneration = 0

    public convenience init() {
        self.init(
            configStore: .applicationSupport(),
            keychain: SystemKeychainStore(),
            tokenSource: CursorLocalTokenSource(),
            provider: CursorDashboardAPI(),
            loginItem: LoginItemController(),
        )
    }

    @_spi(Testing)
    public init(
        configStore: LedgerConfigStore,
        keychain: any KeychainStore,
        tokenSource: any SessionTokenSource,
        provider: any DashboardProvider,
        loginItem: LoginItemController,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.configStore = configStore
        self.keychain = keychain
        self.tokenSource = tokenSource
        self.provider = provider
        self.loginItem = loginItem
        self.now = now
        do {
            configuration = try configStore.load()
        } catch {
            Self.logger.error("Couldn't load configuration: \(error)")
            configuration = .initial
        }
        refreshTokenAvailability()
    }

    // MARK: - Lifecycle

    /// Kicks off the first fetch and the periodic refresh loop.
    public func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.settings.refreshInterval, interval > 0 else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Cancels the periodic refresh loop (the app's quit path).
    public func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    // MARK: - Spend

    /// Fetches the current cycle's usage summary and the year's invoices, then
    /// builds a ``SpendSnapshot``. Safe to call concurrently: a stale response
    /// is dropped.
    public func refresh() async {
        refreshTokenAvailability()
        guard let token = resolveToken() else {
            loadState = .failed(.missingCredentials)
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        // Keep any already-loaded data on screen during a refresh — only show
        // the full-screen loading state for the very first load. The header
        // spinner (driven by `isRefreshing`) signals the in-flight fetch.
        if case .loaded = loadState {} else {
            loadState = .loading
        }
        isRefreshing = true
        defer {
            // Don't clear the flag for a newer refresh that superseded this one.
            if generation == requestGeneration { isRefreshing = false }
        }

        do {
            let summary = try await provider.usageSummary(token: token)
            let models = await topModels(cycleStart: summary.cycleStart, token: token)

            guard generation == requestGeneration else { return }
            let snapshot = SpendSnapshot(
                currentCycleCents: summary.onDemandCents,
                cycleStart: summary.cycleStart,
                cycleEnd: summary.cycleEnd,
                membershipType: summary.membershipType,
                includedFractionUsed: summary.includedFractionUsed,
                usageMessages: summary.usageMessages,
                topModels: models,
            )
            loadState = .loaded(snapshot)
            lastUpdated = now()
        } catch let error as DashboardError {
            guard generation == requestGeneration else { return }
            loadState = .failed(error.asLoadError)
        } catch {
            guard generation == requestGeneration else { return }
            Self.logger.error("Unexpected dashboard error: \(error.localizedDescription)")
            loadState = .failed(.network(error.localizedDescription))
        }
    }

    /// The top models by usage for the current cycle, as relative shares.
    /// Best-effort: the per-model breakdown is supplementary, so a failure (or
    /// an unknown cycle start) logs and yields an empty list rather than
    /// failing the whole load.
    private func topModels(cycleStart: Date?, token: SessionToken) async -> [ModelShare] {
        guard let cycleStart else { return [] }
        do {
            let usage = try await provider.aggregatedUsage(
                startDate: cycleStart,
                endDate: now(),
                token: token,
            )
            return usage.topModels(limit: 5)
        } catch {
            Self.logger.warning("Couldn't load per-model usage: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Token

    /// A pasted token (Keychain) wins as an explicit override; otherwise the
    /// auto-detected local Cursor session is used.
    private func resolveToken() -> SessionToken? {
        if let manual = manualToken(), let token = SessionToken(rawToken: manual) {
            return token
        }
        return tokenSource.currentToken()
    }

    private func manualToken() -> String? {
        do {
            let value = try keychain.read()
            return (value?.isEmpty ?? true) ? nil : value
        } catch {
            Self.logger.error("Couldn't read the pasted token: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stores (or clears, for an empty string) a pasted session token.
    public func setManualToken(_ token: String) throws {
        try keychain.write(token)
        refreshTokenAvailability()
    }

    /// Removes any pasted token (falling back to auto-detection).
    public func clearManualToken() throws {
        try keychain.remove()
        refreshTokenAvailability()
    }

    private func refreshTokenAvailability() {
        hasManualToken = manualToken() != nil
        autoTokenAvailable = tokenSource.currentToken() != nil
    }

    // MARK: - Login item

    public func refreshLoginItemStatus() {
        loginItem.refresh()
    }

    public func openSystemSettingsLoginItems() {
        loginItem.openSystemSettingsLoginItems()
    }

    // MARK: - Persistence

    private func settingsDidChange() {
        configuration.refreshInterval = settings.refreshInterval
        persist()
        // Apply a new cadence now rather than after the current sleep: restart
        // the loop (which refreshes immediately) if it's running.
        if refreshLoop != nil {
            stop()
            start()
        }
    }

    private func persist() {
        do {
            try configStore.save(configuration)
        } catch {
            Self.logger.error("Couldn't save configuration: \(error)")
        }
    }
}

extension DashboardError {
    fileprivate var asLoadError: LedgerServices.LoadError {
        switch self {
            case .notAuthenticated: .notAuthenticated
            case let .http(status): .http(status)
            case let .network(reason): .network(reason)
            case let .decode(reason): .decode(reason)
        }
    }
}
