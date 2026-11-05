import Foundation
import Testing
import UserNotifications
@testable import WhereCore

@MainActor
struct DataCompatibilityOutputsTests {
    @Test func retirementWithdrawsLateHistoryOutputAndPreservesTheIndependentUpdateAlert()
        async throws
    {
        let center = CompatibilityNotificationCenter()
        let widgets = CompatibilityWidgetRefresher()
        let access = try CompatibilityOutputTestSupport.access()
        let outputs = CompatibilityOutputTestSupport.outputs(
            access: access,
            center: center,
            widgets: widgets,
        )
        let updateID = "test-independent-update"
        try await center.add(UNNotificationRequest(
            identifier: updateID,
            content: UNMutableNotificationContent(),
            trigger: nil,
        ))
        await outputs.summary.reconcile(enabled: true, time: .defaultMorning, body: "Summary")
        await outputs.issues.reconcile(enabled: true, time: .defaultEvening, body: "Issues")
        try await outputs.widgets.publish(WidgetSnapshot(
            day: .init(year: 2026, month: 3, day: 15),
            version: DataCompatibilityPolicy.foundation.current,
            dayRegions: .complete([]),
            totals: .complete([:]),
        ))
        #expect(await widgets.receivedAccess == access.id)
        let gate = CompatibilityTestGate()
        await center.holdNextAdd(gate)
        let pending = Task {
            await outputs.reminders.reconcile(
                badgeCount: 3,
                scheduleDays: [Date()],
                reminderTime: .defaultEvening,
                enabled: true,
            )
        }
        await gate.waitUntilEntered()
        let retirement = Task { await outputs.retire() }
        try await DataCompatibilityTestSupport.waitUntil { access.isRevoked }
        pending.cancel()
        await gate.resume()
        await pending.value
        await retirement.value
        #expect(await center.pendingNotificationRequests().map(\.identifier) == [updateID])
        #expect(await center.deliveredNotificationIdentifiers() == [updateID])
        #expect(await center.badge == 0)
        #expect(await widgets.snapshot == nil)
        #expect(await widgets.withdrawalCount == 1)

        await outputs.summary.reconcile(enabled: true, time: .defaultMorning, body: "Obsolete")
        #expect(await center.pendingNotificationRequests().map(\.identifier) == [updateID])
        let replacement = try CompatibilityOutputTestSupport.outputs(
            access: CompatibilityOutputTestSupport.access(),
            center: center,
            widgets: widgets,
        )
        await replacement.summary.reconcile(enabled: true, time: .defaultMorning, body: "Current")
        await outputs.retire()
        #expect(await center.pendingNotificationRequests().map(\.content.body).contains("Current"))
        #expect(await widgets.withdrawalCount == 1)
    }
}
