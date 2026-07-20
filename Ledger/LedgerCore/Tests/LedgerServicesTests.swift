import Foundation
@_spi(Testing) import LedgerCore
import Testing

@MainActor
struct LedgerServicesTests {
    private func makeServices(
        provider: any DashboardProvider = ScriptedDashboardProvider(.failure(.network("unused"))),
        manualToken: String? = nil,
        autoToken: SessionToken? = nil,
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
            historyStore: SpendHistoryStore(directory: directory),
        )
    }

    @Test func startsIdle() {
        #expect(makeServices().loadState == .idle)
    }

    @Test func failsWithMissingCredentialsWhenNoTokenAnywhere() async {
        let services = makeServices(autoToken: nil)
        await services.refresh()
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
        await services.refresh()

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

        await services.refresh()
        guard case let .loaded(snapshot) = services.loadState else {
            Issue.record("expected loaded, got \(services.loadState)")
            return
        }
        #expect(snapshot.currentCycleCents == 999)
    }

    @Test func loadsModelSharesSortedByShare() async {
        let provider = ScriptedDashboardProvider(
            .success(summary: .fixture(onDemandCents: 5000)),
            aggregated: .fixture(["a": 75, "b": 25]),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh()

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
            aggregatedFailure: .http(500),
        )
        let services = makeServices(
            provider: provider,
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh()

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

        await services.refresh()
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == nil)

        // A later refresh fails (e.g. offline): keep the data, mark it stale.
        provider.result = .failure(.network("offline"))
        await services.refresh()
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == .network("offline"))

        // Recovering clears the stale flag.
        provider.result = .success(.fixture(onDemandCents: 5100))
        await services.refresh()
        #expect(isLoaded(services.loadState))
        #expect(services.loadError == nil)
    }

    @Test func firstLoadFailureShowsTheErrorState() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.network("offline"))),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh()
        #expect(services.loadState == .failed(.network("offline")))
        #expect(services.loadError == nil)
    }

    @Test func mapsNotAuthenticated() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.notAuthenticated)),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh()
        #expect(services.loadState == .failed(.notAuthenticated))
    }

    @Test func mapsNetworkErrors() async {
        let services = makeServices(
            provider: ScriptedDashboardProvider(.failure(.network("offline"))),
            autoToken: SessionToken(cookieValue: "auto::jwt"),
        )
        await services.refresh()
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
        await services.refresh()
        #expect(isLoaded(services.loadState))
        #expect(!services.isRefreshing)

        // A second refresh suspends inside usage-summary.
        let task = Task { await services.refresh() }
        await waitUntil { services.isRefreshing }

        // The already-loaded data stays on screen — not cleared to `.loading`.
        #expect(isLoaded(services.loadState))

        provider.release()
        await task.value
        #expect(!services.isRefreshing)
        #expect(isLoaded(services.loadState))
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

    func aggregatedUsage(
        startDate _: Date,
        endDate _: Date,
        token _: SessionToken,
    ) async throws -> AggregatedUsage {
        AggregatedUsage(aggregations: [], totalCostCents: 0)
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

    func aggregatedUsage(
        startDate _: Date,
        endDate _: Date,
        token _: SessionToken,
    ) async throws -> AggregatedUsage {
        AggregatedUsage(aggregations: [], totalCostCents: 0)
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
