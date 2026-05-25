import Foundation
import Testing
import WhereCore

struct YearReportTests {
    @Test func yearReport_sortsDaysAscending() {
        let later = DayPresence(date: Date(timeIntervalSince1970: 2_000_000_000), regions: [.newYork])
        let earlier = DayPresence(date: Date(timeIntervalSince1970: 1_000_000_000), regions: [.california])
        let report = YearReport(year: 2026, days: [later, earlier], totals: [:])
        #expect(report.days.first?.date == earlier.date)
        #expect(report.days.last?.date == later.date)
    }
}
