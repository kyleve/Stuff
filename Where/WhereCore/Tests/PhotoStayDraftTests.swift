import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct PhotoStayDraftTests {
    private func day(_ d: Int) -> CalendarDay {
        .init(year: 2026, month: 6, day: d)
    }

    private func draft(_ places: [(Int, Region)]) throws -> PhotoStayDraft {
        let calendar = Calendar(identifier: .gregorian)
        let locations = try places.enumerated().map { index, item in
            let date = day(item.0).startOfDay(in: calendar).addingTimeInterval(Double(index))
            let observation = try #require(PhotoObservation(
                capturedAt: date,
                addedAt: date,
                coordinate: Coordinate(
                    latitude: 43,
                    longitude: -79,
                ),
                accuracy: nil,
            ))
            return DatedPhotoLocation(observation: observation, day: day(item.0), region: item.1)
        }
        return PhotoStayDraft(scan: .init(
            calendar: calendar,
            through: day(30),
            access: .limited,
            points: locations,
        ))
    }

    @Test func mixedTravelDayAndUserConfirmation() throws {
        let ontario = try #require(Region(rawValue: "ca-ON"))
        let quebec = try #require(Region(rawValue: "ca-QC"))
        var draft = try draft([(2, ontario), (2, ontario), (6, ontario), (6, quebec)])
        #expect(draft.report.totals == [ontario: 2, quebec: 1])
        let gap = try #require(draft.pendingGaps.first)
        #expect(gap == PhotoStay(region: ontario, start: day(3), end: day(5)))
        draft.decide(gap, include: true)
        #expect(draft.report.totals == [ontario: 5, quebec: 1])
        #expect(draft.approved.points.count == 4)
        #expect(draft.approved.assertedDays.count == 3)
        draft.edit(
            .init(region: ontario, start: day(2), end: day(6)),
            to: .init(region: quebec, start: day(2), end: day(3)),
        )
        #expect(draft.report.totals == [quebec: 3])
        #expect(draft.approved.points.count == 3)
        #expect(draft.confirmedGaps.isEmpty)
        #expect(draft.approved.points.allSatisfy { $0.region == quebec })
    }

    @Test func boundariesAndContraryEvidence() throws {
        let r = Region.california
        #expect(try draft([(1, r), (9, r)]).pendingGaps.count == 1)
        #expect(try draft([(1, r), (10, r)]).pendingGaps.isEmpty)
        #expect(try draft([(1, r)]).pendingGaps.isEmpty)
        #expect(try draft([(1, r), (4, .other), (9, r)]).pendingGaps.isEmpty)
        #expect(try draft([(1, r), (1, .newYork), (9, r), (9, .newYork)]).pendingGaps.isEmpty)
        var review = try draft([(1, r), (4, r), (9, r)])
        try review.decide(#require(review.pendingGaps.first), include: false)
        try review.decide(#require(review.pendingGaps.first), include: true)
        #expect(review.report.totals == [r: 7])
        let invalid = review.edit(nil, to: .init(region: r, start: day(5), end: day(3)))
        #expect(!invalid)
    }

    @Test func movingRetainsOriginalAndAddingPreservesConfirmedDays() throws {
        var review = try draft([(2, .california), (6, .california)])
        try review.decide(#require(review.pendingGaps.first), include: true)
        review.edit(nil, to: .init(region: .newYork, start: day(4), end: day(4)))
        #expect(review.report.totals == [.california: 5, .newYork: 1])
        var moved = try draft([(2, .california)])
        moved.edit(
            .init(region: .california, start: day(2), end: day(2)),
            to: .init(region: .newYork, start: day(3), end: day(3)),
        )
        let point = try #require(moved.approved.points.first)
        #expect(point.original.day == day(2))
        #expect(point.day == day(3))
        #expect(moved.approved.assertedDays.isEmpty)
    }
}
