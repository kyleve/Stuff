import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct AircraftSourceSettingsModelTests {
    @Test func replacementCredentialStaysIsolatedUntilUseSource() async {
        let session = ThrowSession.fixture()
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .adsbExchange
        model.replaceCredential()
        model.rapidAPIKey = "replacement-secret-9999"

        await model.test()

        #expect(model.validation == .succeeded)
        #expect(session.rapidAPICredentialState == .missing)

        await model.useSource()

        #expect(session.rapidAPICredentialState == .saved(lastFour: "9999"))
        #expect(session.sourceChoice == .adsbExchange)
    }

    @Test func andApplySavesAFlightradar24CredentialInOneAction() async {
        let session = ThrowSession.fixture()
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .flightradar24
        model.rapidAPIKey = "fr24-replacement-1234"

        #expect(model.isEditingCredential)
        #expect(model.canTestAndApply)

        await model.testAndApply()

        #expect(session.flightradar24CredentialState == .saved(lastFour: "1234"))
        #expect(session.sourceChoice == .flightradar24)
        #expect(model.isEditingCredential == false)
        #expect(model.validation == .succeeded)
    }

    @Test func switchingToAMisconfiguredCredentialSourceOpensItsEditor() {
        let session = ThrowSession.fixture()
        session.rapidAPICredentialState = .saved(lastFour: "9999")
        let model = AircraftSourceSettingsModel(session: session)

        model.choice = .adsbExchange
        #expect(model.isEditingCredential == false)

        model.choice = .flightradar24
        #expect(model.isEditingCredential)
        #expect(model.canTestAndApply == false)
    }

    @Test func editingTestedConfigurationInvalidatesValidatedDraft() async {
        let session = ThrowSession.fixture()
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .adsbExchange
        model.replaceCredential()
        model.rapidAPIKey = "replacement-secret-9999"

        await model.test()
        #expect(model.validation == .succeeded)
        #expect(model.canUseSource)

        model.pollingIntervalSeconds = 60

        #expect(model.validation == .untested)
        #expect(model.canUseSource == false)
    }

    @Test func lateSuccessfulTestCannotRestoreAnInvalidatedDraft() async {
        let transport = DeferredSourceTestTransport()
        let session = ThrowSession.fixture(cloudTransport: transport)
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .adsbExchange
        model.replaceCredential()
        model.rapidAPIKey = "replacement-secret-9999"

        let testTask = Task { await model.test() }
        await transport.waitForRequest()
        model.pollingIntervalSeconds = 60
        await transport.succeed()
        await testTask.value

        #expect(model.validation == .untested)
        #expect(model.canUseSource == false)
    }

    @Test func recentFlightradar24UsageProjectsTheSelectedCadence() async throws {
        let transport = Flightradar24UsageTransport()
        let session = ThrowSession.fixture(cloudTransport: transport)
        try await session.credentialStore.save(
            AircraftCredential(secret: "fr24-token"),
            for: .flightradar24,
        )
        session.flightradar24CredentialState = .saved(lastFour: "oken")
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .flightradar24
        model.pollingIntervalSeconds = 300

        await model.loadFlightradar24Usage()

        guard case let .loaded(report) = model.flightradar24UsageState else {
            Issue.record("Expected loaded FR24 usage")
            return
        }
        #expect(report.requestCount == 12)
        #expect(report.credits == 2400)
        #expect(model.flightradar24CreditEstimate?.averageCreditsPerRequest == 200)
        #expect(model.flightradar24CreditEstimate?.creditsPerActiveHour == 2400)

        await model.loadFlightradar24Usage()
        #expect(await transport.requestCount() == 1)
    }

    @Test func usageRateLimitDoesNotClaimTheAccountQuotaWasReached() async throws {
        let transport = Flightradar24UsageRateLimitTransport()
        let session = ThrowSession.fixture(cloudTransport: transport)
        try await session.credentialStore.save(
            AircraftCredential(secret: "fr24-token"),
            for: .flightradar24,
        )
        session.flightradar24CredentialState = .saved(lastFour: "oken")
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .flightradar24

        await model.loadFlightradar24Usage()

        #expect(model.flightradar24UsageState == .rateLimited)
        await model.loadFlightradar24Usage()
        #expect(await transport.requestCount() == 1)
    }

    @Test func malformedUsageReportDoesNotClaimTheLiveFeedChanged() async throws {
        let session = ThrowSession.fixture(
            cloudTransport: Flightradar24MalformedUsageTransport(),
        )
        try await session.credentialStore.save(
            AircraftCredential(secret: "fr24-token"),
            for: .flightradar24,
        )
        session.flightradar24CredentialState = .saved(lastFour: "oken")
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .flightradar24

        await model.loadFlightradar24Usage()

        #expect(model.flightradar24UsageState == .unexpectedResponse)
    }
}

private actor DeferredSourceTestTransport: HTTPTransport {
    private var continuation: CheckedContinuation<HTTPResponse, Error>?

    func response(for _: HTTPRequest) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForRequest() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func succeed() {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: Data(#"{"ac":[],"now":1787594400,"total":0}"#.utf8),
        )
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private actor Flightradar24UsageTransport: HTTPTransport {
    private var requests = 0

    func response(for request: HTTPRequest) async throws -> HTTPResponse {
        requests += 1
        #expect(request.url.path() == "/api/usage")
        return HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: Data(
                """
                {"data":[{
                  "endpoint":"live/flight-positions/full?{filters}",
                  "request_count":12,
                  "credits":2400
                }]}
                """.utf8,
            ),
        )
    }

    func requestCount() -> Int {
        requests
    }
}

private actor Flightradar24UsageRateLimitTransport: HTTPTransport {
    private var requests = 0

    func response(for _: HTTPRequest) async throws -> HTTPResponse {
        requests += 1
        return HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": "60"],
            data: Data(),
        )
    }

    func requestCount() -> Int {
        requests
    }
}

private struct Flightradar24MalformedUsageTransport: HTTPTransport {
    func response(for _: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: Data(#"{"data":[{"endpoint":false}]}"#.utf8),
        )
    }
}
