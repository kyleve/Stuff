#if DEBUG
    import Testing
    @_spi(Testing) @testable import ThrowUI

    @MainActor
    struct ProjectorLabModelTests {
        @Test func simulatedConnectionUsesTypedOutputDemand() {
            let session = ThrowSession.fixture()
            let model = ProjectorLabModel(
                session: session,
                outputID: ProjectionOutputID(rawValue: "projector-lab-test"),
            )

            model.isConnected = true
            #expect(session.projectionOutputCount == 1)
            #expect(session.hasExternalDisplayOutput)

            model.disconnect()
            #expect(session.projectionOutputCount == 0)
            #expect(session.hasExternalDisplayOutput == false)
        }
    }
#endif
