import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct WhereCompatibilityModelTests {
    @Test(.timeLimit(.minutes(1)))
    func ordinaryScopeRetirementWaitsForBootstrapCleanupAndRevokesWrites() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let model = WhereCompatibilityModel(bootstrap: bootstrap, initialState: .checking)
        await model.refresh()
        #expect(model.isCompatible)
        let services = try await bootstrap.makeServices()
        let store = try #require(bootstrap.lastDomainStore)
        let previousWithdrawals = bootstrap.withdrawals
        let gate = CompatibilityOperationGate()
        defer { gate.release() }
        bootstrap.withdrawalGate = gate
        var retired = false
        let retirement = Task {
            await model.retireScope(services)
            retired = true
        }
        while !gate.entered {
            try Task.checkCancellation()
            await Task.yield()
        }
        #expect(!retired)
        // Cleanup must not delay permit revocation or require a blocked UI state.
        while true {
            try Task.checkCancellation()
            do { try await store.validateDataAccess() }
            catch DataCompatibilityError.accessRevoked { break }
            await Task.yield()
        }
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await store.perform {}
        }
        gate.release()
        await retirement.value
        #expect(retired)
        #expect(bootstrap.withdrawals == previousWithdrawals + 1)
    }

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
