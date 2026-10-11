import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct WhereCompatibilityModelTests {
    @Test func handoffUnblocksBeforeCompatibleStateCanResumeLaunch() async throws {
        let bootstrap = try CompatibilityBootstrap()
        let model = WhereCompatibilityModel(bootstrap: bootstrap, initialState: .checking)
        await model.refresh()
        #expect(model.state == .recordingChoiceRequired)
        var notified = false
        model.onStateChange = { state in
            if case .compatible = state, !notified {
                #expect(!model.isCompatible)
                notified = true
            }
        }
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        await model.refresh()
        #expect(notified)
        #expect(model.isCompatible)
    }
}
