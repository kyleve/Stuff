import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct WidgetSnapshotRankingTests {
    private static func snapshot(
        dayRegions: Set<Region>,
        totals: [Region: Int],
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            day: .init(year: 2026, month: 3, day: 15),
            version: DataCompatibilityPolicy.foundation.current,
            dayRegions: .complete(dayRegions),
            totals: .complete(totals),
        )
    }

    @Test func unresolvedYearPreservesACompleteDayWithoutExposingYearCounts() {
        let snapshot = WidgetSnapshot(
            day: .init(year: 2026, month: 3, day: 15),
            version: RecordingEvidencePolicy.version,
            dayRegions: .complete([.california]),
            totals: .needsReview,
        )
        #expect(snapshot.orderedDayRegions == .complete([.california]))
        #expect(snapshot.rankedTotals(maxRows: 3) == .unavailable(.needsReview))
        #expect(WhereFormat.widgetYearAccessibilityValue(content: snapshot.rankedTotals(maxRows: 3))
            == WidgetHistoryStatus.needsReview.accessibilityValue)
    }

    @Test func unavailableAndNeedsReviewStayDistinctFromAnEmptyDay() {
        let unavailable = PreviewSupport.unavailableWidgetSnapshot()
        let review = PreviewSupport.widgetSnapshotNeedingReview()
        #expect(unavailable.orderedDayRegions == .unavailable(.unavailable))
        #expect(unavailable.rankedTotals(maxRows: 3) == .unavailable(.unavailable))
        #expect(review.orderedDayRegions == .unavailable(.needsReview))
        #expect(WhereFormat.widgetTodayAccessibilityValue(content: review.orderedDayRegions)
            == WidgetHistoryStatus.needsReview.accessibilityValue)
        #expect(WhereFormat.widgetTodayAccessibilityValue(content: unavailable.orderedDayRegions)
            == WidgetHistoryStatus.unavailable.accessibilityValue)
        #expect(WidgetHistoryStatus.needsReview.accessibilityValue != WhereFormat
            .widgetTodayAccessibilityValue(regions: []))
    }

    @Test func rankedTotalsOrderAndCapMatchTheApp() {
        let snapshot = Self.snapshot(
            dayRegions: [],
            totals: [.california: 132, .newYork: 41, .canada: 9, .europeanUnion: 4, .other: 2],
        )
        guard case let .complete(ranked) = snapshot.rankedTotals(maxRows: 3) else {
            Issue.record("The complete fixture must remain complete")
            return
        }
        #expect(ranked.map(\.region) == [.california, .newYork, .canada])
        #expect(ranked.map(\.days) == [132, 41, 9])
    }

    @Test func orderedDayRegionsFollowDeclarationOrder() {
        let snapshot = Self.snapshot(
            dayRegions: [.other, .california, .canada],
            totals: [:],
        )
        #expect(snapshot.orderedDayRegions == .complete([.california, .canada, .other]))
    }
}
