import Foundation
import Testing
import WhereCore

struct WidgetSnapshotTests {
    @Test func wireFormatRetainsLogicalDatePolicyAndIndependentScopeEligibility() throws {
        let day = CalendarDay(year: 2026, month: 3, day: 15)
        let version = DataSemanticsVersion(major: 1, minor: 3, patch: 7)
        let snapshots = [
            WidgetSnapshot(day: day, history: .unavailable),
            WidgetSnapshot(
                day: day,
                version: version,
                dayRegions: .complete([]),
                totals: .complete([:]),
            ),
            WidgetSnapshot(
                day: day,
                version: version,
                dayRegions: .complete([.california]),
                totals: .needsReview,
            ),
            WidgetSnapshot(
                day: day,
                version: version,
                dayRegions: .needsReview,
                totals: .needsReview,
            ),
            WidgetSnapshot(
                day: day,
                version: version,
                dayRegions: .complete([.newYork]),
                totals: .complete([.newYork: 3]),
                appearances: [.newYork: .init(
                    color: .indigo,
                    emoji: "🗽",
                    symbolName: .building2Fill,
                )],
            ),
        ]
        for snapshot in snapshots {
            let encoded = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
            #expect(decoded == snapshot)
            #expect(decoded.day == day)
            #expect(decoded.year == day.year)
        }
    }

    @Test func priorUnassessedCacheCannotDecodeAsCompleteHistory() {
        let old = Data(
            #"{"day":794534400,"year":2026,"dayRegions":["us-CA"],"totals":["us-CA",1],"appearances":{}}"#
                .utf8,
        )
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(
            WidgetSnapshot.self,
            from: old,
        ) }
    }
}
