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
