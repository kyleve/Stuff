import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataCompatibilityOutputsTests {
    @Test func teardownWithdrawsOutputsEvenWhenWidgetMetadataFails() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        await world.reminders.reconcile(
            badgeCount: 4,
            scheduleDays: [],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        await world.summary.reconcile(enabled: true, time: .defaultMorning, body: "summary")
        await world.issues.reconcile(enabled: true, time: .defaultEvening, body: "issues")
        struct Unavailable: Error {}
        await world.widgets.failNextCompatibilityPublication(with: Unavailable())

        await world.outputs.withdraw()

        #expect(await world.reminders.badgeCount == 0)
        #expect(await !world.reminders.enabled)
        #expect(await !world.summary.enabled)
        #expect(await !world.issues.enabled)
    }

    @Test(.timeLimit(.minutes(1)))
    func withdrawalDoesNotWaitForAnAlreadyStartedPublication() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let gate = CompatibilityOutputTestSupport.Gate()
        await world.summary.holdNextPublication(gate)
        let publication = Task {
            await world.summary.reconcile(
                enabled: true,
                time: .defaultMorning,
                body: "old totals",
            )
        }
        await gate.waitUntilEntered()
        await world.outputs.withdraw()
        #expect(await !world.summary.enabled)
        #expect(await world.widgets.compatibility.last?.allowsData == false)

        // The simpler contract permits this late display. It grants no store write access.
        gate.resume()
        await publication.value
        #expect(await world.summary.enabled)
    }
}
