import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataCompatibilityOutputsTests {
    @Test func failedFreshSnapshotWriteCannotReopenCachedWidgets() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        await world.widgets.failPublication()
        await #expect(throws: (any Error).self) {
            try await world.services.outputs.widgets.publish(WidgetSnapshot(
                day: CompatibilityTestSupport.now,
                year: 2026,
                dayRegions: [],
                totals: [:],
            ))
        }
        #expect(await world.widgets.compatibility.allSatisfy { !$0.allowsData })
        #expect(await world.widgets.snapshots.isEmpty)
    }

    @Test func incompatiblePublicationWithdrawsEveryOwnedOutput() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let outputs = world.services.outputs
        await outputs.reminders.reconcile(
            badgeCount: 4,
            scheduleDays: [],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        await outputs.summary.reconcile(enabled: true, time: .defaultMorning, body: "summary")
        await outputs.issueAlerts.reconcile(enabled: true, time: .defaultEvening, body: "issues")
        try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
        await outputs.reminders.reconcile(
            badgeCount: 99,
            scheduleDays: [],
            reminderTime: .defaultEvening,
            enabled: true,
        )
        #expect(await world.reminders.badgeCount == 0)
        #expect(await !world.reminders.enabled)
        #expect(await !world.summary.enabled)
        #expect(await !world.issues.enabled)
        #expect(await world.widgets.compatibility.last?.requiredVersion == CompatibilityTestSupport
            .nextVersion)
        #expect(await !outputs.summary.requestAuthorization())
        #expect(await world.summary.requests == 0)
    }

    @Test func suspendedPublicationCannotWinAgainstWithdrawal() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let gate = CompatibilityOutputTestSupport.Gate()
        await world.summary.holdNextPublication(gate)
        let publication = Task {
            await world.services.outputs.summary.reconcile(
                enabled: true,
                time: .defaultMorning,
                body: "old totals",
            )
        }
        await gate.waitUntilEntered()
        try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
        let withdrawal = Task { await world.services.outputs.withdraw() }
        gate.resume()
        await publication.value
        await withdrawal.value
        #expect(await !world.summary.enabled)
        #expect(await world.widgets.compatibility.last?.allowsData == false)
        // An upgraded installation can publish again; the saved preference is independent.
        await world.store
            .setSupportedDataCompatibilityVersionForTesting(CompatibilityTestSupport.nextVersion)
        await world.services.outputs.summary.reconcile(
            enabled: true,
            time: .defaultMorning,
            body: "current totals",
        )
        #expect(await world.summary.enabled)
    }

    @Test func widgetAccessOpensOnlyAfterFreshDataPublication() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let snapshot = WidgetSnapshot(
            day: CompatibilityTestSupport.now,
            year: 2026,
            dayRegions: [],
            totals: [:],
        )
        try await world.services.outputs.widgets.publish(snapshot)
        #expect(await world.widgets.snapshots == [snapshot])
        #expect(await world.widgets.compatibility.map(\.requiredVersion) == [nil, .initial])
        try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
        await #expect(throws: DataCompatibilityError.self) {
            try await world.services.outputs.widgets.publish(snapshot)
        }
        #expect(await world.widgets.snapshots.count == 1)
        #expect(await world.widgets.compatibility.last?.allowsData == false)
    }
}
