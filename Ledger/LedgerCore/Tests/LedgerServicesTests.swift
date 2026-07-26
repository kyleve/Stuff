import Foundation
@_spi(Testing) import LedgerCore
import Testing

@MainActor
struct LedgerServicesTests {
    private func makeServices(
        provider: any DashboardProvider = ScriptedDashboardProvider(.failure(.network("unused"))),
        manualToken: String? = nil,
        autoToken: SessionToken? = nil,
        historyStore: SpendHistoryStore? = nil,
    ) -> LedgerServices {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerServicesTests-\(UUID().uuidString)")
        let store = LedgerConfigStore(directory: directory)
        return LedgerServices(
            configStore: store,
            keychain: InMemoryKeychainStore(secret: manualToken),
            tokenSource: StubTokenSource(token: autoToken),
            provider: provider,
            loginItem: LoginItemController(backend: LoginItemRecorder()),
            historyStore: historyStore ?? SpendHistoryStore(directory: directory),
        )
    }

    /// A history store in its own temp directory, so a test can read back what
    /// the services persisted.
    private func makeHistoryStore() -> SpendHistoryStore {
        SpendHistoryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerHistoryTests-\(UUID().uuidString)"))
    }

    @Test func startsIdle() {
        #expect(makeServices().loadState == .idle)
    }

    @Test func failsWithMissingCredentialsWhenNoTokenAnywhere() async {
        let services = makeServices(autoToken: nil)
        await services.refresh(force: false)
        #expect(services.loadState == .failed(.missingCredentials))
    }

