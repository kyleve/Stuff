import Foundation
import Observation

/// The root of the Ledger model tree. Resolves a Cursor session token
/// (auto-detected from the local Cursor app, or pasted and kept in the
/// Keychain), fetches the current cycle's usage summary and per-model usage
/// from the dashboard API, and exposes a single observable ``LoadState`` the
/// UI renders.
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

    /// The most recent refresh failure *while spend is still shown* — i.e. the
    /// data is stale. `nil` when the last refresh succeeded. (A failure with no
    /// prior data goes to `loadState = .failed` instead.)
    public private(set) var loadError: LoadError?

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

    private static let logger = LedgerLog.services

    /// Minimum time between per-model fetches. That breakdown costs several
    /// paginated requests (it walks every usage event in the cycle), while the
    /// headline refreshes as often as once a minute — so it is deliberately
    /// *not* refetched at the headline cadence. The mix changes slowly; the
    /// manual Refresh button bypasses this, as does a new billing cycle.
    private static let modelRefreshInterval: TimeInterval = 15 * 60

    @ObservationIgnored private var configuration: LedgerConfiguration
    @ObservationIgnored private let configStore: LedgerConfigStore
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private let tokenSource: any SessionTokenSource
    @ObservationIgnored private let provider: any DashboardProvider
    @ObservationIgnored private let loginItem: LoginItemController
    @ObservationIgnored private let historyStore: SpendHistoryStore
    @ObservationIgnored private var history: [SpendSample] = []
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    /// Increments per fetch so a slow earlier response can't clobber a newer one.
    @ObservationIgnored private var requestGeneration = 0
    /// The resolved credential, cached so refreshes don't re-read the Keychain
    /// and Cursor's SQLite store every time (see ``resolveToken()``).
    @ObservationIgnored private var cachedToken: SessionToken?
    /// The last per-model breakdown, reused between throttled fetches (see
    /// ``modelRefreshInterval``) and kept when a per-model fetch fails.
    @ObservationIgnored private var cachedModelShares: [ModelShare] = []
    /// When ``cachedModelShares`` was last fetched, and for which cycle.
    @ObservationIgnored private var lastModelFetch: Date?
    @ObservationIgnored private var cachedModelCycle: Date?

    public convenience init() {
        self.init(
            configStore: .applicationSupport(),
            keychain: SystemKeychainStore(),
            tokenSource: CursorLocalTokenSource(),
            provider: CursorDashboardAPI(),
            loginItem: LoginItemController(),
            historyStore: .applicationSupport(),
        )
    }

    @_spi(Testing)
    public init(
        configStore: LedgerConfigStore,
        keychain: any KeychainStore,
        tokenSource: any SessionTokenSource,
        provider: any DashboardProvider,
        loginItem: LoginItemController,
        historyStore: SpendHistoryStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.configStore = configStore
        self.keychain = keychain
        self.tokenSource = tokenSource
        self.provider = provider
        self.loginItem = loginItem
        self.historyStore = historyStore
        self.calendar = calendar
        self.now = now
        do {
            configuration = try configStore.load()
        } catch {
            Self.logger.error("Couldn't load configuration: \(error)")
            configuration = .initial
        }
        do {
            history = try historyStore.load()
        } catch {
            Self.logger.error("Couldn't load spend history: \(error)")
            history = []
        }
        refreshTokenStatus()
    }

    // MARK: - Lifecycle

    /// Kicks off the first fetch and the periodic refresh loop.
    public func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                // Periodic refreshes respect the per-model throttle; only an
                // explicit user refresh forces that (expensive) fetch.
                await self?.refresh(force: false)
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

    /// Fetches the current cycle's usage summary (and, subject to the
    /// ``modelRefreshInterval`` throttle, the per-model breakdown), then builds
    /// a ``SpendSnapshot``. Pass `force` for an explicit user refresh, which
    /// bypasses that throttle. Safe to call concurrently: a stale response is
    /// dropped without touching state or recorded history.
    public func refresh(force: Bool) async {
        guard let token = resolveToken() else {
            applyFailure(.missingCredentials)
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
            let models = await modelShares(
                cycleStart: summary.cycleStart,
                token: token,
                force: force,
            )

            // Everything below mutates state, so it must run only for the
            // newest request: recording history from a superseded (older)
            // response would append a lower reading at a later timestamp and
            // skew future day/week baselines.
            guard generation == requestGeneration else { return }
            let deltas = recordHistory(summary: summary)
            let snapshot = SpendSnapshot(
                currentCycleCents: summary.onDemandCents,
                deltas: deltas,
                cycleStart: summary.cycleStart,
                cycleEnd: summary.cycleEnd,
                membershipType: summary.membershipType,
                autoFractionUsed: summary.autoFractionUsed,
                apiFractionUsed: summary.apiFractionUsed,
                modelShares: models,
            )
            loadState = .loaded(snapshot)
            lastUpdated = now()
            loadError = nil
        } catch let error as DashboardError {
            guard generation == requestGeneration else { return }
            if error == .notAuthenticated {
                // The credential we cached was rejected — drop it so the next
                // refresh re-reads (the user may have signed back in to Cursor,
                // rotating the stored token).
                cachedToken = nil
            }
            applyFailure(error.asLoadError)
        } catch {
            guard generation == requestGeneration else { return }
            Self.logger.error("Unexpected dashboard error: \(error.localizedDescription)")
            applyFailure(.network(error.localizedDescription))
        }
    }

    /// Records a refresh failure. If spend is already loaded, the last good data
    /// stays on screen and the failure surfaces as ``loadError`` (a stale
    /// warning); otherwise — nothing loaded yet — it becomes the full error
    /// state.
    private func applyFailure(_ error: LoadError) {
        if case .loaded = loadState {
            loadError = error
        } else {
            loadState = .failed(error)
            loadError = nil
        }
    }

    /// Appends a sample of the cumulative on-demand spend, prunes and persists
    /// the history (best-effort), and returns today's / this-week's deltas.
    private func recordHistory(summary: UsageSummary) -> SpendDeltas {
        let timestamp = now()
        let sample = SpendSample(
            timestamp: timestamp,
            cycleStart: summary.cycleStart,
            onDemandCents: summary.onDemandCents,
        )
        history = historyStore.pruned(history + [sample], now: timestamp)
        do {
            try historyStore.save(history)
        } catch {
            Self.logger.warning("Couldn't save spend history: \(error.localizedDescription)")
        }
        return SpendHistory.deltas(
            current: sample,
            samples: history,
            calendar: calendar,
            now: timestamp,
        )
    }

    /// The models by usage for the current cycle, as relative shares, derived
    /// from the per-event endpoint — throttled by ``modelRefreshInterval``, so
    /// most refreshes reuse the cached breakdown instead of re-walking every
    /// event. Best-effort: a failure (or an unknown cycle start) logs and keeps
    /// the last good breakdown rather than failing the whole load.
    private func modelShares(
        cycleStart: Date?,
        token: SessionToken,
        force: Bool,
    ) async -> [ModelShare] {
        guard let cycleStart else { return [] }
        guard shouldFetchModels(cycleStart: cycleStart, force: force) else {
            return cachedModelShares
        }
        do {
            let events = try await cycleEvents(since: cycleStart, token: token)
            cachedModelShares = ModelShare.shares(from: events)
            cachedModelCycle = cycleStart
            lastModelFetch = now()
            return cachedModelShares
        } catch {
            Self.logger.warning("Couldn't load per-model usage: \(error.localizedDescription)")
            return cachedModelShares
        }
    }

    /// Whether the per-model breakdown is due for a refetch: on an explicit
    /// user refresh, when the billing cycle rolled over (the cached breakdown
    /// belongs to the previous cycle), or once the throttle window has elapsed.
    private func shouldFetchModels(cycleStart: Date, force: Bool) -> Bool {
        if force || cycleStart != cachedModelCycle { return true }
        guard let lastModelFetch else { return true }
        return now().timeIntervalSince(lastModelFetch) >= Self.modelRefreshInterval
    }

    /// Fetches all usage events from `cycleStart` to now, paginating newest-first
    /// until the reported total is covered (capped to bound request count).
    private func cycleEvents(
        since cycleStart: Date,
        token: SessionToken,
    ) async throws -> [UsageEvent] {
        let pageSize = 250
        let maxPages = 40
        let end = now()
        var events: [UsageEvent] = []
        var page = 1
        while page <= maxPages {
            let result = try await provider.usageEvents(
                startDate: cycleStart,
                endDate: end,
                page: page,
                pageSize: pageSize,
                token: token,
            )
            events.append(contentsOf: result.usageEventsDisplay)
            if result.usageEventsDisplay.isEmpty || events.count >= result.totalUsageEventsCount {
                break
            }
            page += 1
        }
        return events
    }

    // MARK: - Token

    /// The session token, read once and then cached. Reading it touches the
    /// Keychain *and* opens Cursor's SQLite store, and the value doesn't change
    /// between refreshes — so the cache is dropped only when it actually can
    /// change: the user edits the pasted token, the API rejects it (401), or
    /// Settings asks for a fresh read.
    private func resolveToken() -> SessionToken? {
        if let cachedToken { return cachedToken }
        cachedToken = readToken()
        return cachedToken
    }

    /// Reads both credential sources — a pasted token (Keychain) overrides the
    /// auto-detected local Cursor session — and mirrors what it found onto the
    /// observable availability flags.
    private func readToken() -> SessionToken? {
        let manual = manualToken()
        hasManualToken = manual != nil
        let auto = tokenSource.currentToken()
        autoTokenAvailable = auto != nil

        if let manual, let token = SessionToken(rawToken: manual) {
            return token
        }
        return auto
    }

    /// Re-reads the credential sources now, refreshing ``hasManualToken`` and
    /// ``autoTokenAvailable``. Settings calls this when it appears, since the
    /// underlying state changes outside the app (signing in/out of Cursor).
    public func refreshTokenStatus() {
        cachedToken = nil
        _ = resolveToken()
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
        refreshTokenStatus()
    }

    /// Removes any pasted token (falling back to auto-detection).
    public func clearManualToken() throws {
        try keychain.remove()
        refreshTokenStatus()
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
