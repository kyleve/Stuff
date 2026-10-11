import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataCompatibilityOutputsTests {
    @Test func failedFreshSnapshotWriteCannotReopenCachedWidgets() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        await world.widgets.failPublication()
        await #expect(throws: (any Error).self) {
            try await world.outputs.widgets.publish(WidgetSnapshot(
                day: Date(timeIntervalSinceReferenceDate: 0),
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
        let outputs = world.outputs
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
        #expect(await world.widgets.compatibility.last?.allowsData == false)
        #expect(await !outputs.summary.requestAuthorization())
        #expect(await world.summary.requests == 0)
    }

    @Test func suspendedPublicationCannotWinAgainstWithdrawal() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let gate = CompatibilityOutputTestSupport.Gate()
        await world.summary.holdNextPublication(gate)
        let publication = Task {
            await world.outputs.summary.reconcile(
                enabled: true,
                time: .defaultMorning,
                body: "old totals",
            )
        }
        await gate.waitUntilEntered()
        try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
        let withdrawal = Task { await world.outputs.retire() }
        gate.resume()
        await publication.value
        await withdrawal.value
        #expect(await !world.summary.enabled)
        #expect(await world.widgets.compatibility.last?.allowsData == false)
        // Retiring this world is permanent even after a later build supports the floor.
        await world.store
            .setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        await world.outputs.summary.reconcile(
            enabled: true,
            time: .defaultMorning,
            body: "current totals",
        )
        #expect(await !world.summary.enabled)
    }

    @Test func widgetAccessOpensOnlyAfterFreshDataPublication() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let snapshot = WidgetSnapshot(
            day: Date(timeIntervalSinceReferenceDate: 0),
            year: 2026,
            dayRegions: [],
            totals: [:],
        )
        try await world.outputs.widgets.publish(snapshot)
        #expect(await world.widgets.snapshots == [snapshot])
        #expect(await world.widgets.compatibility.map(\.requiredVersion) == [nil, .initial])
        try await CompatibilityOutputTestSupport.makeIncompatible(world.store)
        await #expect(throws: DataCompatibilityError.self) {
            try await world.outputs.widgets.publish(snapshot)
        }
        #expect(await world.widgets.snapshots.count == 1)
        #expect(await world.widgets.compatibility.last?.allowsData == false)
    }
}
