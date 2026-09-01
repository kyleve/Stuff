import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func calibrationDemandSynchronizesDraftAndAcceptsFullScreenOutputChoice() {
        let session = ThrowSession.fixture()
        let outputs = ControllerProjectionOutputs()
        let model = OnboardingFlowModel(session: session, outputs: outputs)
        model.step = .calibration

        #expect(model.canContinue == false)

        model.calibrationOutputChoice = .fullScreenPreview

        model.beginCalibration()
        model.screenTopBearing = 123
        model.safeInsetPercent = 12

        #expect(session.isCalibrating)
        #expect(session.screenTopBearing == 123)
        #expect(session.safeInsetPercent == 12)
        #expect(model.canContinue)
        #expect(model.didVerifyFullScreenPreview == false)

        model.markFullScreenPreviewPresented()
        #expect(model.didVerifyFullScreenPreview)
        #expect(model.canContinue)

        model.calibrationOutputChoice = .externalDisplay
        #expect(model.didVerifyFullScreenPreview == false)
        #expect(model.canContinue == false)

        model.endCalibration()
        #expect(session.isCalibrating == false)
    }

    @Test func equalQuietEndpointsBlockAppearanceStep() {
        let session = ThrowSession.fixture()
        let model = OnboardingFlowModel(
            session: session,
            outputs: ControllerProjectionOutputs(),
        )
        model.step = .appearance
        model.quietEnabled = true
        model.quietEnd = model.quietStart

        #expect(model.quietScheduleIsValid == false)
        #expect(model.canContinue == false)

        model.quietEnd = model.quietStart.addingTimeInterval(60)
        #expect(model.quietScheduleIsValid)
        #expect(model.canContinue)
    }

    @Test func tappingSelectedSourcePreservesItsValidatedDraft() async {
        let model = OnboardingFlowModel(
            session: ThrowSession.fixture(),
            outputs: ControllerProjectionOutputs(),
        )
        model.sourceChoice = .adsbExchange
        model.rapidAPIKey = "replacement-secret-9999"
        await model.testSource()

        #expect(model.sourceValidation == .succeeded)
        #expect(model.hasStagedRapidAPICredential)

        model.sourceChoice = .adsbExchange

        #expect(model.sourceValidation == .succeeded)
        #expect(model.hasStagedRapidAPICredential)
        #expect(model.rapidAPICredentialState == .saved(lastFour: "9999"))
    }

    @Test func editingValidatedSourceInvalidatesItsStagedCredential() async {
        let model = OnboardingFlowModel(
            session: ThrowSession.fixture(),
            outputs: ControllerProjectionOutputs(),
        )
        model.sourceChoice = .adsbExchange
        model.rapidAPIKey = "replacement-secret-9999"
        await model.testSource()

        #expect(model.sourceValidation == .succeeded)
        #expect(model.hasStagedRapidAPICredential)

        model.pollingIntervalSeconds = 60

        #expect(model.sourceValidation == .untested)
        #expect(model.hasStagedRapidAPICredential == false)
        #expect(model.rapidAPICredentialState == .missing)
    }

    @Test func lateSourceSuccessCannotRestoreAnInvalidatedDraft() async {
        let transport = DeferredOnboardingSourceTestTransport()
        let model = OnboardingFlowModel(
            session: ThrowSession.fixture(cloudTransport: transport),
            outputs: ControllerProjectionOutputs(),
        )
        model.sourceChoice = .adsbExchange
        model.rapidAPIKey = "replacement-secret-9999"

        let testTask = Task { await model.testSource() }
        await transport.waitForRequest()
        model.pollingIntervalSeconds = 60
        await transport.succeed()
        await testTask.value

        #expect(model.sourceValidation == .untested)
        #expect(model.hasStagedRapidAPICredential == false)
        #expect(model.rapidAPIKey == "replacement-secret-9999")
    }
}

private actor DeferredOnboardingSourceTestTransport: HTTPTransport {
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
        continuation?.resume(returning: HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: Data(#"{"ac":[],"now":1787594400,"total":0}"#.utf8),
        ))
        continuation = nil
    }
}
