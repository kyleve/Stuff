import LifecycleKit
import Testing
@testable import WhereUI

@MainActor
struct PrepareProtectedDataStepTests {
    @Test func preparationIsAwaitedBeforeTheFollowingLaunchNode() async {
        let gate = BackupKeyAccessGate()
        var prepared = false
        let step = PrepareProtectedDataStep {
            _ = await gate.wait()
            prepared = true
        }
        let runner = LifecycleRunner(reason: .undetermined, plan: LaunchPlan(step))
        let launch = Task { await runner.run() }
        await gate.waitForArrival()
        #expect(prepared == false)
        #expect(runner.phase.isReady == false)
        await gate.release()
        await launch.value
        #expect(prepared)
        #expect(runner.phase.isReady)
    }
}
