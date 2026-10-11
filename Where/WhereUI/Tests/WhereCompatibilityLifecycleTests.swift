import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereCompatibilityLifecycleTests {
    @Test func restoredHeadlessLaunchRequiresChoiceBeforeServices() async throws {
        let bootstrap = try CompatibilityBootstrap()
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: bootstrap.installation,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        let drive = Task { await runner.run() }
        defer { drive.cancel() }
        try await wait { runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility) }
        #expect(model.compatibility.state == .recordingChoiceRequired)
        #expect(bootstrap.makeServicesCount == 0)
        #expect(model.activeScope == nil)
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        await model.compatibility.refresh()
        try await wait { runner.phase.isReady }
        await drive.value
        #expect(bootstrap.makeServicesCount == 1)
        #expect(model.activeScope != nil)
    }

    @Test func historyChangeRetiresTheActiveScopeAndPreservesConsent() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: bootstrap.installation,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        await runner.run()
        #expect(runner.phase.isReady)
        let consent = try bootstrap.installation.resolve().recordingChoice
        let oldStore = try #require(bootstrap.lastDomainStore)
        let required = DataCompatibilityVersion(rawValue: 2)
        try await bootstrap.store.perform {
            try await bootstrap.store.addDataCompatibilityRequirement(.init(
                id: UUID(),
                version: required,
            ))
        }
        try await wait {
            model.compatibility.state == .updateRequired(required) && model.activeScope == nil
        }
        #expect(try bootstrap.installation.resolve().recordingChoice == consent)
        #expect(bootstrap.makeServicesCount == 1)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            _ = try await oldStore.allSamples()
        }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw Timeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private struct Timeout: Error {}
}
