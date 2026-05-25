import Foundation
import Testing
import WhereCore

struct WhereCoreCodableTests {
    @Test func dayPresence_encodesRegionsSorted() throws {
        let day = DayPresence(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            regions: [.newYork, .canada, .california],
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(day)
        let json = String(decoding: data, as: UTF8.self)
        let californiaIndex = json.range(of: "california")?.lowerBound
        let canadaIndex = json.range(of: "canada")?.lowerBound
        let newYorkIndex = json.range(of: "newYork")?.lowerBound
        #expect(californiaIndex != nil)
        #expect(canadaIndex != nil)
        #expect(newYorkIndex != nil)
        if let c = californiaIndex, let k = canadaIndex, let n = newYorkIndex {
            #expect(c < k)
            #expect(k < n)
        }
    }

    @Test func dayPresence_decodesBackToSameRegions() throws {
        let original = DayPresence(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            regions: [.california, .newYork],
        )
        let data = try JSONEncoder().encode(original)
        let round = try JSONDecoder().decode(DayPresence.self, from: data)
        #expect(round == original)
    }

    @Test func yearReport_sortsDaysAscending() {
        let later = DayPresence(date: Date(timeIntervalSince1970: 2_000_000_000), regions: [.newYork])
        let earlier = DayPresence(date: Date(timeIntervalSince1970: 1_000_000_000), regions: [.california])
        let report = YearReport(year: 2026, days: [later, earlier], totals: [:])
        #expect(report.days.first?.date == earlier.date)
        #expect(report.days.last?.date == later.date)
    }
}
