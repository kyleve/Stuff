import Foundation
import RegionKit
@testable import WhereCore

enum ElsewhereTestSupport {
    static let calendar = WhereCoreTestSupport.calendar()
    static let vegas = Coordinate(latitude: 36.1699, longitude: -115.1398)
    static let portland = Coordinate(latitude: 45.5152, longitude: -122.6784)
    static let ocean = Coordinate(latitude: 0, longitude: -160)

    static func sample(_ coordinate: Coordinate, day: Int = 1) -> LocationSample {
        LocationSample(
            timestamp: CalendarDay(year: 2026, month: 6, day: day).startOfDay(in: calendar),
            coordinate: coordinate,
            horizontalAccuracy: 10,
            source: .gpsVisit,
        )
    }

    static func input(
        samples: [LocationSample] = [],
        manualDays: [DayPresence] = [],
        revisions: [SampleAttributionRevision] = [],
        primaryRegions: Set<Region> = [.california, .newYork],
    ) -> ElsewhereInput {
        var winners: [UUID: SampleAttributionRevision] = [:]
        for revision in revisions {
            if let old = winners[revision.sampleID],
               !SampleAttributionRevision.newer(revision, than: old) { continue }
            winners[revision.sampleID] = revision
        }
        let history = LocationHistoryProjection(
            samples: samples.map {
                AttributedLocationSample(
                    sample: $0,
                    regions: winners[$0.id]?.replacementRegions ?? [.other],
                )
            },
            revisions: revisions,
        )
        let report = DayAggregator(calendar: calendar, timeZone: calendar.timeZone).report(
            for: 2026,
            history: history.samples,
            manualDays: manualDays,
        )
        return ElsewhereInput(
            report: report,
            primaryRegions: primaryRegions,
            history: history,
            manualDays: manualDays,
            calendar: calendar,
        )
    }
}
