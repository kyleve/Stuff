import Foundation
@_spi(Testing) import LedgerCore
import Testing

@MainActor
struct LedgerServicesTests {
    /// A fixed "now" in July 2026 (month 7), UTC, so prior-month invoice fetches
    /// (months 1..6) are deterministic.
    private func julyCalendarAndNow() -> (Calendar, @Sendable () -> Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        return (calendar, { now })
    }

    private func makeServices(
        provider: any DashboardProvider = ScriptedDashboardProvider(.failure(.network("unused"))),
        manualToken: String? = nil,
        autoToken: SessionToken? = nil,
    ) -> LedgerServices {
        let (calendar, now) = julyCalendarAndNow()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerServicesTests-\(UUID().uuidString)")
        let store = LedgerConfigStore(directory: directory)
        return LedgerServices(
            configStore: store,
            keychain: InMemoryKeychainStore(secret: manualToken),
            tokenSource: StubTokenSource(token: autoToken),
            provider: provider,
            loginItem: LoginItemController(backend: LoginItemRecorder()),
            calendar: calendar,
            now: now,
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
            invoiceCentsByMonth: [1: 100, 2: 200, 3: 300, 4: 400, 5: 500, 6: 600],
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
        // Year-to-date = prior months (1..6 = 2100) + current cycle live (5000).
        #expect(snapshot.yearToDateCents == 2100 + 5000)
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
}