    @Test func loadsUsingTheAutoDetectedToken() async {
        let provider = ScriptedDashboardProvider(.success(
            summary: .fixture(
                onDemandCents: 5000,
                membershipType: "ultra",
                includedUsed: 40000,
                includedLimit: 40000,
            ),
        ))
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)

        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.currentCycleCents == 5000)
        #expect(snapshot.membershipType == "ultra")
        #expect(services.lastUpdated != nil)
    }

    @Test func loadsUsingAPastedTokenWhenNoAutoToken() async {
        let jwt = DashboardFixture.jwt(sub: "auth0|user_PASTE")
        let provider = ScriptedDashboardProvider(summary: .fixture(onDemandCents: 999))
        let services = makeServices(provider: provider, manualToken: jwt, autoToken: nil)
        #expect(services.hasManualToken)

        await services.refresh(force: false)
        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.currentCycleCents == 999)
    }

    @Test func loadsModelSharesSortedByShare() async {
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 5000)),
            events: UsageEventFixture.events(["a": 75, "b": 25]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)

        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.modelShares.map(\.name) == ["a", "b"])
        #expect(snapshot.modelShares.first?.fraction == 0.75)
    }

    @Test func stillLoadsWhenPerModelFetchFails() async {
        // The per-model breakdown is best-effort: its failure must not blank
        // the headline.
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 5000)),
            eventsFailure: .http(500),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)

        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.currentCycleCents == 5000)
        #expect(snapshot.modelShares.isEmpty)
    }

    @Test func keepsLoadedDataAndFlagsStaleWhenARefreshFails() async {
        let provider = MutableDashboardProvider(.success(.fixture(onDemandCents: 5000)))
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        await services.refresh(force: false)
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == nil)

        // A later refresh fails (e.g. offline): keep the data, mark it stale.
        provider.result = .failure(.network("offline"))
        await services.refresh(force: false)
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == .network("offline"))

        // Recovering clears the stale flag.
        provider.result = .success(.fixture(onDemandCents: 5100))
        await services.refresh(force: false)
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == nil)
    }

    @Test func firstLoadFailureShowsTheErrorState() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.network("offline"))),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)
        #expect(services.loadState == .failed(.network("offline")))
        #expect(services.loadError == nil)
    }

    @Test func mapsNotAuthenticated() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.notAuthenticated)),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)
        #expect(services.loadState == .failed(.notAuthenticated))
    }

    @Test func mapsNetworkErrors() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.network("offline"))),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)
        #expect(services.loadState == .failed(.network("offline")))
    }

    @Test func tracksManualTokenPresence() throws {
        let services = makeServices()
        #expect(!services.hasManualToken)

        try services.setManualToken(DashboardFixture.jwt(sub: "auth0|user_X"))
        #expect(services.hasManualToken)

        try services.clearManualToken()
        #expect(!services.hasManualToken)
    }

    @Test func reportsAutoTokenAvailability() {
        #expect(makeServices(autoToken: nil).autoTokenAvailable == false)
        #expect(makeServices(autoToken: SessionToken(cookieValue: "a::b"))
            .autoTokenAvailable == true)
    }

    @Test func errorMessagesAreActionable() {
        #expect(LedgerServices.LoadError.missingCredentials.message.contains("Cursor"))
        #expect(LedgerServices.LoadError.notAuthenticated.message.contains("expired"))
    }

    @Test func keepsLoadedDataVisibleDuringARefresh() async {
        let provider = GatedDashboardProvider(summary: .fixture(onDemandCents: 5000))
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        // First load completes (the first usage-summary call isn't gated).
        await services.refresh(force: false)
        #expect(isLoaded(services.loadState))
        #expect(!services.isRefreshing)

        // A second refresh suspends inside usage-summary.
        let task = Task { await services.refresh(force: false) }
        await waitUntil { services.isRefreshing }

        // The already-loaded data stays on screen — not cleared to `.loading`.
        #expect(isLoaded(services.loadState))

        provider.release()
        await task.value
        #expect(!services.isRefreshing)
        #expect(isLoaded(services.loadState))
    }

    // MARK: - Per-model throttle & pagination

    @Test func throttlesThePerModelFetchAcrossPeriodicRefreshes() async {
        let provider = CountingDashboardProvider(
            summary: .fixture(onDemandCents: 5000),
            events: UsageEventFixture.events(["a": 75, "b": 25]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        await services.refresh(force: false)
        #expect(provider.eventFetches == 1)

        // A second periodic refresh reuses the cached breakdown — walking every
        // event again on each headline refresh is far too expensive.
        await services.refresh(force: false)
        #expect(provider.eventFetches == 1)
        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.modelShares.map(\.name) == ["a", "b"])
    }

    @Test func anExplicitRefreshForcesThePerModelFetch() async {
        let provider = CountingDashboardProvider(
            summary: .fixture(onDemandCents: 5000),
            events: UsageEventFixture.events(["a": 100]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        await services.refresh(force: false)
        await services.refresh(force: true)
        #expect(provider.eventFetches == 2)
    }

    @Test func aNewBillingCycleInvalidatesTheCachedBreakdown() async {
        let provider = CountingDashboardProvider(
            summary: .fixture(onDemandCents: 5000),
            events: UsageEventFixture.events(["a": 100]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        await services.refresh(force: false)
        // The cycle rolls over: the cached breakdown belongs to the old cycle.
        provider.summary = .fixture(
            onDemandCents: 10,
            cycleStart: "2026-08-04T18:16:08.000Z",
            cycleEnd: "2026-09-04T18:16:08.000Z",
        )
        await services.refresh(force: false)
        #expect(provider.eventFetches == 2)
    }

    @Test func keepsTheLastBreakdownWhenAPerModelFetchFails() async {
        let provider = CountingDashboardProvider(
            summary: .fixture(onDemandCents: 5000),
            events: UsageEventFixture.events(["a": 100]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh(force: false)

        provider.eventsFailure = .http(500)
        await services.refresh(force: true)

        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        // A transient per-model failure must not blank a good breakdown.
        #expect(snapshot.modelShares.map(\.name) == ["a"])
    }

    @Test func paginatesEveryEventInTheCycle() async {
        // 600 events over a 250-event page size → three pages.
        let events = Array(repeating: UsageEvent(model: "a", chargedCents: 1), count: 400)
            + Array(repeating: UsageEvent(model: "b", chargedCents: 1), count: 200)
        let provider = CountingDashboardProvider(
            summary: .fixture(onDemandCents: 5000),
            events: events,
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )

        await services.refresh(force: false)

        #expect(provider.eventPageRequests == 3)
        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        // All 600 events counted: a = 400/600, b = 200/600.
        #expect(snapshot.modelShares.map(\.name) == ["a", "b"])
        #expect(abs((snapshot.modelShares.first?.fraction ?? 0) - 2.0 / 3.0) < 0.0001)
    }

    // MARK: - Superseded refreshes

    @Test func aSupersededRefreshDoesNotRecordHistory() async {
        let historyStore = makeHistoryStore()
        let provider = FirstCallGatedProvider(
            gated: .fixture(onDemandCents: 5000),
            later: .fixture(onDemandCents: 5100),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
            historyStore: historyStore,
        )

        // A slow refresh (reading the older total) suspends mid-flight…
        let stale = Task { await services.refresh(force: false) }
        await waitUntil { provider.gatedCallStarted }
        // …a newer one overtakes and completes…
        await services.refresh(force: false)
        // …then the stale one lands.
        provider.release()
        await stale.value

        // Only the winning refresh recorded a sample: appending the older
        // reading at a later timestamp would skew future day/week baselines.
        let samples = (try? historyStore.load()) ?? []
        #expect(samples.count == 1)
        #expect(samples.first?.onDemandCents == 5100)
    }

    private func isLoaded(_ state: LedgerServices.LoadState) -> Bool {
        if case .loaded = state { true } else { false }
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if predicate() { return }
            await Task.yield()
        }
    }
}

/// A `DashboardProvider` that serves a (swappable) summary and a fixed event
/// list sliced into pages, counting how many event pages — and how many
/// distinct fetches — were requested.
private final class CountingDashboardProvider: DashboardProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _summary: UsageSummary
    private let events: [UsageEvent]
    private var _eventPageRequests = 0
    private var _eventFetches = 0
    private var _eventsFailure: DashboardError?

    init(summary: UsageSummary, events: [UsageEvent]) {
        _summary = summary
        self.events = events
    }

    var summary: UsageSummary {
        get { lock.withLock { _summary } }
        set { lock.withLock { _summary = newValue } }
    }

    /// When set, every `usageEvents` call throws it.
    var eventsFailure: DashboardError? {
        get { lock.withLock { _eventsFailure } }
        set { lock.withLock { _eventsFailure = newValue } }
    }

    /// Total pages requested (pagination depth across all fetches).
    var eventPageRequests: Int {
        lock.withLock { _eventPageRequests }
    }

    /// Distinct per-model fetches (counted by first-page requests).
    var eventFetches: Int {
        lock.withLock { _eventFetches }
    }

    func usageSummary(token _: SessionToken) async throws -> UsageSummary {
        summary
    }

    func usageEvents(
        startDate _: Date,
        endDate _: Date,
        page: Int,
        pageSize: Int,
        token _: SessionToken,
    ) async throws -> UsageEventsPage {
        let failure: DashboardError? = lock.withLock {
            _eventPageRequests += 1
            if page == 1 { _eventFetches += 1 }
            return _eventsFailure
        }
        if let failure { throw failure }

        let start = (page - 1) * pageSize
        guard start < events.count else {
            return UsageEventsPage(usageEventsDisplay: [], totalUsageEventsCount: events.count)
        }
        let slice = Array(events[start ..< min(start + pageSize, events.count)])
        return UsageEventsPage(usageEventsDisplay: slice, totalUsageEventsCount: events.count)
    }
}

/// A `DashboardProvider` whose *first* `usageSummary` call blocks until
/// `release()` (later calls return immediately), so a test can start a slow
/// refresh, let a newer one overtake it, and then land the stale response.
private final class FirstCallGatedProvider: DashboardProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let gatedSummary: UsageSummary
    private let laterSummary: UsageSummary
    private var callCount = 0
    private var stored: CheckedContinuation<Void, Never>?
    private var released = false
    private var started = false

    init(gated: UsageSummary, later: UsageSummary) {
        gatedSummary = gated
        laterSummary = later
    }

    /// Whether the gated (first) call has been entered.
    var gatedCallStarted: Bool {
        lock.withLock { started }
    }

    func usageSummary(token _: SessionToken) async throws -> UsageSummary {
        let isGated = lock.withLock { () -> Bool in
            callCount += 1
            if callCount == 1 {
                started = true
                return true
            }
            return false
        }
        guard isGated else { return laterSummary }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let releaseNow = lock.withLock { () -> Bool in
                if released { return true }
                stored = continuation
                return false
            }
            if releaseNow { continuation.resume() }
        }
        return gatedSummary
    }

    func usageEvents(
        startDate _: Date,
        endDate _: Date,
        page _: Int,
        pageSize _: Int,
        token _: SessionToken,
    ) async throws -> UsageEventsPage {
        UsageEventsPage(usageEventsDisplay: [], totalUsageEventsCount: 0)
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            let stored = stored
            self.stored = nil
            return stored
        }
        continuation?.resume()
    }
}

/// A `DashboardProvider` whose usage-summary result can be swapped between
/// calls, so a test can simulate a success followed by a failure.
private final class MutableDashboardProvider: DashboardProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<UsageSummary, DashboardError>

    init(_ result: Result<UsageSummary, DashboardError>) {
        _result = result
    }

    var result: Result<UsageSummary, DashboardError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    func usageSummary(token _: SessionToken) async throws -> UsageSummary {
        try result.get()
    }

    func usageEvents(
        startDate _: Date,
        endDate _: Date,
        page _: Int,
        pageSize _: Int,
        token _: SessionToken,
    ) async throws -> UsageEventsPage {
        UsageEventsPage(usageEventsDisplay: [], totalUsageEventsCount: 0)
    }
}

/// A `DashboardProvider` whose *second* `usageSummary` call blocks until
/// `release()`, so a test can observe the in-flight-refresh state.
private final class GatedDashboardProvider: DashboardProvider, @unchecked Sendable {
    private let summary: UsageSummary
    private let lock = NSLock()
    private var callCount = 0
    private var stored: CheckedContinuation<Void, Never>?
    private var released = false

    init(summary: UsageSummary) {
        self.summary = summary
    }

    func usageSummary(token _: SessionToken) async throws -> UsageSummary {
        let shouldGate = lock.withLock {
            callCount += 1
            return callCount >= 2
        }
        if shouldGate {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let releaseNow = lock.withLock { () -> Bool in
                    if released { return true }
                    stored = continuation
                    return false
                }
                if releaseNow { continuation.resume() }
            }
        }
        return summary
    }

    func usageEvents(
        startDate _: Date,
        endDate _: Date,
        page _: Int,
        pageSize _: Int,
        token _: SessionToken,
    ) async throws -> UsageEventsPage {
        UsageEventsPage(usageEventsDisplay: [], totalUsageEventsCount: 0)
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            let stored = stored
            self.stored = nil
            return stored
        }
        continuation?.resume()
    }
}
