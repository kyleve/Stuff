@testable import LifecycleKit
import SwiftUI
import Testing

private struct ResetError: Error {}

@MainActor
struct LauncherResetTests {
    @Test func resetRunsTeardownThenRelaunches() async {
        var events: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("launch") { _ in events.append("launch") }
        })
        await launcher.run()
        #expect(events == ["launch"])
        #expect(launcher.phase.isReady)

        await launcher.reset(LaunchSequence {
            Work("teardown") { _ in events.append("teardown") }
        })
        #expect(events == ["launch", "teardown", "launch"])
        #expect(launcher.phase.isReady)
    }

    @Test func resetRunsTeardownStepsInOrder() async {
        var events: [String] = []
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {})
        await launcher.run()

        await launcher.reset(LaunchSequence {
            Work("stop-gps") { _ in events.append("stop-gps") }
            Work("clear-store") { _ in events.append("clear-store") }
            Work("clear-widget") { _ in events.append("clear-widget") }
        })
        #expect(events == ["stop-gps", "clear-store", "clear-widget"])
    }

    @Test func resetStepCanPresentTeardownUI() async throws {
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {})
        await launcher.run()

        let task = Task { @MainActor in
            await launcher.reset(LaunchSequence {
                Interactive("signing-out") { _ in Text("Signing out") }
            })
        }
        try await waitUntil { launcher.phase.runningStepID == "signing-out" }
        #expect(launcher.phase.runningHandle?.presentation != nil)

        launcher.phase.runningHandle?.complete()
        await task.value
        #expect(launcher.phase.isReady)
    }

    @Test func failedTeardownParksInFailedAndSkipsRelaunch() async {
        var relaunched = false
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("launch") { _ in relaunched = true }
        })
        await launcher.run()
        relaunched = false

        await launcher.reset(LaunchSequence {
            Work("teardown") { _ in throw ResetError() }
        })
        #expect(launcher.phase.failure?.stepID == "teardown")
        #expect(!relaunched)
    }
}
