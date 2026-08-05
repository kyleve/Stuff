import Foundation
import RegionKit
import Testing
import WhereCore

/// Mirrors [`PostWriteReconcile`](../../Specifications/PostWriteReconcile/README.md)
/// fan-out tiers on the pure plan layer.
struct PostWriteReconcilePlanTests {
    private let issueSteps: [ReconcileStep] = [
        .invalidateIssues,
        .reconcileReminders,
        .reconcileIssueAlerts,
    ]

    @Test func issueOnlyOmitsWidgetPublish() {
        let plan = PostWriteReconcilePlan.forOutcome(.issueOnly)
        #expect(plan.steps == issueSteps)
    }

    @Test func dayDataChangedAppendsFullWidgetPublish() {
        let plan = PostWriteReconcilePlan.forOutcome(.dayDataChanged)
        #expect(plan.steps == issueSteps + [.publishWidgets])
    }

    @Test func sampleIngestUsesAfterIngestWidgetPolicy() {
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_735_689_600),
            coordinate: Coordinate(latitude: 37.78, longitude: -122.42),
            horizontalAccuracy: 10,
            source: .gpsSignificantChange,
        )
        let plan = PostWriteReconcilePlan.forOutcome(.sampleIngest(sample))
        #expect(plan.steps == issueSteps + [.publishWidgetsAfterIngest(sample)])
    }

    @Test func bulkAndManualDayPathsShareDayDataPlan() {
        let dayPlan = PostWriteReconcilePlan.forOutcome(.dayDataChanged)
        #expect(dayPlan.steps.last == .publishWidgets)
        #expect(!dayPlan.steps.contains { step in
            if case .publishWidgetsAfterIngest = step { return true }
            return false
        })
    }
}
