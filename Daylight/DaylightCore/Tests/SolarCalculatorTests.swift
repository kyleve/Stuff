@testable import DaylightCore
import Foundation
import Testing

struct SolarCalculatorTests {
    @Test(arguments: [
        "2026-03-08T12:00:00Z",
        "2026-06-21T12:00:00Z",
        "2026-11-01T12:00:00Z",
        "2026-12-21T12:00:00Z",
    ])
    func producesOrderedEventsOnLocalDay(iso: String) throws {
        let date = try #require(ISO8601DateFormatter().date(from: iso))
        let events = try SolarCalculator().events(on: date, site: .sanFrancisco)
        #expect(events.count == 2)
        #expect(events[0].date < events[1].date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(events.allSatisfy { calendar.isDate($0.date, inSameDayAs: date) })
        #expect(events[1].date.timeIntervalSince(events[0].date) > 8 * 3600)
    }

    @Test func summerReferenceAndPolarNight() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z"))
        let events = try SolarCalculator().events(on: date, site: .sanFrancisco)
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-06-21T12:48:00Z"))
        #expect(abs(events[0].date.timeIntervalSince(expected)) < 5 * 60)
        var polar = CaptureSettings.Site.sanFrancisco
        polar.latitude = 89
        #expect(try SolarCalculator().events(on: date, site: polar).isEmpty)
    }
}
