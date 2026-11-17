import Testing
@testable import WhereUI

@MainActor
struct MainTabsSnapshotReadinessTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func completionCanPrecedeOrFollowTheHook(completesFirst: Bool) async {
        let readiness = MainTabsSnapshotReadiness()
        let mount = readiness.registerMount()
        mount.didActivate = completesFirst
        let waiter = Task.immediate {
            await readiness.waitForActivation()
            #expect(mount.didActivate)
        }
        await Task.yield()
        mount.didActivate = true
        await waiter.value
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cancellationReleasesTheWaitForTheNextMount(beforeMount: Bool) async {
        let readiness = MainTabsSnapshotReadiness()
        let previous = beforeMount ? nil : readiness.registerMount()
        let canceled = Task.immediate { await readiness.waitForActivation() }
        await Task.yield()
        canceled.cancel()
        await canceled.value

        var current: MainTabsSnapshotReadiness.Mount?
        let next = Task.immediate {
            await readiness.waitForActivation()
            #expect(current?.didActivate == true)
        }
        // A late completion from the canceled capture cannot release the new hook.
        previous?.didActivate = true
        await Task.yield()
        current = readiness.registerMount()
        await Task.yield()
        current?.didActivate = true
        await next.value
    }

    @Test(.timeLimit(.minutes(1)))
    func completedCaptureCannotSatisfyTheNextMount() async {
        let readiness = MainTabsSnapshotReadiness()
        let previous = readiness.registerMount()
        previous.didActivate = true
        await readiness.waitForActivation()

        let current = readiness.registerMount()
        let next = Task.immediate {
            await readiness.waitForActivation()
            #expect(current.didActivate)
        }
        await Task.yield()
        current.didActivate = true
        await next.value
    }
}
